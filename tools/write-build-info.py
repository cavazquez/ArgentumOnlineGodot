#!/usr/bin/env python3
"""Metadata pública del binario; nunca incorpora configuración de la máquina."""

import json
from pathlib import Path
import re
import subprocess


def metadata(root):
    try:
        # GITHUB_SHA puede ser el merge sintético de un PR, distinto del checkout.
        commit = subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=root, text=True, stderr=subprocess.DEVNULL
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        try:
            commit = json.loads((root / "snap/pyao-source.json").read_text())["commit"]
        except (OSError, ValueError, KeyError, TypeError):
            commit = "no disponible"
    if not isinstance(commit, str) or re.fullmatch(r"[a-fA-F0-9]{40}", commit) is None:
        commit = "no disponible"
    return {"commit": commit}


def main():
    root = Path(__file__).resolve().parents[1]
    (root / "build-info.json").write_text(json.dumps(metadata(root), indent=2) + "\n")


if __name__ == "__main__":
    main()
