#!/usr/bin/env python3
"""Instala exclusivamente el motor y los templates Linux fijados y verificados."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile
import urllib.request
import zipfile


def install(destination: Path) -> Path:
    project = Path(__file__).resolve().parent.parent
    release = json.loads((project / "tools/godot-release.json").read_text())
    version = (project / ".godot-version").read_text().strip()
    if version != release["version"]:
        raise ValueError("El manifiesto y .godot-version difieren")
    destination.mkdir(parents=True, exist_ok=True)
    editor_name = f"Godot_v{version}-stable_linux.x86_64"
    templates = destination / "data/godot/export_templates" / release["template_version"]
    templates.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="pyao-godot-") as directory:
        for name, asset in release["assets"].items():
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
                if name.endswith(".zip"):
                    with contents.open(editor_name) as source, (destination / editor_name).open("wb") as target:
                        shutil.copyfileobj(source, target)
                    (destination / editor_name).chmod(0o755)
                else:
                    for template in ["version.txt", "linux_debug.x86_64", "linux_release.x86_64"]:
                        with contents.open("templates/" + template) as source, (templates / template).open("wb") as target:
                            shutil.copyfileobj(source, target)
    if (templates / "version.txt").read_text().strip() != release["template_version"]:
        raise ValueError("La versión interna de templates difiere")
    return destination / editor_name


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", type=Path, required=True)
    args = parser.parse_args()
    engine = install(args.destination.resolve())
    print(engine)
    if path := os.environ.get("GITHUB_ENV"):
        with Path(path).open("a") as environment:
            environment.write(f"GODOT_BIN={engine}\n")
            environment.write(f"XDG_DATA_HOME={engine.parent / 'data'}\n")
