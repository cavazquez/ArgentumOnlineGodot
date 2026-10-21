"""Comprueba el Python privado del servidor antes de ejecutar el par nativo."""

import hashlib
import json
import os
from pathlib import Path
import re


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def verify_bundle(root, commit, version, wheel):
    root = root.resolve()
    record = json.loads((root / "server-candidate.json").read_text())
    if record.get("dirty") is not False or record.get("commit") != commit or record.get("version") != version:
        raise ValueError("El servidor privado no acredita las mismas fuentes limpias y versión")
    if not re.fullmatch(r"[0-9a-f]{40}", commit) or record.get("wheel_sha256") != digest(wheel):
        raise ValueError("El servidor privado corresponde a otro wheel")
    actual = {}
    for path in sorted(root.rglob("*")):
        name = path.relative_to(root).as_posix()
        if path.is_symlink():
            if not path.resolve().is_relative_to(root):
                raise ValueError("Enlace fuera del servidor privado")
            actual[name] = "symlink:" + os.readlink(path)
        elif path.is_file() and name not in {"server-candidate.json", "server-proof.json", "candidate-manifest.json"}:
            actual[name] = digest(path)
    if not actual or actual != record.get("files"):
        raise ValueError("El servidor privado cambió después de construirse")
    relative = record.get("python_path", "")
    path = Path(relative)
    if not relative or path.is_absolute() or ".." in path.parts:
        raise ValueError("Ruta de Python privado inválida")
    python = root / path
    if not python.is_file() or not python.resolve().is_relative_to(root):
        raise ValueError("Python privado fuera del candidato")
    return python
