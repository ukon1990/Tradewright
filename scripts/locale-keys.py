#!/usr/bin/env python3
"""Translatable text of the addon.

  python3 scripts/locale-keys.py           # check the translation files (part of npm test)
  python3 scripts/locale-keys.py --list    # print every text that can be translated

Code marks shown text as L["..."] (see src/Tradewright/src/core/Tradewright_Locale.lua). The check
fails when a translation file translates a text the code no longer uses, which is how a reworded
label would otherwise lose its translation without anyone noticing.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
LOCALE_DIR = SRC / "Tradewright" / "src" / "locale"
KEY = re.compile(r'L\[("(?:[^"\\\n]|\\.)*")\]')
# Words handed to Tradewright:Plural are looked up too: Plural(count, "mail") or Plural(count, "item has", "items have").
PLURAL = re.compile(r'Plural\([^,()]+,\s*"([^"]+)"(?:,\s*"([^"]+)")?\)')
TRANSLATED = re.compile(r'^\s*\[("(?:[^"\\\n]|\\.)*")\]\s*=', re.M)


def code_files():
    for path in sorted(SRC.rglob("*.lua")):
        parts = path.relative_to(SRC).parts
        if "tests" not in parts and "data" not in parts and "locale" not in parts and "Libs" not in parts:
            yield path


def used_keys():
    keys = set()
    for path in code_files():
        text = path.read_text(encoding="utf-8")
        keys.update(KEY.findall(text))
        for singular, plural in PLURAL.findall(text):
            keys.add(f'"{singular}"')
            keys.add(f'"{plural or singular + "s"}"')
    return keys


def main() -> int:
    keys = used_keys()
    if "--list" in sys.argv:
        for key in sorted(keys, key=str.lower):
            print(f"\t-- [{key}] = \"\",")
        return 0
    failures = []
    for path in sorted(LOCALE_DIR.glob("Tradewright_Locale_*.lua")):
        text = path.read_text(encoding="utf-8")
        stale = [key for key in TRANSLATED.findall(text) if key not in keys]
        failures += [f"{path.relative_to(ROOT)}: {key} is not a text the code uses" for key in stale]
    for line in failures:
        print(line)
    print(f"locale: {len(keys)} translatable texts" + ("" if not failures else f", {len(failures)} stale translation(s)"))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
