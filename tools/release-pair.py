#!/usr/bin/env python3
"""Prepara y promueve una entrega Snap conjunta, con recibos y recuperación.

La Store no ofrece una transacción entre nombres. Nunca se usa upload --release:
primero se revisan los tres paquetes y luego se promueven desde un único proceso.
Si una promoción falla (incluso después de aplicarse), se restaura el par previo.
"""

import argparse
from datetime import UTC, datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time

from r10_world import REQUIRED_SCENARIOS

PACKAGES = {"pyao/amd64", "pyao/arm64", "pyao-client/amd64"}
REPOSITORIES = {
    "pyao": ("cavazquez/pyao-server", {"CI", "Server Snap"}),
    "pyao-client": ("cavazquez/ArgentumOnlineGodot", {"Cliente Linux"}),
}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def now():
    return datetime.now(UTC).isoformat()


def digest(path, algorithm="sha256"):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, algorithm).hexdigest()


def read(path):
    return json.loads(path.read_text())


def save(path, value):
    """Publica atómicamente un recibo privado; jamás contiene credenciales."""
    temporary = path.with_suffix(".pending")
    descriptor = os.open(temporary, os.O_CREAT | os.O_TRUNC | os.O_WRONLY, 0o600)
    with os.fdopen(descriptor, "w") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    temporary.replace(path)


def command(arguments, *, timeout=120):
    return subprocess.check_output(
        arguments, text=True, stderr=subprocess.STDOUT, timeout=timeout
    )


def reference(item, root):
    path = (root / item["file"]).resolve()
    require(path.is_file(), f"Falta el archivo {path}")
    require(digest(path) == item["sha256"], f"SHA256 distinto: {path}")
    return path


def validate_evidence(manifest, root):
    server = manifest["sources"]["pyao"]["commit"]
    client = manifest["sources"]["pyao-client"]["commit"]
    proof = {
        key: read(reference(manifest["evidence"][key], root))
        for key in ("r10", "upgrade", "requirements")
    }
    for key, result in proof.items():
        require(result["server_commit"] == server, f"{key}: otro servidor")
        if key != "upgrade":
            require(result["client_commit"] == client, f"{key}: otro cliente")
    long = proof["r10"]
    require(long["release_version"] == manifest["version"], "R10: otra versión")
    for flag in (
        "passed",
        "long_acceptance",
        "native_export",
        "installed_wheel",
        "tls",
        "graceful_sigterm",
    ):
        require(long.get(flag) is True, f"R10 incompleta: {flag}")
    require(
        long["clients"] == 2 and long["live_tls_sessions_drained"] == 2,
        "R10 requiere dos clientes nativos y cierre de ambas sesiones TLS",
    )
    durations = long["godot_measured_seconds"]
    require(len(durations) == 2 and min(durations) >= 1800, "R10 menor a 30 minutos")
    acceptance = long["acceptance"]
    require(
        acceptance.get("r10_gameplay_passed") is True
        and not acceptance["missing"]
        and REQUIRED_SCENARIOS <= set(acceptance["completed"]),
        "R10: faltan escenarios funcionales",
    )
    export = long["export_provenance"]
    require(
        export["commit"] == client and export["clean_before_export"] is True,
        "R10: exportación ajena o sucia",
    )
    upgrade = proof["upgrade"]
    for flag in (
        "legacy_migrated",
        "progress_preserved",
        "idempotent",
        "restart_preserved",
        "rollback_verified",
        "legacy_config_checked",
    ):
        require(upgrade.get(flag) is True, f"Actualización incompleta: {flag}")
    require(
        upgrade.get("production_data_used") is False,
        "El ensayo de actualización requiere datos descartables",
    )
    for identifier in (f"R{i:02d}" for i in range(1, 10)):
        requirement = proof["requirements"]["requirements"][identifier]
        # R09 se cierra tras instalar el par firmado desde Store. Antes de publicar
        # exige el smoke del mismo candidato instalado, sin fingir ese paso futuro.
        passed = requirement.get(
            "candidate_passed" if identifier == "R09" else "passed"
        )
        require(
            passed is True and requirement["evidence"],
            f"Falta la aceptación {identifier}",
        )
        for item in requirement["evidence"]:
            reference(
                item, reference(manifest["evidence"]["requirements"], root).parent
            )


def validate(manifest, root, backend):
    require(manifest["version"] == "1.0.0rc1", "Esta entrega conserva 1.0.0rc1")
    require(
        manifest["channel"] == "latest/edge", "Esta entrega se publica en latest/edge"
    )
    require(set(manifest["sources"]) == set(REPOSITORIES), "Fuentes incompletas")
    keys = [f"{p['name']}/{p['architecture']}" for p in manifest["packages"]]
    require(
        len(keys) == len(PACKAGES) and set(keys) == PACKAGES,
        "Par de paquetes incompleto",
    )
    for name, (repository, workflows) in REPOSITORIES.items():
        source = manifest["sources"][name]
        require(source["repository"] == repository, "Repositorio ajeno a la entrega")
        require(re.fullmatch(r"[0-9a-f]{40}", source["commit"]), "Commit inválido")
        require(
            backend.main(repository) == source["commit"],
            f"{name}: main cambió o el PR todavía no está fusionado",
        )
        runs = [backend.ci(repository, run) for run in source["ci_runs"]]
        require(
            workflows <= {run["workflowName"] for run in runs}, f"Falta CI de {name}"
        )
        for run in runs:
            require(
                run["headSha"] == source["commit"]
                and run["conclusion"] == "success"
                and run["status"] == "completed",
                f"CI pendiente o ajena: {name}",
            )
    for package in manifest["packages"]:
        path = reference(package, root)
        metadata, provenance = backend.inspect(path, package["name"])
        expected = {
            "name": package["name"],
            "version": manifest["version"],
            "confinement": "strict",
            "architectures": [package["architecture"]],
        }
        require(
            all(metadata.get(k) == v for k, v in expected.items()),
            f"Metadata Snap incompatible: {path}",
        )
        require(
            provenance["commit"] == manifest["sources"][package["name"]]["commit"]
            and provenance["version"] == manifest["version"]
            and provenance["dirty"] is False,
            f"Procedencia incompatible: {path}",
        )
    validate_evidence(manifest, root)


class Store:
    def main(self, repository):
        return json.loads(command(["gh", "api", f"repos/{repository}/commits/main"]))[
            "sha"
        ]

    def ci(self, repository, run):
        return json.loads(
            command(
                [
                    "gh",
                    "run",
                    "view",
                    str(run),
                    "--repo",
                    repository,
                    "--json",
                    "headSha,status,conclusion,workflowName",
                ]
            )
        )

    def inspect(self, path, name):
        yaml = command(["unsquashfs", "-cat", str(path), "meta/snap.yaml"])
        # Sólo los escalares y la lista plana generados por Snapcraft; sin ejecutar YAML.
        fields = {}
        for line in yaml.splitlines():
            if line and not line[0].isspace() and ": " in line:
                key, value = line.split(": ", 1)
                fields[key] = value.strip("\"'")
        inline = re.search(r"^architectures: \[([^\]]+)\]$", yaml, re.MULTILINE)
        block = re.search(r"^architectures:\n((?:- [^\n]+\n)+)", yaml, re.MULTILINE)
        require(inline or block, "No se reconoció architectures del Snap")
        fields["architectures"] = (
            [v.strip().strip("\"'") for v in inline[1].split(",")]
            if inline
            else [v[2:].strip() for v in block[1].splitlines()]
        )
        provenance = json.loads(
            command(
                [
                    "unsquashfs",
                    "-cat",
                    str(path),
                    f"share/doc/{name}/provenance.json",
                ]
            )
        )
        return fields, provenance

    def channels(self, channel):
        track, risk = channel.split("/")
        result = {}
        for name in REPOSITORIES:
            response = json.loads(
                command(
                    [
                        "curl",
                        "-4",
                        "--fail",
                        "--silent",
                        "--show-error",
                        "--max-time",
                        "30",
                        "-H",
                        "Snap-Device-Series: 16",
                        f"https://api.snapcraft.io/v2/snaps/info/{name}",
                    ]
                )
            )
            for entry in response["channel-map"]:
                selected = entry["channel"]
                key = f"{name}/{selected['architecture']}"
                if (
                    key in PACKAGES
                    and selected["track"] == track
                    and selected["risk"] == risk
                ):
                    result[key] = {
                        "name": name,
                        "revision": entry["revision"],
                        "version": entry["version"],
                        "sha3_384": entry["download"]["sha3-384"],
                    }
        require(set(result) == PACKAGES, "La Store no devolvió el par completo")
        return result

    def upload(self, path, name, log):
        # Omitir --release es deliberado: la revisión no cambia ningún canal.
        try:
            output = command(["snapcraft", "upload", str(path)], timeout=1800)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
            output = (
                error.output or "Sin respuesta; no repetir el upload automáticamente"
            )
            if isinstance(output, bytes):
                output = output.decode(errors="replace")
            log.write_text(output)
            log.chmod(0o600)
            raise
        log.write_text(output)
        log.chmod(0o600)
        revisions = re.findall(
            r"Revision\s+(\d+)\s+created for ['\"]" + re.escape(name), output
        )
        require(
            len(revisions) == 1,
            f"Revisión incierta; revisar {log} antes de repetir el upload",
        )
        return int(revisions[0])

    def release(self, name, revision, channel):
        command(["snapcraft", "release", name, str(revision), channel], timeout=120)

    def wait(self, expected, channel):
        deadline = time.monotonic() + 180
        while time.monotonic() < deadline:
            actual = self.channels(channel)
            if actual == expected:
                return actual
            time.sleep(3)
        raise TimeoutError(
            "La Store no confirmó todos los hashes y revisiones esperados"
        )


def prepare(manifest_path, directory, backend):
    manifest = read(manifest_path)
    validate(manifest, manifest_path.parent, backend)
    # Un directorio nuevo evita reintentar ciegamente un upload de resultado incierto.
    directory.mkdir(mode=0o700)
    copied = json.loads(json.dumps(manifest))
    for package in copied["packages"]:
        original = reference(package, manifest_path.parent)
        target = directory / f"{package['name']}_{package['architecture']}.snap"
        shutil.copyfile(original, target)
        target.chmod(0o600)
        package["file"] = str(target.resolve())
    # Las evidencias conservan su ruta y hash; se revalidan al promover.
    for item in copied["evidence"].values():
        item["file"] = str(reference(item, manifest_path.parent))
    validate(copied, directory, backend)
    baseline = backend.channels(manifest["channel"])
    receipt = {
        "status": "preparing",
        "started_at": now(),
        "manifest": copied,
        "baseline": baseline,
        "candidates": {},
        "operations": [],
    }
    path = directory / "state.json"
    save(path, receipt)
    for package in copied["packages"]:
        key = f"{package['name']}/{package['architecture']}"
        receipt["upload_in_progress"] = key
        save(path, receipt)
        reference(package, directory)
        revision = backend.upload(
            Path(package["file"]),
            package["name"],
            directory / f"{key.replace('/', '-')}.log",
        )
        receipt["candidates"][key] = {
            "name": package["name"],
            "revision": revision,
            "version": manifest["version"],
            "sha3_384": digest(Path(package["file"]), "sha3_384"),
        }
        receipt.pop("upload_in_progress")
        save(path, receipt)
    require(
        backend.channels(manifest["channel"]) == baseline,
        "El canal cambió durante la preparación",
    )
    receipt.update(status="ready", reviewed_at=now())
    save(path, receipt)
    return receipt


def promote(path, backend):
    receipt = read(path)
    require(receipt["status"] == "ready", "La entrega no está completamente revisada")
    manifest = receipt["manifest"]
    validate(manifest, path.parent, backend)
    require(set(receipt["candidates"]) == PACKAGES, "Faltan revisiones revisadas")
    for package in manifest["packages"]:
        key = f"{package['name']}/{package['architecture']}"
        candidate = receipt["candidates"][key]
        require(
            candidate["sha3_384"] == digest(Path(package["file"]), "sha3_384")
            and candidate["name"] == package["name"]
            and candidate["version"] == manifest["version"],
            "Recibo de upload alterado",
        )
    require(
        backend.channels(manifest["channel"]) == receipt["baseline"],
        "El canal cambió: detener y preparar de nuevo la entrega",
    )
    receipt.update(status="promoting", promotion_started_at=now())
    save(path, receipt)
    try:
        for candidate in receipt["candidates"].values():
            # Se registra ANTES: un timeout puede ocurrir después de que la Store cambió.
            receipt["operations"].append(
                {"action": "release", **candidate, "at": now()}
            )
            save(path, receipt)
            backend.release(
                candidate["name"], candidate["revision"], manifest["channel"]
            )
        backend.wait(receipt["candidates"], manifest["channel"])
        receipt.update(status="published", promotion_completed_at=now())
        save(path, receipt)
    except BaseException as error:
        receipt.update(error=str(error), failed_at=now())
        rollback(path, receipt, backend)
        raise
    return receipt


def rollback(path, receipt, backend):
    """Recupera también una promoción interrumpida al terminar el proceso."""
    channel = receipt["manifest"]["channel"]
    require(
        channel == "latest/edge" and set(receipt["baseline"]) == PACKAGES,
        "Recibo de recuperación incompatible",
    )
    for key, previous in receipt["baseline"].items():
        require(
            previous["name"] == key.split("/")[0]
            and type(previous["revision"]) is int
            and previous["revision"] > 0,
            "Revisión anterior inválida",
        )
    receipt.update(status="rolling-back")
    save(path, receipt)
    failures = []
    for previous in receipt["baseline"].values():
        try:
            backend.release(previous["name"], previous["revision"], channel)
        except BaseException as error:
            failures.append(str(error))
    try:
        backend.wait(receipt["baseline"], channel)
    except BaseException as error:
        failures.append(str(error))
    receipt.update(
        status="rollback-failed" if failures else "rolled-back",
        rollback_errors=failures,
        rollback_completed_at=now(),
    )
    save(path, receipt)
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    check = sub.add_parser("check")
    check.add_argument("manifest", type=Path)
    stage = sub.add_parser("prepare")
    stage.add_argument("manifest", type=Path)
    stage.add_argument("--output", type=Path, required=True)
    release = sub.add_parser("promote")
    release.add_argument("state", type=Path)
    recover = sub.add_parser("recover")
    recover.add_argument("state", type=Path)
    args = parser.parse_args()
    store = Store()
    # Serializa publicadores de este usuario en esta máquina, incluso entre checkouts.
    descriptor = os.open(
        f"/tmp/pyao-release-pair-{os.getuid()}.lock",
        os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW,
        0o600,
    )
    with os.fdopen(descriptor, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        execute(args, store)


def execute(args, store):
    if args.command == "check":
        validate(read(args.manifest), args.manifest.resolve().parent, store)
        print("Par completo y validado; ningún canal modificado")
    elif args.command == "prepare":
        result = prepare(args.manifest.resolve(), args.output.resolve(), store)
        print(
            json.dumps({"status": result["status"], "candidates": result["candidates"]})
        )
    elif args.command == "promote":
        result = promote(args.state.resolve(), store)
        print(
            json.dumps(
                {
                    k: result[k]
                    for k in (
                        "status",
                        "promotion_started_at",
                        "promotion_completed_at",
                    )
                }
            )
        )
    else:
        receipt = read(args.state)
        require(
            receipt["status"]
            in {"promoting", "rolling-back", "rollback-failed", "published"},
            "El recibo no corresponde a una entrega publicada o interrumpida",
        )
        current = store.channels(receipt["manifest"]["channel"])
        require(
            all(
                current[key]
                in (receipt["baseline"][key], receipt["candidates"].get(key))
                for key in PACKAGES
            ),
            "Otra entrega cambió el canal; no se recupera un recibo viejo",
        )
        result = rollback(args.state.resolve(), receipt, store)
        require(
            result["status"] == "rolled-back",
            "Falló la recuperación; revisar state.json",
        )
        print(json.dumps({"status": result["status"]}))


if __name__ == "__main__":
    main()
