#!/usr/bin/env python3
"""Run AuctionHelper offline tests (every tests/test_*.lua under Lua 5.1)."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LUA = "lua5.1"


def main() -> int:
    tests = sorted((ROOT / "tests").glob("test_*.lua"))
    if not tests:
        print("no tests/test_*.lua found", file=sys.stderr)
        return 2
    failed = []
    for test in tests:
        cmd = [LUA, str(test)]
        print("Running:", " ".join(cmd), flush=True)
        if subprocess.run(cmd, cwd=str(ROOT)).returncode != 0:
            failed.append(test.name)
    if failed:
        print("FAILED: " + ", ".join(failed), file=sys.stderr)
        return 1
    print(f"All {len(tests)} test files passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
