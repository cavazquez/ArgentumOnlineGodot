#!/usr/bin/env python3
"""Login gráfico entre los Snaps de Store, con Redis propio y dos arranques.

El checkout del servidor aporta sólo utilidades de fixture y decodificación del
protocolo. El proceso de juego se ejecuta exclusivamente mediante snap run.
Requiere un usuario descartable sin perfil previo del cliente, Xvfb y Docker.
"""

import argparse
import asyncio
from datetime import UTC, datetime
import json
import os
from pathlib import Path
import secrets
import shutil
import signal
import socket
import ssl
import struct
import subprocess
import time
from tempfile import TemporaryDirectory

from src.operations.redis_sandbox import RedisSandbox
from src.operations.two_client_smoke import ProtocolPeer
from src.network.packet_id import ServerPacketID
from src.core.schema_manager import CURRENT_SCHEMA_VERSION

from runtime_log import classify_runtime_log
from store_schema_evidence import verify_schema

ROOT = Path(__file__).resolve().parents[1]


def metadata(name, revision, commit, version, digest):
    rows = subprocess.check_output(
        ["snap", "list", name, "--unicode=never"], text=True
    ).splitlines()
    values = rows[1].split()
    if values[:3] != [name, version, revision] or "dangerous" in rows[1]:
        raise RuntimeError("El Snap instalado no es la revisión de Store esperada")
    base = Path("/snap") / name / revision
    provenance = json.loads((base / "share/doc" / name / "provenance.json").read_text())
    if provenance["commit"] != commit or provenance["dirty"]:
        raise RuntimeError("La procedencia del Snap no coincide con la publicación")
    package = Path("/var/lib/snapd/snaps") / f"{name}_{revision}.snap"
    # snapd conserva los paquetes con permisos de root. El runner descartable
    # permite este acceso de sólo lectura; no se cambia el archivo instalado.
    actual = subprocess.check_output(
        ["sudo", "-n", "sha256sum", str(package)], text=True
    ).split()[0]
    if actual != digest:
        raise RuntimeError("El paquete instalado difiere del SHA256 publicado")
    return {
        "name": name,
        "version": version,
        "revision": revision,
        "sha256": actual,
        "commit": commit,
        "source": "snap-store",
    }


def wait_until(predicate, label, timeout=20):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.1)
    raise TimeoutError(label)


def stop(process):
    if process.poll() is None:
        process.send_signal(signal.SIGTERM)
        try:
            process.wait(timeout=30)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
            raise
    if process.returncode != 0:
        raise RuntimeError("El proceso Snap no terminó limpiamente")


def ready(process, port, cert, *, initial=False):
    context = ssl.create_default_context(cafile=cert)
    started = time.monotonic()
    # Redis vacío migra el catálogo completo; el login conserva su límite de 5 s.
    budget = 240 if initial else 60
    deadline = started + budget
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError("El servidor Snap terminó antes de abrir TLS")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=1) as raw:
                with context.wrap_socket(raw, server_hostname="localhost") as stream:
                    stream.sendall(b"\x77")
                    if stream.recv(1) != b"\x58":
                        raise RuntimeError("No respondió PONG dentro de TLS verificado")
                    return {"elapsed_seconds": round(time.monotonic() - started, 3),
                            "budget_seconds": budget, "login_budget_changed": False}
        except (ConnectionRefusedError, TimeoutError):
            time.sleep(0.1)
    raise TimeoutError("El servidor no abrió TLS")


async def create_account(port, cert, username, password):
    reader, writer = await asyncio.open_connection(
        "127.0.0.1",
        port,
        ssl=ssl.create_default_context(cafile=cert),
        server_hostname="localhost",
    )
    peer = ProtocolPeer(reader, writer)

    def string(value):
        encoded = value.encode("latin-1")
        return struct.pack("<H", len(encoded)) + encoded

    packet = (
        b"\x02"
        + string(username)
        + string(password)
        + b"\x00\x0d\x00"
        + b"\x01\x01\x01\x12\x00"
        + string("fixture@example.invalid")
        + b"\x01"
    )
    try:
        await peer.send(b"\x01")  # Dados reales, como la pantalla de alta.
        await peer.wait(
            lambda frames: any(f[0] == ServerPacketID.DICE_ROLL for f in frames)
        )
        await peer.send(packet)
        await peer.wait(
            lambda frames: any(f[0] == ServerPacketID.LOGGED for f in frames)
            and any(f[0] == ServerPacketID.SHOW_PARTY_FORM for f in frames)
        )
        # El PONG confirma que terminó el handler de alta y su envío inicial.
        await peer.send(b"\x77")
        await peer.wait(lambda frames: any(f[0] == ServerPacketID.PONG for f in frames))
        await peer.send(b"\x47")  # QUIT deja que el servidor cierre TLS.
        async with asyncio.timeout(10):
            await peer.task
        if peer.error is not None:
            raise RuntimeError(
                "El alta terminó con una respuesta incompleta"
            ) from peer.error
    finally:
        await peer.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--version", default="1.0.0rc2")
    parser.add_argument("--server-revision", default="18")
    parser.add_argument("--client-revision", default="3")
    parser.add_argument(
        "--server-commit", default="0a921ccd5e9a04ef5ff7dd2eb8ba8370cd2352ea"
    )
    parser.add_argument(
        "--client-commit", default="cf1c9ab41a25db6f4290b08beb038251fac9a0b3"
    )
    parser.add_argument(
        "--server-sha256",
        default="c9b749ed07f4b193b11569ab03ef3defbcb4a525d4c209b5366249b4242000db",
    )
    parser.add_argument(
        "--client-sha256",
        default="2c2d119da95e1395c62056fd82b8a9baa337d71c2cc79aaab6029731e9ed847a",
    )
    parser.add_argument("--max-login-seconds", type=float, default=5)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    started = datetime.now(UTC).isoformat()
    installed = [
        metadata(
            "pyao",
            args.server_revision,
            args.server_commit,
            args.version,
            args.server_sha256,
        ),
        metadata(
            "pyao-client",
            args.client_revision,
            args.client_commit,
            args.version,
            args.client_sha256,
        ),
    ]
    common = Path.home() / "snap/pyao/common"
    common.mkdir(parents=True, exist_ok=True)
    profile = (
        Path.home() / "snap/pyao-client/common/data/godot/app_userdata/"
        "ArgentumOnlineGodot/connection.cfg"
    )
    if profile.exists():
        raise RuntimeError(
            "La prueba requiere un usuario descartable sin perfil de juego"
        )
    clean_environment = {
        k: v for k, v in os.environ.items() if not k.startswith(("PYAO_", "SNAP"))
    }
    with (
        TemporaryDirectory(prefix="pair-login-", dir=common) as directory,
        RedisSandbox() as sandbox,
    ):
        work = Path(directory)
        secret = work / "redis-password"
        shutil.copyfile(sandbox.password_file, secret)
        secret.chmod(0o600)
        cert, key = work / "test.crt", work / "test.key"
        subprocess.run(
            [
                "openssl",
                "req",
                "-x509",
                "-newkey",
                "rsa:2048",
                "-nodes",
                "-days",
                "1",
                "-subj",
                "/CN=localhost",
                "-addext",
                "subjectAltName=DNS:localhost,IP:127.0.0.1",
                "-keyout",
                str(key),
                "-out",
                str(cert),
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        key.chmod(0o600)
        with socket.socket() as reservation:
            reservation.bind(("127.0.0.1", 0))
            port = reservation.getsockname()[1]
        environment = dict(
            clean_environment,
            PYAO_STATE_DIR=str(work),
            PYAO_REDIS__HOST="127.0.0.1",
            PYAO_REDIS__PORT=str(sandbox.port),
            PYAO_REDIS__PASSWORD_FILE=str(secret),
        )
        username, password = (
            "SnapFixture" + secrets.token_hex(4),
            secrets.token_urlsafe(18),
        )
        attempts = []
        persisted = None
        with sandbox.client() as store:
            for attempt in (1, 2):
                with (output / f"server-{attempt}.log").open("wb") as log:
                    server = subprocess.Popen(
                        [
                            "snap",
                            "run",
                            "pyao.pyao-server",
                            "--host",
                            "127.0.0.1",
                            "--port",
                            str(port),
                            "--ssl",
                            "--ssl-cert",
                            str(cert),
                            "--ssl-key",
                            str(key),
                        ],
                        cwd=work,
                        env=environment,
                        stdout=log,
                        stderr=subprocess.STDOUT,
                    )
                    try:
                        startup = ready(server, port, cert, initial=attempt == 1)
                        if attempt == 1:
                            asyncio.run(create_account(port, cert, username, password))
                        account = wait_until(
                            lambda: store.hgetall(f"account:{username}:data"),
                            "Falta la cuenta creada por protocolo",
                        )
                        uid = account["user_id"]
                        wait_until(
                            lambda: not store.exists(f"session:{uid}:owner"),
                            "La conexión anterior no liberó su sesión",
                        )
                        inventory = f"player:{uid}:inventory"
                        if attempt == 1:
                            # Fixture exclusiva: añadir manzanas con el personaje desconectado.
                            store.hset(inventory, "slot_30", "1:10")
                        before = store.hgetall(inventory)
                        if attempt == 2 and before != persisted:
                            raise RuntimeError(
                                "El reinicio perdió el inventario persistido"
                            )
                        # El segundo recorrido arrastra el ítem del primer slot al último
                        # mientras el personaje está desconectado para repetir el mismo input.
                        if attempt == 2:
                            store.hset(
                                inventory,
                                mapping={
                                    "slot_30": before["slot_1"],
                                    "slot_1": before["slot_30"],
                                },
                            )
                            before = store.hgetall(inventory)
                        ui_output = output / f"login-{attempt}"
                        positions = set()
                        with (output / f"ui-{attempt}.log").open("wb") as ui_log:
                            ui = subprocess.Popen(
                                [
                                    "/usr/bin/python3",
                                    str(ROOT / "tools/snap-ui-smoke.py"),
                                    "--output",
                                    str(ui_output),
                                    "--ca",
                                    str(cert),
                                    "--port",
                                    str(port),
                                    "--version",
                                    args.version,
                                    "--commit",
                                    args.client_commit,
                                ],
                                env=dict(
                                    clean_environment,
                                    PYAO_TEST_USERNAME=username,
                                    PYAO_TEST_PASSWORD=password,
                                    PYAO_TEST_AUDIO="PulseAudio",
                                ),
                                cwd=work,
                                stdout=ui_log,
                                stderr=subprocess.STDOUT,
                            )
                            try:
                                deadline = time.monotonic() + 120
                                while ui.poll() is None:
                                    position = store.hgetall(f"player:{uid}:position")
                                    if position:
                                        positions.add(
                                            tuple(
                                                position[k] for k in ("map", "x", "y")
                                            )
                                        )
                                    if time.monotonic() > deadline:
                                        raise TimeoutError(
                                            "El cliente Snap no completó el recorrido UI"
                                        )
                                    time.sleep(0.1)
                                if ui.returncode != 0:
                                    raise RuntimeError(
                                        "Falló la UI real; revisar capturas y logs"
                                    )
                            finally:
                                if ui.poll() is None:
                                    ui.terminate()
                                    ui.wait(timeout=20)
                        result = json.loads((ui_output / "snap-ui.json").read_text())
                        if result["login_to_world_seconds"] > args.max_login_seconds:
                            raise RuntimeError(
                                "El login excede el plazo de pocos segundos"
                            )
                        if len(positions) < 2:
                            raise RuntimeError(
                                "El teclado no confirmó movimiento en Redis"
                            )
                        persisted = store.hgetall(inventory)
                        if persisted.get("slot_1") != before.get(
                            "slot_30"
                        ) or persisted.get("slot_30") != before.get("slot_1"):
                            raise RuntimeError(
                                "El drag no confirmó su resultado en Redis"
                            )
                        wait_until(
                            lambda: not store.exists(f"session:{uid}:owner"),
                            "El cierre de la UI no liberó su sesión",
                        )
                        schema_version = verify_schema(store, CURRENT_SCHEMA_VERSION)
                        attempts.append(
                            {
                                "attempt": attempt,
                                "server_startup": startup,
                                **result,
                                "movement_confirmed_in_redis": True,
                                "distinct_positions": len(positions),
                                "inventory_confirmed_in_redis": True,
                                "session_released": True,
                                "redis_schema_version": schema_version,
                            }
                        )
                    finally:
                        stop(server)
                if attempt == 1:
                    original_profile = profile.read_bytes()
                    # El smoke se niega a sobrescribir un perfil. Éste pertenece
                    # exclusivamente al usuario descartable creado para esta prueba.
                    profile.unlink()
            if profile.read_bytes() != original_profile:
                raise RuntimeError("Cambió el endpoint al volver a ingresar")
        for path in output.rglob("*.log"):
            text = path.read_text()
            if (
                password in text
                or "Traceback (most recent call last)" in text
                or not classify_runtime_log(text)["passed"]
                or "| ERROR |" in text
            ):
                raise RuntimeError("Un log contiene un error o la credencial sintética")
        proof = {
            "passed": True,
            "started_at": started,
            "completed_at": datetime.now(UTC).isoformat(),
            "installed_snaps": installed,
            "attempts": attempts,
            "tls_verified": True,
            "server_restarted": True,
            "inventory_preserved_after_restart": True,
            "graceful_sigterm": True,
            "production_data_used": False,
            "long_r10_acceptance": False,
            "expected_redis_schema": CURRENT_SCHEMA_VERSION,
        }
        (output / "result.json").write_text(json.dumps(proof, indent=2) + "\n")
        print(json.dumps(proof))


if __name__ == "__main__":
    main()
