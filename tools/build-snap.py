#!/usr/bin/env python3
"""Construye el Snap fijando herramienta, fuente y procedencia antes del proveedor aislado."""

import argparse
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--allow-dirty", action="store_true", help="Sólo para artefactos locales de revisión; la procedencia registra dirty=true")
    args = parser.parse_args()
    toolchain = json.loads((ROOT / "snap/toolchain.json").read_text())
    version = subprocess.check_output(["snapcraft", "--version"], text=True).strip()
    if version != f"snapcraft {toolchain['snapcraft_version']}":
        raise SystemExit(f"Se requiere Snapcraft {toolchain['snapcraft_version']}; se encontró {version}")
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    dirty = bool(subprocess.check_output(["git", "status", "--porcelain", "--untracked-files=normal"], cwd=ROOT))
    if dirty and not args.allow_dirty:
        raise SystemExit("El checkout tiene cambios: confirmar primero o usar --allow-dirty para revisión local")
    provenance = {"commit": commit, "dirty": dirty, "toolchain": toolchain, "godot": json.loads((ROOT / "tools/godot-release.json").read_text())}
    (ROOT / "snap/pyao-source.json").write_text(json.dumps(provenance, indent=2) + "\n")
    subprocess.run(["snapcraft", "pack", "--use-lxd", "--verbosity=brief"], cwd=ROOT, check=True)


if __name__ == "__main__":
    main()
