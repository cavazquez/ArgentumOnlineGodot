"""Instala el acceso del portable Linux usando su ubicación final real."""

import argparse
import os
from pathlib import Path


def install(bundle: Path, destination: Path) -> Path:
    candidates = [p for p in bundle.glob("pyao-client.*") if p.suffix in {".x86_64", ".arm64"}]
    if len(candidates) != 1:
        raise ValueError("Se requiere un único ejecutable PyAO del portable Linux")
    executable = str(candidates[0].resolve())
    if any(c in executable for c in ("\n", "\r")):
        raise ValueError("El nombre de la carpeta no puede contener saltos de línea")
    escaped = executable.replace("\\", "\\\\").replace('"', '\\"').replace("`", "\\`").replace("$", "\\$")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text("[Desktop Entry]\nType=Application\nName=PyAO Client\nExec=\"" + escaped + "\"\nIcon=" + str((bundle / "pyao-client.png").resolve()) + "\nTerminal=false\nCategories=Game;RolePlaying;\n")
    return destination


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--destination", type=Path, default=Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share"))) / "applications/pyao-client.desktop")
    args = parser.parse_args()
    print(install(args.bundle, args.destination))
