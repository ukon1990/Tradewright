#!/usr/bin/env python3
"""Code-quality gate for AuctionHelper (ratchet against scripts/lint-baseline.json).

Checks:
  * luacheck (config: .luacheckrc) over all of src/  -> per-file warning counts
  * file length, function length, cyclomatic complexity and parameter count
    for hand-written Lua (src/**, excluding tests/ and generated data/)

Existing debt is recorded in the baseline; the check fails only when something is
new or got worse. Improvements are reported so the baseline can be tightened.

Usage:
  python3 scripts/lint.py                     # check (npm run lint)
  python3 scripts/lint.py --update-baseline   # rewrite baseline (npm run lint:baseline)
"""

from __future__ import annotations

import bisect
import json
import os
import re
import shutil
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT / "scripts" / "lint-baseline.json"

# Limits (keep in sync with .agents/skills/wow-addon-issue-work/focus/code-quality.md)
LIMITS = {"file_lines": 700, "lines": 40, "ccn": 10, "params": 5}
METRIC_LABEL = {"lines": "length", "ccn": "complexity", "params": "parameters"}

TOKEN_RE = re.compile(
    r"--\[(?P<lc>=*)\[.*?\](?P=lc)\]"  # long comment
    r"|--[^\n]*"  # line comment
    r"|\[(?P<ls>=*)\[.*?\](?P=ls)\]"  # long string
    r"|\"(?:\\.|[^\"\\\n])*\"|'(?:\\.|[^'\\\n])*'"  # short strings
    r"|(?P<name>[A-Za-z_]\w*)"
    r"|(?P<num>\d[\w.]*)"
    r"|(?P<op>\.\.\.|\S)",
    re.S,
)
BRANCHES = {"if", "elseif", "for", "while", "repeat", "and", "or"}
KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in",
    "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while",
}
NAME_PARTS = {".", ":"}


def tokens(src: str):
    """Yield (kind, text, line) for code tokens; comments and strings are dropped."""
    newlines = [i for i, ch in enumerate(src) if ch == "\n"]
    for m in TOKEN_RE.finditer(src):
        kind = "name" if m.group("name") else "op" if m.group("op") else None
        if kind:
            yield kind, m.group(0), bisect.bisect_left(newlines, m.start()) + 1


def scan_functions(path: Path) -> list[dict]:
    """Return [{name, line, lines, ccn, params}] for every function in a Lua file."""
    toks = list(tokens(path.read_text(encoding="utf-8", errors="replace")))
    stack, funcs = [], []
    for i, (kind, text, line) in enumerate(toks):
        if kind != "name":
            continue
        if text in BRANCHES:
            fn = next((f for f in reversed(stack) if f["kind"] == "function"), None)
            if fn:
                fn["ccn"] += 1
        if text == "function":
            stack.append(open_function(toks, i, stack))
        elif text in ("if", "do", "repeat"):
            stack.append({"kind": text})
        elif text in ("end", "until"):
            if not stack:
                raise SyntaxError(f"{path}:{line}: unbalanced '{text}'")
            block = stack.pop()
            if block["kind"] == "function":
                block["lines"] = line - block["line"] + 1
                funcs.append({k: block[k] for k in ("name", "line", "lines", "ccn", "params")})
    if stack:
        raise SyntaxError(f"{path}: {len(stack)} unclosed block(s)")
    return funcs


def open_function(toks, i, stack) -> dict:
    """Build a function frame for the 'function' keyword at toks[i]."""
    j, name = i + 1, ""
    while j < len(toks) and toks[j][1] != "(":
        name += toks[j][1]
        j += 1
    if not name:  # anonymous: use the assignment target (x.y = function / Key = function)
        k, parts = i - 1, []
        if k >= 0 and toks[k][1] == "=":
            k -= 1
            while k >= 0 and ((toks[k][0] == "name" and toks[k][1] not in KEYWORDS) or toks[k][1] in NAME_PARTS):
                parts.insert(0, toks[k][1])
                k -= 1
        name = "".join(parts) or "<anon>"
        outer = next((f["name"] for f in reversed(stack) if f["kind"] == "function"), None)
        if outer:
            name = f"{outer}/{name}"
    params, j = 0, j + 1
    while j < len(toks) and toks[j][1] != ")":
        params += toks[j][0] == "name" or toks[j][1] == "..."
        j += 1
    return {"kind": "function", "name": name, "line": toks[i][2], "ccn": 1, "params": params}


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def metric_files() -> list[Path]:
    return sorted(
        p for p in (ROOT / "src").rglob("*.lua") if not {"tests", "data"} & set(p.relative_to(ROOT).parts)
    )


def run_luacheck() -> list[tuple[str, int, str, str]]:
    exe = os.environ.get("LUACHECK") or shutil.which("luacheck")
    if not exe:
        sys.exit(
            "lint: luacheck not found. Install it (Arch: sudo pacman -S luacheck; "
            "elsewhere: luarocks install luacheck) or set LUACHECK=/path/to/luacheck. "
            "See README.md#setup."
        )
    proc = subprocess.run(
        [exe, "src", "--formatter", "plain", "--codes", "-q"], cwd=ROOT, capture_output=True, text=True
    )
    if proc.returncode > 2:
        sys.exit(f"lint: luacheck failed ({proc.returncode}):\n{proc.stdout}{proc.stderr}")
    found = []
    for raw in proc.stdout.splitlines():
        m = re.match(r"^(.+?):(\d+):\d+: \((\w\d+)\) (.*)$", raw)
        if m:
            found.append((Path(m.group(1)).as_posix(), int(m.group(2)), m.group(3), m.group(4)))
    return found


def collect() -> tuple[dict, list, dict]:
    """Return (state, luacheck findings, function records by file) for the current tree."""
    findings = run_luacheck()
    lc = defaultdict(Counter)
    for path, _, code, _ in findings:
        lc[path][code] += 1
    files, functions, records = {}, defaultdict(dict), {}
    for path in metric_files():
        key = rel(path)
        n = len(path.read_text(encoding="utf-8", errors="replace").splitlines())
        if n > LIMITS["file_lines"]:
            files[key] = n
        records[key] = scan_functions(path)
        by_name = defaultdict(lambda: defaultdict(list))
        for f in records[key]:
            for metric in METRIC_LABEL:
                if f[metric] > LIMITS[metric]:
                    by_name[f["name"]][metric].append(f[metric])
        for name, metrics in by_name.items():
            functions[key][name] = {m: sorted(v, reverse=True) for m, v in metrics.items()}
    state = {
        "luacheck": {p: dict(sorted(c.items())) for p, c in sorted(lc.items())},
        "files": dict(sorted(files.items())),
        "functions": {p: dict(sorted(f.items())) for p, f in sorted(functions.items())},
    }
    return state, findings, records


def worse(cur: list[int], base: list[int]) -> bool:
    return len(cur) > len(base) or any(c > b for c, b in zip(cur, base))


def compare(state: dict, base: dict, findings: list, records: dict) -> tuple[list[str], int]:
    fails, improved = [], 0
    for path, line, code, msg in findings:
        if code.startswith("E"):
            fails.append(f"{path}:{line}: ({code}) {msg}")
    for path, codes in state["luacheck"].items():
        for code, n in codes.items():
            allowed = base["luacheck"].get(path, {}).get(code, 0)
            if n > allowed and not code.startswith("E"):
                fails.append(f"{path}: luacheck {code} x{n} (baseline {allowed}):")
                fails += [f"    {p}:{ln}: {m}" for p, ln, c, m in findings if p == path and c == code]
    for path, n in state["files"].items():
        allowed = max(LIMITS["file_lines"], base["files"].get(path, 0))
        if n > allowed:
            fails.append(f"{path}: {n} lines (limit {LIMITS['file_lines']}, baseline {allowed}) - split the file")
    for path, names in state["functions"].items():
        for name, metrics in names.items():
            for metric, values in metrics.items():
                allowed = base["functions"].get(path, {}).get(name, {}).get(metric, [])
                if worse(values, allowed):
                    lines = [f["line"] for f in records[path] if f["name"] == name]
                    fails.append(
                        f"{path}:{lines[0]}: function '{name}' {METRIC_LABEL[metric]} {values[0]} "
                        f"(limit {LIMITS[metric]}, baseline {allowed or 'none'})"
                    )
    for section in ("luacheck", "files", "functions"):
        if json.dumps(base[section], sort_keys=True) != json.dumps(state[section], sort_keys=True):
            improved += 1
    return fails, improved


def main() -> int:
    state, findings, records = collect()
    errors = [f for f in findings if f[2].startswith("E")]
    if "--update-baseline" in sys.argv:
        if errors:
            print("lint: refusing to baseline luacheck errors:", *errors, sep="\n  ")
            return 1
        BASELINE.write_text(json.dumps(state, indent=1) + "\n", encoding="utf-8")
        print(f"lint: baseline written to {rel(BASELINE)}")
        return 0
    base = json.loads(BASELINE.read_text(encoding="utf-8")) if BASELINE.exists() else {}
    base = {k: base.get(k, {}) for k in ("luacheck", "files", "functions")}
    fails, changed = compare(state, base, findings, records)
    warnings = sum(sum(c.values()) for c in state["luacheck"].values())
    nfuncs = sum(len(v) for v in state["functions"].values())
    print(
        f"lint: {warnings} luacheck warnings, {len(state['files'])} files > {LIMITS['file_lines']} lines, "
        f"{nfuncs} functions over limits (lines {LIMITS['lines']}, complexity {LIMITS['ccn']}, "
        f"params {LIMITS['params']})"
    )
    if fails:
        print("FAIL - new or worse than baseline (fix the code; do not loosen the baseline):")
        print(*fails, sep="\n")
        return 1
    if changed:
        print("OK - debt went down vs baseline. Lock it in: npm run lint:baseline")
    else:
        print("OK - matches baseline")
    return 0


if __name__ == "__main__":
    sys.exit(main())
