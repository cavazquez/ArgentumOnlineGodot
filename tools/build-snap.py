#!/usr/bin/env python3
"""Construye el Snap fijando herramienta, fuente y procedencia antes del proveedor aislado."""

import argparse
import json
import platform
import re
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--allow-dirty", action="store_true", help="Sólo para artefactos locales de revisión; la procedencia registra dirty=true")
    parser.add_argument("--arch", choices=["amd64", "arm64"])
    args = parser.parse_args()
    native = {"x86_64": "amd64", "aarch64": "arm64", "arm64": "arm64"}.get(platform.machine().lower())
    arch = args.arch or native
    if arch is None or arch != native:
        raise SystemExit("Cada Snap requiere construir y probar en su arquitectura nativa")
    toolchain = json.loads((ROOT / "snap/toolchain.json").read_text())
    toolchain["architecture"] = arch
    toolchain["snapcraft_revision"] = {"amd64": "19274", "arm64": "19281"}[arch]
    version = subprocess.check_output(["snapcraft", "--version"], text=True).strip()
    if version != f"snapcraft {toolchain['snapcraft_version']}":
        raise SystemExit(f"Se requiere Snapcraft {toolchain['snapcraft_version']}; se encontró {version}")
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    dirty = bool(subprocess.check_output(["git", "status", "--porcelain", "--untracked-files=normal"], cwd=ROOT))
    if dirty and not args.allow_dirty:
        raise SystemExit("El checkout tiene cambios: confirmar primero o usar --allow-dirty para revisión local")
    release = re.search(r'^config/version="([0-9][A-Za-z0-9.+-]*)"$', (ROOT / "project.godot").read_text(), re.MULTILINE)
    if release is None:
        raise SystemExit("Falta una versión válida del cliente en project.godot")
    provenance = {"version": release[1], "commit": commit, "dirty": dirty, "toolchain": toolchain, "godot": json.loads((ROOT / "tools/godot-release.json").read_text())}
    (ROOT / "snap/pyao-source.json").write_text(json.dumps(provenance, indent=2) + "\n")
    subprocess.run(["snapcraft", "pack", "--use-lxd", f"--build-for={arch}", "--verbosity=brief"], cwd=ROOT, check=True)


if __name__ == "__main__":
    main()
