#!/usr/bin/env python3
"""Reject Han text in hardcoded Flutter copy and the English catalog."""

import json
from pathlib import Path
import sys
import unicodedata


CLIENT = Path(__file__).resolve().parents[1] / "apps" / "client"
LOCALIZATIONS = CLIENT / "lib" / "l10n"
LANGUAGE_NAMES = {"languageZh": "简体中文", "languageJa": "日本語"}
# These patterns match model/vendor identifiers. They are not rendered as copy.
PROVIDER_PATTERNS = {
    "zhipu|智谱|glm",
    "moonshot|月之暗面",
    "silicon|硅基",
    "step|阶跃",
}


def has_han(text):
    return any(
        unicodedata.name(char, "").startswith(("CJK UNIFIED", "CJK COMPATIBILITY"))
        for char in text
    )


def main():
    errors = []
    for path in sorted((CLIENT / "lib").rglob("*.dart")):
        if path.is_relative_to(LOCALIZATIONS):
            continue
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if path.name == "ai_icon_helper.dart":
                for pattern in PROVIDER_PATTERNS:
                    line = line.replace(f"RegExp(r'{pattern}')", "")
            if has_han(line):
                errors.append(f"{path.relative_to(CLIENT)}:{number}: {line.strip()}")

    catalog = json.loads((LOCALIZATIONS / "app_en.arb").read_text(encoding="utf-8"))
    for key, value in catalog.items():
        if isinstance(value, str) and value != LANGUAGE_NAMES.get(key) and has_han(value):
            errors.append(f"lib/l10n/app_en.arb:{key}: {value}")

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print("Hardcoded Flutter copy and the English catalog passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
