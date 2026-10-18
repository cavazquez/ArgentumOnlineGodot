#!/usr/bin/env python3
"""Dos Godot reales, servidor instalado y Redis propio; ejecutar con uv/Python 3.14.

La duración por defecto es 30 minutos. --seconds 30 sirve para desarrollar el
harness, pero no acredita la aceptación prolongada de la versión 1.0.
"""
import argparse
import asyncio
import contextlib
import hashlib
import json
import os
import re
from pathlib import Path
import secrets
import signal
import socket
import ssl
import subprocess
import sys
import tempfile
import time
import tomllib

ROOT = Path(__file__).resolve().parents[1]


def run(arguments, **kwargs):
    return subprocess.run(arguments, check=True, text=True, **kwargs)


def port():
    with socket.socket() as reserved:
        reserved.bind(("127.0.0.1", 0))
        return reserved.getsockname()[1]


def stop(process):
    if process.poll() is None:
        process.send_signal(signal.SIGTERM)
        try:
            process.wait(timeout=20)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)


class NativeRedis:
    """Alternativa local al contenedor, sobre el mismo Redis 8.10.2 real.

    Sólo administra un proceso y directorio creados por esta instancia. Nunca
    acepta una URL Redis existente ni modifica el firewall o las redes del host.
    """
    def __init__(self, runtime, work):
        self.runtime = runtime
        self.root = work / "redis-owned"
        self.root.mkdir(mode=0o700)
        self.port = port()
        self.password_file = self.root / "password"
        self.password_file.write_text(secrets.token_hex(32))
        self.password_file.chmod(0o600)
        self.process = None

    def __enter__(self):
        from src.runtime_paths import resource_root
        runtime = self.runtime
        command = [str(runtime / "ld-musl"), "--library-path",
                   str(runtime / "lib") + ":" + str(runtime / "usr-lib"),
                   str(runtime / "redis-server")]
        version = subprocess.check_output([*command, "--version"], text=True)
        if "v=8.10.2 " not in version:
            raise RuntimeError("La fixture requiere Redis 8.10.2")
        password = self.password_file.read_text()
        acl = self.root / "users.acl"
        acl.write_text("user default on #" + hashlib.sha256(password.encode()).hexdigest() + " ~* &* +@all\n")
        acl.chmod(0o600)
        config = self.root / "redis.conf"
        config.write_text((resource_root() / "redis/redis.conf").read_text().replace("dir /data", "dir " + str(self.root)))
        self.log = (self.root / "redis.log").open("wb")
        self.process = subprocess.Popen([*command, str(config), "--bind", "127.0.0.1",
            "--port", str(self.port), "--aclfile", str(acl)], stdout=self.log, stderr=subprocess.STDOUT)
        try:
            with self.client():
                pass
        except BaseException:
            self.__exit__()
            raise
        return self

    def client(self):
        from redis import Redis, ConnectionError
        client = Redis(host="127.0.0.1", port=self.port, password=self.password_file.read_text(),
                       decode_responses=True, socket_timeout=5, socket_connect_timeout=1)
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            try:
                client.ping()
                return client
            except ConnectionError:
                if self.process.poll() is not None:
                    break
                time.sleep(.1)
        client.close()
        raise RuntimeError("Redis propio no inició")

    def __exit__(self, *_):
        if self.process is not None:
            stop(self.process)
        self.log.close()


def worker(args):
    def interrupted(*_):
        raise InterruptedError("Ensayo interrumpido; se limpian los procesos propios")
    signal.signal(signal.SIGTERM, interrupted)
    from src.operations.redis_sandbox import RedisSandbox
    from importlib.metadata import version
    if version("pyao-server") != args.release_version:
        raise RuntimeError("El wheel no corresponde a la versión común del par")
    work = Path.cwd()
    output = args.output
    certificate, key = work / "test-ca.crt", work / "test-key.pem"
    run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
         "-subj", "/CN=127.0.0.1", "-addext", "subjectAltName=IP:127.0.0.1,DNS:localhost",
         "-keyout", str(key), "-out", str(certificate)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    key.chmod(0o600)
    fixture = NativeRedis(args.redis_runtime, work) if args.redis_runtime else RedisSandbox()
    with fixture as redis, contextlib.ExitStack() as stack:
        endpoint = port()
        environment = dict(os.environ, PYAO_REDIS__HOST="127.0.0.1", PYAO_REDIS__PORT=str(redis.port),
            PYAO_REDIS__PASSWORD_FILE=str(redis.password_file), PYAO_STATE_DIR=str(work / "server-state"))
        server_log = stack.enter_context((output / "server.log").open("wb"))
        entry = Path(sys.executable).parent / "pyao-server"
        server = subprocess.Popen([str(entry), "--host", "127.0.0.1", "--port", str(endpoint),
            "--ssl", "--ssl-cert", str(certificate), "--ssl-key", str(key)],
            cwd=work, env=environment, stdout=server_log, stderr=subprocess.STDOUT)
        stack.callback(stop, server)
        deadline = time.monotonic() + 60
        while True:
            if server.poll() is not None:
                raise RuntimeError("El servidor instalado terminó; revisar server.log")
            try:
                with socket.create_connection(("127.0.0.1", endpoint), timeout=.5):
                    break
            except ConnectionRefusedError:
                if time.monotonic() > deadline:
                    raise TimeoutError("Listener no disponible")
                time.sleep(.1)
        clients = []
        password = secrets.token_urlsafe(18)
        names = []
        for index in (1, 2):
            name = "Fixture" + secrets.token_hex(4) + str(index)
            names.append(name)
            client_log = stack.enter_context((output / f"godot-{index}.log").open("wb"))
            client_env = dict(os.environ, PYAO_TEST_PASSWORD=password, PYAO_TEST_USERNAME=name,
                PYAO_TEST_PORT=str(endpoint), PYAO_TEST_CA=str(certificate),
                PYAO_TEST_INDEX=str(index), PYAO_TEST_PEER=str(3-index), PYAO_TEST_DURATION=str(args.seconds),
                PYAO_TEST_SCREENSHOT=str(output / f"godot-{index}.png"),
                XDG_DATA_HOME=str(work / f"client-{index}/data"), XDG_CONFIG_HOME=str(work / f"client-{index}/config"),
                XDG_CACHE_HOME=str(work / f"client-{index}/cache"))
            command = [str(args.godot), "--path", str(ROOT), "--audio-driver", "Dummy",
                       "--rendering-method", "gl_compatibility", "res://tests/integration_world.tscn"]
            if args.headless:
                command.insert(1, "--headless")
            client = subprocess.Popen(command, env=client_env, cwd=work, stdout=client_log, stderr=subprocess.STDOUT)
            stack.callback(stop, client)
            clients.append(client)
        started = time.monotonic()
        while any(client.poll() is None for client in clients):
            for index in (1, 2):
                text = (output / f"godot-{index}.log").read_text()
                if "SCRIPT ERROR:" in text or "ERROR:" in text:
                    raise RuntimeError(f"Error de script o recurso en Godot {index}; revisar log")
            if any(client.poll() not in (None, 0) for client in clients):
                raise RuntimeError("Falló un cliente Godot; revisar logs")
            if server.poll() is not None or time.monotonic() - started > args.seconds + 120:
                raise TimeoutError("Proceso perdido o plazo total agotado")
            time.sleep(1)
        for index in (1, 2):
            log = (output / f"godot-{index}.log").read_text()
            if "INTEGRATION_WORLD: PASS" not in log or "SCRIPT ERROR:" in log or "ERROR:" in log:
                raise RuntimeError(f"Godot {index} no acredita la prueba completa")
            if password in log:
                raise RuntimeError("Se filtró una credencial sintética en el log")
        from src.utils.redis_config import RedisKeys
        with redis.client() as store:
            for name in names:
                account = store.hgetall(RedisKeys.account_data(name))
                if not account:
                    raise RuntimeError("Falta la cuenta creada por UI")
                deadline = time.monotonic() + 15
                while store.exists(f"session:{account['user_id']}:owner"):
                    if time.monotonic() > deadline:
                        raise TimeoutError("La desconexión de Godot no liberó la sesión")
                    time.sleep(.1)
        if args.snap_installed or args.ui_executable:
            ui_output = output / "installed-snap"
            ui_environment = dict(os.environ, PYAO_TEST_USERNAME=names[0],
                PYAO_TEST_PASSWORD=password, PYAO_TEST_AUDIO=args.snap_audio)
            arguments = ["/usr/bin/python3", str(ROOT / "tools/snap-ui-smoke.py"),
                "--port", str(endpoint), "--ca", str(certificate), "--output", str(ui_output),
                "--version", args.release_version]
            if args.ui_executable:
                arguments += ["--executable", str(args.ui_executable)]
            with redis.client() as store, (output / "snap-ui-run.log").open("wb") as ui_log:
                user_id = store.hget(RedisKeys.account_data(names[0]), "user_id")
                inventory_key = RedisKeys.player_inventory(int(user_id))
                expected_item = store.hget(inventory_key, "slot_30").split(":")[0]
                positions = set()
                ui_process = subprocess.Popen(arguments, cwd=work, env=ui_environment, stdout=ui_log, stderr=subprocess.STDOUT)
                try:
                    deadline = time.monotonic() + 120
                    while ui_process.poll() is None:
                        positions.add(tuple(sorted(store.hgetall(f"player:{user_id}:position").items())))
                        if time.monotonic() > deadline:
                            raise TimeoutError("El Snap no completó su recorrido por UI")
                        time.sleep(.2)
                    if ui_process.returncode != 0:
                        raise RuntimeError("Falló la UI del Snap; revisar sus capturas y logs")
                    if len(positions) < 2:
                        raise RuntimeError("El input del Snap no cambió la posición en Redis")
                    if store.hget(inventory_key, "slot_1").split(":")[0] != expected_item or store.hget(inventory_key, "slot_30"):
                        raise RuntimeError("El drag del Snap no confirmó inventario en Redis")
                finally:
                    stop(ui_process)
        async def live_session_shutdown():
            from src.operations.two_client_smoke import ProtocolPeer, login_packet
            from src.network.packet_id import ServerPacketID
            peers = []
            try:
                for name in names:
                    reader, writer = await asyncio.open_connection("127.0.0.1", endpoint,
                        ssl=ssl.create_default_context(cafile=certificate), server_hostname="127.0.0.1")
                    peer = ProtocolPeer(reader, writer)
                    peers.append(peer)
                    await peer.send(login_packet(name, password))
                    await peer.wait(lambda frames: any(frame[0] == ServerPacketID.LOGGED for frame in frames))
                await asyncio.to_thread(stop, server)
                for peer in peers:
                    async with asyncio.timeout(8):
                        await peer.task
                    if peer.error is not None:
                        raise RuntimeError("El cierre de TLS dejó un frame incompleto") from peer.error
            finally:
                for peer in peers:
                    await peer.close()
        asyncio.run(live_session_shutdown())
        with redis.client() as store:
            for name in names:
                user_id = store.hget(RedisKeys.account_data(name), "user_id")
                if store.exists(f"session:{user_id}:owner"):
                    raise RuntimeError("SIGTERM dejó una reserva de sesión activa")
        if server.returncode != 0:
            raise RuntimeError("El servidor no terminó limpiamente con SIGTERM")
        elapsed = time.monotonic() - started
        proof = {"passed": True, "clients": 2, "seconds": round(elapsed, 2),
                 "long_acceptance": args.seconds >= 1800, "tls": True, "installed_wheel": True,
                 "server_commit": args.server_commit, "client_commit": args.client_commit,
                 "wheel_sha256": hashlib.sha256(args.wheel.read_bytes()).hexdigest(),
                 "redis": "8.10.2", "godot": args.godot_version, "graceful_sigterm": True}
        proof["live_tls_sessions_drained"] = 2
        proof["release_version"] = args.release_version
        proof["installed_snap_ui"] = args.snap_installed
        (output / "result.json").write_text(json.dumps(proof, indent=2) + "\n")
        print(json.dumps(proof))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server-project", type=Path, required=True)
    parser.add_argument("--wheel", type=Path, required=True)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--seconds", type=int, default=1800)
    parser.add_argument("--headless", action="store_true")
    parser.add_argument("--redis-runtime", type=Path)
    parser.add_argument("--snap-installed", action="store_true")
    parser.add_argument("--snap-audio", choices=("Dummy", "PulseAudio"), default="Dummy")
    parser.add_argument("--ui-executable", type=Path, help="Desarrollo de UI fuera de Snap; no acredita instalación")
    parser.add_argument("--worker", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if not 10 <= args.seconds <= 7200:
        parser.error("La duración debe estar entre 10 y 7200 segundos")
    for name in ("server_project", "wheel", "godot", "output", "redis_runtime", "ui_executable"):
        if getattr(args, name) is not None:
            setattr(args, name, getattr(args, name).resolve())
    if not args.worker and args.output.exists() and any(args.output.iterdir()):
        parser.error("La salida debe ser nueva para no confundir evidencia de ejecuciones anteriores")
    args.output.mkdir(parents=True, exist_ok=True)
    args.server_commit = subprocess.check_output(["git", "-C", str(args.server_project), "rev-parse", "HEAD"], text=True).strip()
    args.client_commit = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()
    args.godot_version = subprocess.check_output([str(args.godot), "--version"], text=True).strip()
    args.release_version = tomllib.loads((args.server_project / "pyproject.toml").read_text())["project"]["version"]
    client_version = re.search(r'^config/version="([^"]+)"$', (ROOT / "project.godot").read_text(), re.MULTILINE)
    if client_version is None or client_version[1] != args.release_version:
        parser.error("Servidor y cliente deben declarar exactamente la misma versión")
    if args.seconds >= 1800:
        for project in (ROOT, args.server_project):
            if subprocess.check_output(["git", "-C", str(project), "status", "--porcelain"], text=True).strip():
                parser.error("La aceptación prolongada exige ambos checkouts limpios y commits fijos")
    manifest = json.loads((ROOT / "tools/godot-release.json").read_text())
    if args.godot_version != manifest["editor_version"]:
        parser.error("Motor distinto del manifiesto fijado")
    if args.worker:
        worker(args)
        return
    environment = {k: v for k, v in os.environ.items() if not k.startswith(("PYAO_", "SNAP"))}
    environment.update(PYTHONPATH="", PYTHONNOUSERSITE="1")
    with tempfile.TemporaryDirectory(prefix="pyao-godot-world-") as temporary:
        work = Path(temporary)
        run(["uv", "venv", "--python", sys.executable, str(work / "venv")], cwd=work, env=environment)
        python = work / "venv/bin/python"
        runtime = subprocess.check_output(["uv", "export", "--locked", "--no-dev", "--no-emit-project"], cwd=args.server_project, text=True)
        run(["uv", "pip", "install", "--python", str(python), "--require-hashes", "-r", "-"], input=runtime, cwd=work, env=environment)
        run(["uv", "pip", "install", "--python", str(python), "--no-deps", str(args.wheel)], cwd=work, env=environment)
        # Argumentos absolutos para que el proceso instalado trabaje fuera de los checkouts.
        arguments = [str(python), str(Path(__file__).resolve()), "--worker", "--server-project", str(args.server_project),
            "--wheel", str(args.wheel), "--godot", str(args.godot), "--output", str(args.output), "--seconds", str(args.seconds)]
        if args.headless:
            arguments.append("--headless")
        if args.redis_runtime:
            arguments += ["--redis-runtime", str(args.redis_runtime)]
        if args.snap_installed:
            arguments.append("--snap-installed")
        if args.ui_executable:
            arguments += ["--ui-executable", str(args.ui_executable)]
        arguments += ["--snap-audio", args.snap_audio]
        child = subprocess.Popen(arguments, cwd=work, env=environment, start_new_session=True)
        try:
            if child.wait(timeout=args.seconds + 240) != 0:
                raise RuntimeError("Falló el ensayo instalado; revisar los logs conservados")
        finally:
            if child.poll() is None:
                child.send_signal(signal.SIGTERM)
                try:
                    child.wait(timeout=120)
                except subprocess.TimeoutExpired:
                    # El grupo contiene únicamente worker, servidor, Redis y Godot propios.
                    os.killpg(child.pid, signal.SIGKILL)
                    child.wait(timeout=5)


if __name__ == "__main__":
    main()
