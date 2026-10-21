#!/usr/bin/env python3
"""Construye candidatos portables sin publicarlos; verifica motor y procedencia."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PRESETS = {"windows": ("Windows Desktop", "pyao-client.exe"), "linux": ("Linux Desktop", "pyao-client.x86_64"), "linux-arm64": ("Linux ARM64", "pyao-client.arm64"), "macos": ("macOS", "pyao-client.zip"), "web": ("Web", "index.html")}


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def run_export(command, output):
    """Admite una sola inicialización de caché; no oculta fallos persistentes."""
    log = output / "export.log"
    checker = [sys.executable, str(ROOT / "tools/check-export-log.py"), str(log)]
    for attempt in range(2):
        with log.open("w") as stream:
            subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, check=True)
        checked = subprocess.run(checker)
        if checked.returncode == 0:
            return
        if checked.returncode == 2 and attempt == 0:
            shutil.copy2(log, output / "export-initial.log")
        else:
            checked.check_returncode()


def export(target, output, engine, reuse=None):
    if output.exists() and any(output.iterdir()):
        raise ValueError("La carpeta de salida debe estar vacía")
    output.mkdir(parents=True, exist_ok=True)
    product = re.search(r'^config/version="([^"]+)"$', (ROOT / "project.godot").read_text(), re.M)[1]
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    dirty = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT))
    release = json.loads((ROOT / "tools/godot-release.json").read_text())
    version = subprocess.check_output([str(engine), "--version"], text=True).strip()
    if version != release["editor_version"]:
        raise ValueError("Motor distinto del manifiesto fijado")
    subprocess.run([sys.executable, str(ROOT / "tools/write-build-info.py")], check=True)
    preset, filename = PRESETS[target]
    if reuse:
        if target not in {"linux", "linux-arm64"} or not reuse.is_file():
            raise ValueError("Sólo se reutiliza el export nativo Linux existente")
        shutil.copy2(reuse, output / filename)
    else:
        command = [str(engine), "--headless", "--path", str(ROOT), "--export-release", preset, str(output / filename)]
        run_export(command, output)
    if not (output / filename).is_file():
        raise ValueError("El motor no produjo el artefacto esperado")
    if not dirty and subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT):
        raise ValueError("La exportación modificó fuentes; confirmar el ajuste antes de acreditar el candidato")
    if target == "macos":
        with zipfile.ZipFile(output / filename) as archive:
            for info in archive.infolist():
                path = (output / info.filename).resolve()
                if not path.is_relative_to(output.resolve()):
                    raise ValueError("Ruta inesperada en el bundle macOS")
                if info.is_dir():
                    path.mkdir(parents=True, exist_ok=True)
                else:
                    path.parent.mkdir(parents=True, exist_ok=True)
                    with archive.open(info) as source, path.open("wb") as destination:
                        shutil.copyfileobj(source, destination)
                    path.chmod((info.external_attr >> 16) & 0o777 or 0o644)
        (output / filename).unlink()
    if target in {"linux", "linux-arm64"}:
        subprocess.run([sys.executable, str(ROOT / "tools/build_tray.py"), "--output", str(output / "pyao-tray")], check=True)
        shutil.copy2(ROOT / "Assets/Branding/pyao-client-128.png", output / "pyao-client.png")
        shutil.copy2(ROOT / "tools/install-desktop.py", output / "install-desktop.py")
    for name in ("LICENSE", "README.md"):
        shutil.copy2(ROOT / name, output / name)
    (output / "PORTABLE.txt").write_text("PyAO Client " + product + "\nUsar un servidor de la misma versión.\nEste paquete incluye sus recursos y no requiere instalar Godot.\nLinux: python3 install-desktop.py agrega el acceso de menú desde la ubicación final del portable.\nmacOS: firma ad hoc, sin notarización; abrir mediante el menú contextual si Gatekeeper lo solicita.\n")
    files = {str(path.relative_to(output)).replace(os.sep, "/"): digest(path) for path in sorted(output.rglob("*")) if path.is_file()}
    record = {"version": product, "commit": commit, "dirty": dirty, "platform": target, "godot": version, "files": files, "verified": False}
    (output / "candidate-manifest.json").write_text(json.dumps(record, indent=2) + "\n")
    return record


def seal(output, evidence):
    """Sólo empaqueta después de verificar pruebas del mismo binario y commit."""
    record = json.loads((output / "candidate-manifest.json").read_text())
    proof = json.loads(evidence.read_text())
    if record["dirty"] or proof.get("passed") is not True or proof.get("client_commit") != record["commit"] or proof.get("platform") != record["platform"]:
        raise ValueError("La evidencia no acredita este candidato limpio/plataforma")
    for name, expected in record["files"].items():
        if digest(output / name) != expected:
            raise ValueError("El candidato cambió después de construirse: " + name)
    if proof.get("candidate_manifest_sha256") != digest(output / "candidate-manifest.json"):
        raise ValueError("La prueba no referencia este manifiesto exacto")
    checks = ("rendering", "audio", "input", "login", "preferences", "outside_checkout")
    if record["platform"] != "web": checks += ("desktop",)
    for check in checks:
        if proof.get(check) is not True:
            raise ValueError("Falta verificación nativa: " + check)
    suffix = record['platform'] + ("-" + proof["native_machine"] if record['platform'] == "macos" else "")
    name = f"pyao-client-{record['version']}-{suffix}"
    archive = Path(shutil.make_archive(str(output.parent / name), "zip", output))
    manifest = {**record, "verified": True, "evidence_sha256": digest(evidence), "archive": archive.name, "sha256": digest(archive)}
    (archive.parent / (name + ".json")).write_text(json.dumps(manifest, indent=2) + "\n")
    return archive


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["export", "seal"])
    parser.add_argument("--platform", choices=PRESETS)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--godot", type=Path)
    parser.add_argument("--reuse-linux", type=Path)
    parser.add_argument("--evidence", type=Path)
    args = parser.parse_args()
    if args.action == "export":
        if not args.platform or not args.godot: parser.error("export requiere --platform y --godot")
        export(args.platform, args.output.resolve(), args.godot.resolve(), args.reuse_linux)
    else:
        if not args.evidence: parser.error("seal requiere --evidence")
        print(seal(args.output.resolve(), args.evidence.resolve()))
