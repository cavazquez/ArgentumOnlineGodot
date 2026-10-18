#!/usr/bin/env python3
"""0: limpio; 2: inicialización de caché conocida; 1: cualquier otro error."""

from pathlib import Path
import re
import sys


def classify(log: str) -> int:
    text = re.sub(r"\x1b\[[0-9;]*m", "", log)
    if "SCRIPT ERROR:" in text:
        return 1
    errors = list(re.finditer(r"^\s*ERROR: (.*)$", text, re.MULTILINE))
    if not errors:
        return 0
    completed = list(re.finditer(r"\[\s*DONE\s*\].*savepack", text))
    if not completed or errors[0].start() < completed[-1].end():
        return 1
    messages = [match.group(1).strip() for match in errors]
    width = "The Image width specified (0 pixels) must be greater than 0 pixels."
    empty = "Invalid image: image is empty"
    return 2 if messages == [width, empty] * 3 else 1


if __name__ == "__main__":
    raise SystemExit(classify(Path(sys.argv[1]).read_text()))
