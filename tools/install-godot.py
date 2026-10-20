#!/usr/bin/env python3
"""Instala el motor nativo y los templates oficiales fijados y verificados."""

import argparse
import hashlib
import json
import os
import platform
from pathlib import Path
import shutil
import tempfile
import urllib.request
import zipfile


def install(destination: Path, all_templates=False) -> Path:
    project = Path(__file__).resolve().parent.parent
    release = json.loads((project / "tools/godot-release.json").read_text())
    version = (project / ".godot-version").read_text().strip()
    if version != release["version"]:
        raise ValueError("El manifiesto y .godot-version difieren")
    destination.mkdir(parents=True, exist_ok=True)
    system, machine = platform.system(), platform.machine().lower()
    if system == "Linux":
        editor_name = f"Godot_v{version}-stable_linux." + ("arm64" if machine in {"aarch64", "arm64"} else "x86_64")
        archive_name = editor_name + ".zip"
        executable = destination / editor_name
    elif system == "Windows":
        editor_name = f"Godot_v{version}-stable_win64.exe"
        archive_name = editor_name + ".zip"
        executable = destination / editor_name
    elif system == "Darwin":
        archive_name = f"Godot_v{version}-stable_macos.universal.zip"
        executable = destination / "Godot.app/Contents/MacOS/Godot"
    else:
        raise ValueError(f"Plataforma de editor no soportada: {system}/{machine}")
    templates = destination / "data/godot/export_templates" / release["template_version"]
    templates.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="pyao-godot-") as directory:
        for name in (archive_name, f"Godot_v{version}-stable_export_templates.tpz"):
            asset = release["assets"][name]
            archive = Path(directory) / Path(name).name
            digest = hashlib.sha256()
            with urllib.request.urlopen(asset["url"], timeout=120) as source, archive.open("wb") as target:
                while block := source.read(1024 * 1024):
                    target.write(block)
                    digest.update(block)
            if digest.hexdigest() != asset["sha256"]:
                raise ValueError(f"SHA256 incorrecto: {name}")
            with zipfile.ZipFile(archive) as contents:
                # No extractall: sólo nombres conocidos, sin traversal ni binarios extra.
                if name == archive_name:
                    for info in contents.infolist():
                        if info.is_dir(): continue
                        allowed = info.filename.startswith("Godot.app/") if system == "Darwin" else info.filename in {editor_name, editor_name.replace(".exe", "_console.exe")}
                        if not allowed: continue
                        target_path = (destination / info.filename).resolve()
                        if not target_path.is_relative_to(destination.resolve()):
                            raise ValueError("Ruta insegura en el archivo oficial")
                        target_path.parent.mkdir(parents=True, exist_ok=True)
                        with contents.open(info) as source, target_path.open("wb") as target:
                            shutil.copyfileobj(source, target)
                        target_path.chmod((info.external_attr >> 16) & 0o777 or 0o755)
                else:
                    arch = "arm64" if machine in {"aarch64", "arm64"} else "x86_64"
                    for info in contents.infolist():
                        template = info.filename.removeprefix("templates/")
                        if info.is_dir() or "/" in template or template == info.filename: continue
                        if not all_templates and template not in {"version.txt", f"linux_debug.{arch}", f"linux_release.{arch}"}: continue
                        with contents.open(info) as source, (templates / template).open("wb") as target:
                            shutil.copyfileobj(source, target)
    if (templates / "version.txt").read_text().strip() != release["template_version"]:
        raise ValueError("La versión interna de templates difiere")
    executable.chmod(0o755)
    # Godot uses different template locations on native Windows/macOS.
    if system == "Darwin":
        native_templates = Path.home() / "Library/Application Support/Godot/export_templates" / release["template_version"]
    elif system == "Windows":
        native_templates = Path(os.environ["APPDATA"]) / "Godot/export_templates" / release["template_version"]
    else:
        native_templates = templates
    if native_templates != templates:
        shutil.copytree(templates, native_templates, dirs_exist_ok=True)
    return executable


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", type=Path, required=True)
    parser.add_argument("--all-templates", action="store_true")
    args = parser.parse_args()
    engine = install(args.destination.resolve(), args.all_templates)
    print(engine)
    if path := os.environ.get("GITHUB_ENV"):
        with Path(path).open("a") as environment:
            environment.write(f"GODOT_BIN={engine}\n")
            environment.write(f"XDG_DATA_HOME={engine.parent / 'data'}\n")
