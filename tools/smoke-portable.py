#!/usr/bin/env python3
"""Prueba los bytes del candidato nativo en una carpeta con espacios y sin editor."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def sha(path):
    with path.open("rb") as stream: return hashlib.file_digest(stream, "sha256").hexdigest()


def smoke(candidate, server, engine, output, redis_runtime):
    record = json.loads((candidate / "candidate-manifest.json").read_text())
    target = record["platform"]
    expected = {"windows": "Windows", "linux": "Linux", "linux-arm64": "Linux", "macos": "Darwin"}.get(target)
    if platform.system() != expected or record["dirty"]:
        raise ValueError("Se requiere el sistema nativo del candidato y fuentes limpias")
    if target == "linux-arm64" and platform.machine().lower() not in {"aarch64", "arm64"}:
        raise ValueError("ARM64 requiere un runner ARM64 nativo")
    for name, digest in record["files"].items():
        if sha(candidate / name) != digest: raise ValueError("Candidato alterado: " + name)
    output.mkdir(parents=True, exist_ok=False)
    with tempfile.TemporaryDirectory(prefix="PyAO portable con espacios ") as temporary:
        runtime = Path(temporary) / "Cliente listo"
        shutil.copytree(candidate, runtime)
        pattern = {"windows": "pyao-client.exe", "linux": "pyao-client.x86_64", "linux-arm64": "pyao-client.arm64", "macos": "*.app/Contents/MacOS/*"}[target]
        matches = [path for path in runtime.glob(pattern) if path.is_file()]
        if len(matches) != 1: raise ValueError("Ejecutable nativo ambiguo")
        executable = matches[0]
        if target == "macos":
            subprocess.run(["codesign", "--verify", "--deep", "--strict", str(next(runtime.glob("*.app")))], check=True)
        executable.chmod(0o755)
        # Sólo la entrada de aceptación cambia; ejecutable y recursos son los del portable.
        override = executable.parent / "override.cfg"
        shutil.copy2(ROOT / "tests/r10-export.cfg", override)
        if target == "macos": shutil.copy2(override, executable.parent.parent / "Resources/override.cfg")
        (executable.parent / "provenance.json").write_text(json.dumps({"commit": record["commit"], "clean_before_export": True, "files": {executable.name: sha(executable), "override.cfg": sha(override)}}))
        proof_dir = output / "two-clients"
        command = [sys.executable, str(ROOT / "tools/integration-world.py"), "--source", "--scenario", "platform", "--server-project", str(server), "--godot", str(engine), "--client-executable", str(executable), "--output", str(proof_dir), "--seconds", "20"]
        if redis_runtime: command += ["--redis-runtime", str(redis_runtime)]
        subprocess.run(command, cwd=runtime, check=True)
        result = json.loads((proof_dir / "result.json").read_text())
        steps = json.loads((proof_dir / "r10-scenarios.json").read_text())
        verified = result.get("regression_passed") is True and result.get("native_export") is True and result.get("tls") is True
        proof = {"passed": verified, "platform": target, "client_commit": record["commit"], "server_commit": result["server_commit"], "candidate_manifest_sha256": sha(candidate / "candidate-manifest.json"), "login": verified, "outside_checkout": not runtime.is_relative_to(ROOT), "native_system": platform.platform(), "native_machine": platform.machine()}
        for check in ("rendering", "audio", "input", "preferences"):
            proof[check] = len(steps) == 2 and all(row["observations"].get(check) is True for row in steps)
        (output / "native-proof.json").write_text(json.dumps(proof, indent=2) + "\n")
        if not all(proof[key] is True for key in ("passed", "login", "rendering", "audio", "input", "preferences", "outside_checkout")):
            raise ValueError("La prueba nativa no acredita todos los requisitos")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ("candidate", "server", "godot", "output"): parser.add_argument("--" + key, type=Path, required=True)
    parser.add_argument("--redis-runtime", type=Path)
    args = parser.parse_args()
    smoke(args.candidate.resolve(), args.server.resolve(), args.godot.resolve(), args.output.resolve(), args.redis_runtime.resolve() if args.redis_runtime else None)
