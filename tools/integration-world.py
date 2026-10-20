#!/usr/bin/env python3
"""Dos Godot reales, servidor instalado y Redis propio; ejecutar con uv/Python 3.14.

La duración por defecto es 30 minutos. --seconds 30 sirve para desarrollar el
harness, pero no acredita la aceptación prolongada de la versión 1.0.
"""

import argparse
import asyncio
import contextlib
from datetime import UTC, datetime
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
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SCENARIO_TIMEOUT_SECONDS = {
    "r10": 900,
    "skills": 1800,
    "spells": 1800,
    "full": 7200,
    "navigation": 900,
    "duel": 900,
    "economy": 1200,
    "economy-ui": 600,
    "npcs": 600,
    "platform": 600,
    "potions": 1200,
    "expansion": 1200,
    "npc-policy": 1200,
    "lifetime-stats": 900,
    "structure-profile": 900,
}


def verify_wheel_source(project, wheel):
    """Compara todos los recursos instalables con el checkout declarado."""
    tracked = subprocess.check_output(
        [
            "git",
            "-C",
            str(project),
            "ls-files",
            "--",
            "src",
            "tools",
            "data",
            "config",
            "redis",
            "archives/map_data.xz",
        ],
        text=True,
    ).splitlines()
    expected = {
        (
            "src/runtime_data/" + p
            if p.startswith(("data/", "config/", "redis/", "archives/"))
            else p
        )
        for p in tracked
    }
    compared = 0
    with zipfile.ZipFile(wheel) as archive:
        packaged = {
            name
            for name in archive.namelist()
            if not name.endswith("/") and ".dist-info/" not in name
        }
        if expected - packaged:
            raise RuntimeError(
                "El wheel omite archivos del candidato: "
                + ", ".join(sorted(expected - packaged))
            )
        for name in sorted(packaged):
            relative = name.removeprefix("src/runtime_data/")
            source = project / relative
            if not source.is_file() or source.read_bytes() != archive.read(name):
                raise RuntimeError("El wheel no corresponde al candidato: " + name)
            compared += 1
    return {
        "passed": True,
        "files_compared": compared,
        "tracked_files_required": len(expected),
        "wheel_sha256": hashlib.sha256(wheel.read_bytes()).hexdigest(),
    }


def run(arguments, **kwargs):
    return subprocess.run(arguments, check=True, text=True, **kwargs)


def verify_native_export(executable, commit, *, long_run):
    """Un binario antiguo o alterado no puede acreditar otro commit del cliente."""
    provenance = json.loads((executable.parent / "provenance.json").read_text())
    if provenance["commit"] != commit or (
        long_run and not provenance["clean_before_export"]
    ):
        raise RuntimeError(
            "El export de aceptación no acredita el checkout candidato limpio"
        )
    for name, digest in provenance["files"].items():
        if name not in (executable.name, "override.cfg"):
            raise RuntimeError("Archivo inesperado en la procedencia del export")
        if (
            hashlib.sha256((executable.parent / name).read_bytes()).hexdigest()
            != digest
        ):
            raise RuntimeError(
                "El export de aceptación cambió después de compilarse: " + name
            )
    if set(provenance["files"]) != {executable.name, "override.cfg"}:
        raise RuntimeError("La procedencia del export está incompleta")
    return provenance


def port():
    with socket.socket() as reserved:
        reserved.bind(("127.0.0.1", 0))
        return reserved.getsockname()[1]


def stop(process):
    if process.poll() is None:
        process.send_signal(signal.CTRL_BREAK_EVENT if os.name == "nt" else signal.SIGTERM)
        try:
            process.wait(timeout=20)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)


def child_process_options():
    # CTRL_BREAK debe llegar sólo al hijo propio, nunca al grupo del runner.
    return {"creationflags": subprocess.CREATE_NEW_PROCESS_GROUP} if os.name == "nt" else {}


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
        self.log = None
        self.wsl_data_dir = None
        self.storage_kind = "native"

    def __enter__(self):
        try:
            return self._start()
        except BaseException:
            self.__exit__()
            raise

    def data_directory(self, wsl_runtime):
        if not wsl_runtime:
            return str(self.root).replace("\\", "/")
        # Redis conserva AOF/fsync; sus escrituras deben permanecer en el sistema
        # Linux, sin atravesar DrvFS/NTFS por cada barrera de durabilidad.
        owned = subprocess.check_output(
            ["wsl", "--exec", "mktemp", "-d", "/tmp/pyao-redis-fixture-XXXXXXXXXX"],
            text=True,
            timeout=15,
        ).strip()
        if not re.fullmatch(r"/tmp/pyao-redis-fixture-[A-Za-z0-9]{10}", owned):
            raise RuntimeError("WSL no devolvió un directorio Redis propio válido")
        self.wsl_data_dir = owned
        self.storage_kind = "wsl-linux"
        return owned

    def _start(self):
        from src.runtime_paths import resource_root

        runtime = self.runtime
        command = [
            str(runtime / "ld-musl"),
            "--library-path",
            str(runtime / "lib") + ":" + str(runtime / "usr-lib"),
            str(runtime / "redis-server"),
        ]
        native = runtime / "runtime.json"
        wsl_runtime = bool(json.loads(native.read_text()).get("wsl")) if native.exists() else False
        def native_path(path):
            if wsl_runtime:
                return subprocess.check_output(["wsl", "--exec", "wslpath", "-u", str(path)], text=True).strip()
            return str(path)
        if native.exists():
            command = (["wsl", "--exec"] if wsl_runtime else []) + [native_path(runtime / "redis-server")]
        version = subprocess.check_output([*command, "--version"], text=True)
        if "v=8.10.2 " not in version:
            raise RuntimeError("La fixture requiere Redis 8.10.2")
        password = self.password_file.read_text()
        acl = self.root / "users.acl"
        acl.write_text(
            "user default on #"
            + hashlib.sha256(password.encode()).hexdigest()
            + " ~* &* +@all\n"
        )
        acl.chmod(0o600)
        config = self.root / "redis.conf"
        config.write_text(
            (resource_root() / "redis/redis.conf")
            .read_text()
            .replace("dir /data", 'dir "' + self.data_directory(wsl_runtime) + '"')
        )
        self.log = (self.root / "redis.log").open("wb")
        self.process = subprocess.Popen(
            [
                *command,
                native_path(config),
                "--bind",
                "127.0.0.1",
                "--port",
                str(self.port),
                "--aclfile",
                native_path(acl),
            ],
            stdout=self.log,
            stderr=subprocess.STDOUT,
            **child_process_options(),
        )
        with self.client():
            pass
        return self

    def client(self):
        from redis import Redis, ConnectionError

        client = Redis(
            host="127.0.0.1",
            port=self.port,
            password=self.password_file.read_text(),
            decode_responses=True,
            socket_timeout=5,
            socket_connect_timeout=1,
        )
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            try:
                client.ping()
                return client
            except ConnectionError:
                if self.process.poll() is not None:
                    break
                time.sleep(0.1)
        client.close()
        raise RuntimeError("Redis propio no inició")

    def __exit__(self, *_):
        try:
            if self.process is not None:
                with contextlib.suppress(Exception):
                    with self.client() as client: client.shutdown(save=True)
                stop(self.process)
        finally:
            if self.log is not None:
                self.log.close()
            if self.wsl_data_dir is not None:
                subprocess.run(
                    ["wsl", "--exec", "rm", "-rf", "--", self.wsl_data_dir],
                    check=True,
                    timeout=15,
                )
                self.wsl_data_dir = None


def worker(args):
    started_at = datetime.now(UTC).isoformat()

    def interrupted(*_):
        raise InterruptedError("Ensayo interrumpido; se limpian los procesos propios")

    signal.signal(signal.SIGTERM, interrupted)
    if os.name == "nt": signal.signal(signal.SIGBREAK, interrupted)
    from src.operations.redis_sandbox import RedisSandbox
    from importlib.metadata import version

    if not args.source and version("pyao-server") != args.release_version:
        raise RuntimeError("El wheel no corresponde a la versión común del par")
    work = Path.cwd()
    output = args.output
    os.environ["PYAO_STATE_DIR"] = str(work / "runner-state")
    if args.scenario == "structure-profile":
        from structure_profile_world import StructureProfileWorld as R10World, acceptance, prepare_fixture
    elif args.scenario == "lifetime-stats":
        from lifetime_stats_world import LifetimeStatsWorld as R10World, acceptance, prepare_fixture
    elif args.scenario == "npc-policy":
        from npc_policy_world import NPCPolicyWorld as R10World, acceptance, prepare_fixture
    elif args.scenario == "potions":
        from potion_world import PotionWorld as R10World, acceptance, prepare_fixture
    elif args.scenario == "expansion":
        from phase50_world import Phase50World as R10World, acceptance, prepare_fixture
    elif args.scenario == "platform":
        from platform_world import PlatformWorld as R10World, acceptance, prepare_fixture
    elif args.scenario == "npcs":
        from npc_world import NPCWorld as R10World, acceptance, prepare_fixture
    elif args.scenario == "economy-ui":
        from economy_world import EconomyUIWorld as R10World, ui_acceptance as acceptance, prepare_fixture
    elif args.scenario == "economy":
        from economy_world import EconomyWorld as R10World, acceptance, prepare_fixture
    elif args.scenario == "duel":
        from duel_world import DuelWorld as R10World, acceptance, prepare_fixture
    elif args.scenario == "navigation":
        from navigation_world import (
            NavigationWorld as R10World,
            acceptance,
            prepare_fixture,
        )
    elif args.scenario == "full":
        from full_world import FullWorld as R10World, acceptance, prepare_fixture
    elif args.scenario == "skills":
        from skills_world import MechanicsWorld as R10World, acceptance, prepare_fixture
    elif args.scenario == "spells":
        from mechanics_world import (
            MechanicsWorld as R10World,
            acceptance,
            prepare_fixture,
        )
    else:
        from r10_world import R10World, acceptance, prepare_fixture

    scenario_data, locations = prepare_fixture(work, output)
    certificate, key = work / "test-ca.crt", work / "test-key.pem"
    run(
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
            "/CN=127.0.0.1",
            "-addext",
            "subjectAltName=IP:127.0.0.1,DNS:localhost",
            "-keyout",
            str(key),
            "-out",
            str(certificate),
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    key.chmod(0o600)
    fixture = (
        NativeRedis(args.redis_runtime, work) if args.redis_runtime else RedisSandbox()
    )
    with fixture as redis, contextlib.ExitStack() as stack:
        # R05 conserva recursos; el impuesto periódico se verifica por separado.
        # Sólo se modifica esta instancia descartable, antes de arrancar el servidor.
        with redis.client() as store:
            store.set("config:effects:gold_decay:enabled", "0")
        endpoint = port()
        environment = dict(
            os.environ,
            PYTHONUNBUFFERED="1",
            PYAO_REDIS__HOST="127.0.0.1",
            PYAO_REDIS__PORT=str(redis.port),
            PYAO_REDIS__PASSWORD_FILE=str(redis.password_file),
            PYAO_STATE_DIR=str(work / "server-state"),
            PYAO_METRICS_FILE=str(output / "server-ticks.json"),
            PYAO_DATA_DIR=str(scenario_data),
            PYAO_SECURITY__AUTH_ATTEMPTS_PER_IP="400"
            if args.scenario != "r10"
            else "120",
            PYAO_SECURITY__AUTH_ATTEMPTS_PER_ACCOUNT="200"
            if args.scenario != "r10"
            else "40",
        )
        native_platform = args.source and args.scenario == "platform"
        windows_platform = os.name == "nt" and native_platform
        if windows_platform and args.server_debug:
            environment["PYTHONASYNCIODEBUG"] = "1"
        server_log = stack.enter_context((output / "server.log").open("wb"))
        entry = Path(sys.executable).parent / ("pyao-server.exe" if os.name == "nt" else "pyao-server")
        server_entry = [sys.executable, "-m", "src.run_server"] if args.source else [str(entry)]
        server = subprocess.Popen(
            [
                *server_entry,
                *(["--debug", "--log-format", "json"] if args.server_debug else []),
                "--host",
                "127.0.0.1",
                "--port",
                str(endpoint),
                "--ssl",
                "--ssl-cert",
                str(certificate),
                "--ssl-key",
                str(key),
            ],
            cwd=work,
            env=environment,
            stdout=server_log,
            stderr=subprocess.STDOUT,
            **child_process_options(),
        )
        stack.callback(stop, server)
        # La fixture fuente valida y recompila los 290 mapas en frío. Ese trabajo
        # precede al listener y no forma parte de la latencia del login medido.
        startup_started = time.monotonic()
        deadline = startup_started + (240 if args.source else 60)
        while True:
            if server.poll() is not None:
                raise RuntimeError("El servidor instalado terminó; revisar server.log")
            try:
                with socket.create_connection(("127.0.0.1", endpoint), timeout=0.5):
                    break
            except OSError as error:
                if time.monotonic() > deadline:
                    raise TimeoutError(f"Listener 127.0.0.1:{endpoint} no disponible; revisar server.log") from error
                time.sleep(0.1)
        (output / "server-startup.json").write_text(json.dumps({
            "source_fixture": args.source,
            "host": "127.0.0.1", "port": endpoint,
            "elapsed_seconds": round(time.monotonic() - startup_started, 3),
            "login_budget_changed": False,
            "redis_storage": getattr(redis, "storage_kind", "docker-volume"),
            "client_max_fps": 30 if native_platform else None,
            "asyncio_debug": bool(environment.get("PYTHONASYNCIODEBUG")),
        }, indent=2) + "\n")
        clients = []
        reconnect_gates = [work / f"client-{index}-released" for index in (1, 2)]
        password = secrets.token_urlsafe(18)
        names = []
        for index in (1, 2):
            (work / f"control-{index}").mkdir(mode=0o700)
            name = "Fixture" + secrets.token_hex(4) + str(index)
            names.append(name)
            client_log = stack.enter_context((output / f"godot-{index}.log").open("wb"))
            client_env = dict(
                os.environ,
                PYAO_TEST_PASSWORD=password,
                PYAO_TEST_USERNAME=name,
                PYAO_TEST_PORT=str(endpoint),
                PYAO_TEST_CA=str(certificate),
                PYAO_TEST_INDEX=str(index),
                PYAO_TEST_PEER=str(3 - index),
                PYAO_TEST_DURATION=str(args.seconds),
                PYAO_TEST_MECHANICS="1" if args.scenario != "r10" else "0",
                PYAO_TEST_RELEASED=str(reconnect_gates[index - 1]),
                PYAO_TEST_CONTROL=str(work / f"control-{index}"),
                PYAO_TEST_SCREENSHOT=str(output / f"godot-{index}.png"),
                XDG_DATA_HOME=str(work / f"client-{index}/data"),
                XDG_CONFIG_HOME=str(work / f"client-{index}/config"),
                XDG_CACHE_HOME=str(work / f"client-{index}/cache"),
            )
            executable = args.client_executable
            if executable and args.source and args.scenario == "platform":
                from native_client_profile import isolated_copy
                executable = isolated_copy(executable, work, index, sys.platform)
            command = (
                [str(executable)]
                if args.client_executable
                else [str(args.godot), "--path", str(ROOT)]
            )
            if args.scenario != "platform": command += ["--audio-driver", "Dummy"]
            command += ["--rendering-method", "gl_compatibility"]
            if native_platform:
                # WARP/Apple Software Renderer/llvmpipe comparten CPU con los
                # otros procesos. Usar el mismo presupuesto gráfico en cada SO.
                command += ["--max-fps", "30"]
            if not args.client_executable:
                command += ["res://tests/integration_world.tscn"]
            if args.headless:
                command.insert(1, "--headless")
            client = subprocess.Popen(
                command,
                env=client_env,
                cwd=work,
                stdout=client_log,
                stderr=subprocess.STDOUT,
                **child_process_options(),
            )
            stack.callback(stop, client)
            clients.append(client)
        started = time.monotonic()
        scenario = R10World(redis, work, output, names, clients, server)
        scenario.server_port = endpoint
        scenario.benchmark_password = password

        def restart_server():
            nonlocal server
            arguments = server.args
            stop(server)
            server = subprocess.Popen(
                arguments,
                cwd=work,
                env=environment,
                stdout=server_log,
                stderr=subprocess.STDOUT,
                **child_process_options(),
            )
            stack.callback(stop, server)
            deadline = time.monotonic() + 60
            while True:
                if server.poll() is not None:
                    raise RuntimeError("El servidor no volvió a iniciar")
                try:
                    with socket.create_connection(("127.0.0.1", endpoint), timeout=0.5):
                        break
                except ConnectionRefusedError:
                    if time.monotonic() > deadline:
                        raise TimeoutError("No reabrió el listener")
                    time.sleep(0.1)
            return server

        scenario.restart_server = restart_server
        scenario_steps = scenario.run(locations)
        from src.utils.redis_config import RedisKeys

        while any(client.poll() is None for client in clients):
            server_text = (output / "server.log").read_text()
            if (
                "| ERROR |" in server_text
                or "Traceback (most recent call last)" in server_text
            ):
                raise RuntimeError(
                    "Excepción del servidor durante sesión/reconexión; revisar server.log"
                )
            for index in (1, 2):
                text = (output / f"godot-{index}.log").read_text()
                if "SCRIPT ERROR:" in text or "ERROR:" in text:
                    raise RuntimeError(
                        f"Error de script o recurso en Godot {index}; revisar log"
                    )
                if (
                    "INTEGRATION_WORLD: RECONNECT_WAIT" in text
                    and not reconnect_gates[index - 1].exists()
                ):
                    with redis.client() as store:
                        user_id = store.hget(
                            RedisKeys.account_data(names[index - 1]), "user_id"
                        )
                        if user_id and not store.exists(f"session:{user_id}:owner"):
                            reconnect_gates[index - 1].write_text("released\n")
            if any(client.poll() not in (None, 0) for client in clients):
                raise RuntimeError("Falló un cliente Godot; revisar logs")
            if (
                server.poll() is not None
                or time.monotonic() - started
                > args.seconds + SCENARIO_TIMEOUT_SECONDS[args.scenario]
            ):
                raise TimeoutError("Proceso perdido o plazo total agotado")
            time.sleep(1)
        measured_seconds = []
        reconnect_states = []
        for index in (1, 2):
            log = (output / f"godot-{index}.log").read_text()
            if (
                "INTEGRATION_WORLD: PASS" not in log
                or "SCRIPT ERROR:" in log
                or "ERROR:" in log
            ):
                raise RuntimeError(f"Godot {index} no acredita la prueba completa")
            if password in log:
                raise RuntimeError("Se filtró una credencial sintética en el log")
            if args.client_executable and args.scenario != "platform" and "R10_NATIVE: true" not in log:
                raise RuntimeError(
                    "El export no ejecutó el perfil nativo de aceptación"
                )
            measured = re.search(r"INTEGRATION_WORLD: PASS seconds=([0-9.]+)", log)
            if measured is None or float(measured[1]) < args.seconds:
                raise RuntimeError("Godot no acredita la duración solicitada")
            measured_seconds.append(float(measured[1]))
            state = re.search(r"INTEGRATION_WORLD: RECONNECT_STATE (.+)", log)
            if not state:
                raise RuntimeError(
                    "Falta la prueba de inventario y libro tras reconectar"
                )
            reconnect_states.append(json.loads(state[1]))
        if password in (output / "server.log").read_text():
            raise RuntimeError(
                "Se filtró una credencial sintética en el log del servidor"
            )
        with redis.client() as store:
            for name in names:
                account = store.hgetall(RedisKeys.account_data(name))
                if not account:
                    raise RuntimeError("Falta la cuenta creada por UI")
                deadline = time.monotonic() + 15
                while store.exists(f"session:{account['user_id']}:owner"):
                    if time.monotonic() > deadline:
                        raise TimeoutError(
                            "La desconexión de Godot no liberó la sesión"
                        )
                    time.sleep(0.1)
        if args.snap_installed or args.ui_executable:
            ui_output = output / "installed-snap"
            ui_environment = dict(
                os.environ,
                PYAO_TEST_USERNAME=names[0],
                PYAO_TEST_PASSWORD=password,
                PYAO_TEST_AUDIO=args.snap_audio,
            )
            arguments = [
                "/usr/bin/python3",
                str(ROOT / "tools/snap-ui-smoke.py"),
                "--port",
                str(endpoint),
                "--ca",
                str(certificate),
                "--output",
                str(ui_output),
                "--version",
                args.release_version,
                "--commit",
                args.client_commit,
            ]
            if args.ui_executable:
                arguments += ["--executable", str(args.ui_executable)]
            with (
                redis.client() as store,
                (output / "snap-ui-run.log").open("wb") as ui_log,
            ):
                user_id = store.hget(RedisKeys.account_data(names[0]), "user_id")
                inventory_key = RedisKeys.player_inventory(int(user_id))
                before_inventory = store.hgetall(inventory_key)
                expected_source = before_inventory.get("slot_30")
                expected_destination = before_inventory.get("slot_1")
                if not expected_source:
                    raise RuntimeError(
                        "El recorrido UI instalado necesita un ítem real en slot 30"
                    )
                positions = set()
                ui_process = subprocess.Popen(
                    arguments,
                    cwd=work,
                    env=ui_environment,
                    stdout=ui_log,
                    stderr=subprocess.STDOUT,
                    **child_process_options(),
                )
                try:
                    deadline = time.monotonic() + 120
                    while ui_process.poll() is None:
                        positions.add(
                            tuple(
                                sorted(
                                    store.hgetall(f"player:{user_id}:position").items()
                                )
                            )
                        )
                        if time.monotonic() > deadline:
                            raise TimeoutError(
                                "El Snap no completó su recorrido por UI"
                            )
                        time.sleep(0.2)
                    if ui_process.returncode != 0:
                        raise RuntimeError(
                            "Falló la UI del Snap; revisar sus capturas y logs"
                        )
                    if len(positions) < 2:
                        raise RuntimeError(
                            "El input del Snap no cambió la posición en Redis"
                        )
                    if (
                        store.hget(inventory_key, "slot_1") != expected_source
                        or store.hget(inventory_key, "slot_30") != expected_destination
                    ):
                        raise RuntimeError(
                            "El drag del Snap no confirmó inventario en Redis"
                        )
                    deadline = time.monotonic() + 15
                    while store.exists(f"session:{user_id}:owner"):
                        if time.monotonic() > deadline:
                            raise TimeoutError("El cierre del Snap no liberó su sesión")
                        time.sleep(0.1)
                finally:
                    stop(ui_process)

        async def live_session_shutdown():
            from src.operations.two_client_smoke import ProtocolPeer, login_packet
            from src.network.packet_id import ServerPacketID

            peers = []
            try:
                for name in names:
                    reader, writer = await asyncio.open_connection(
                        "127.0.0.1",
                        endpoint,
                        ssl=ssl.create_default_context(cafile=certificate),
                        server_hostname="127.0.0.1",
                    )
                    peer = ProtocolPeer(reader, writer)
                    peers.append(peer)
                    await peer.send(login_packet(name, password))
                    await peer.wait(
                        lambda frames: any(
                            frame[0] == ServerPacketID.LOGGED for frame in frames
                        )
                    )
                await asyncio.to_thread(stop, server)
                for peer in peers:
                    async with asyncio.timeout(8):
                        await peer.task
                    if peer.error is not None:
                        raise RuntimeError(
                            "El cierre de TLS dejó un frame incompleto"
                        ) from peer.error
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
        proof = {
            "passed": True,
            "clients": 2,
            "seconds": round(elapsed, 2),
            "started_at": started_at,
            "completed_at": datetime.now(UTC).isoformat(),
            "long_acceptance": args.seconds >= 1800 and not args.headless,
            "tls": True,
            "installed_wheel": not args.source,
            "source_checkout": args.source,
            "server_commit": args.server_commit,
            "client_commit": args.client_commit,
            "wheel_sha256": hashlib.sha256(args.wheel.read_bytes()).hexdigest() if args.wheel else None,
            "redis": "8.10.2",
            "godot": args.godot_version,
            "graceful_sigterm": True,
        }
        proof["live_tls_sessions_drained"] = 2
        proof["release_version"] = args.release_version
        proof["installed_snap_ui"] = args.snap_installed
        proof["snap_install_source"] = args.snap_source if args.snap_installed else None
        proof["godot_measured_seconds"] = measured_seconds
        proof["reconnect_states"] = reconnect_states
        proof["native_export"] = bool(args.client_executable)
        if args.client_executable:
            proof["export_sha256"] = hashlib.sha256(
                args.client_executable.read_bytes()
            ).hexdigest()
            proof["export_entrypoint_sha256"] = hashlib.sha256(
                (args.client_executable.parent / "override.cfg").read_bytes()
            ).hexdigest()
            proof["export_provenance"] = verify_native_export(
                args.client_executable,
                args.client_commit,
                long_run=args.seconds >= 1800,
            )
            pack = args.client_executable.with_suffix(".pck")
            if pack.exists():
                proof["export_pck_sha256"] = hashlib.sha256(
                    pack.read_bytes()
                ).hexdigest()
        proof["acceptance"] = acceptance(
            scenario_steps,
            min(measured_seconds),
            graphical=not args.headless,
            exported=bool(args.client_executable),
        )
        criterion = (
            "functional_passed" if args.scenario == "r10" else "test_execution_passed"
        )
        if not proof["acceptance"][criterion]:
            raise RuntimeError(
                "La regresión no cubre todos los escenarios: " + args.scenario
            )
        if args.scenario != "r10":
            proof["scenario"] = args.scenario
            proof["regression_passed"] = proof["passed"]
            if args.scenario != "full":
                proof.pop("passed")
        (output / "result.json").write_text(json.dumps(proof, indent=2) + "\n")
        print(json.dumps(proof))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server-project", type=Path, required=True)
    origin = parser.add_mutually_exclusive_group(required=True)
    origin.add_argument("--wheel", type=Path)
    origin.add_argument("--source", action="store_true", help="Prueba el checkout con su entorno uv existente, sin construir paquetes")
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument(
        "--client-executable",
        type=Path,
        help="Export nativo del mismo checkout; obligatorio para R10 prolongada",
    )
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--seconds", type=int, default=1800)
    parser.add_argument(
        "--scenario",
        choices=tuple(SCENARIO_TIMEOUT_SECONDS),
        default="r10",
        help="Regresión que se ejecuta antes del período de observación",
    )
    parser.add_argument("--headless", action="store_true")
    parser.add_argument(
        "--server-debug",
        action="store_true",
        help="Logs detallados del servidor exclusivo del ensayo",
    )
    parser.add_argument("--redis-runtime", type=Path)
    parser.add_argument("--snap-installed", action="store_true")
    parser.add_argument(
        "--snap-audio", choices=("Dummy", "PulseAudio"), default="Dummy"
    )
    parser.add_argument(
        "--snap-source", choices=("artifact", "store"), default="artifact"
    )
    parser.add_argument(
        "--ui-executable",
        type=Path,
        help="Desarrollo de UI fuera de Snap; no acredita instalación",
    )
    parser.add_argument("--worker", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if not 10 <= args.seconds <= 7200:
        parser.error("La duración debe estar entre 10 y 7200 segundos")
    for name in (
        "server_project",
        "wheel",
        "godot",
        "client_executable",
        "output",
        "redis_runtime",
        "ui_executable",
    ):
        if getattr(args, name) is not None:
            setattr(args, name, getattr(args, name).resolve())
    if not args.worker and args.output.exists() and any(args.output.iterdir()):
        parser.error(
            "La salida debe ser nueva para no confundir evidencia de ejecuciones anteriores"
        )
    args.output.mkdir(parents=True, exist_ok=True)
    if not args.source:
        source_proof = verify_wheel_source(args.server_project, args.wheel)
        (args.output / "wheel-source.json").write_text(json.dumps(source_proof, indent=2) + "\n")
    else:
        for project, label in ((args.server_project, "server"), (ROOT, "client")):
            files = subprocess.check_output(["git", "-C", str(project), "ls-files", "-co", "--exclude-standard"], text=True).splitlines()
            proof = {name: hashlib.sha256((project / name).read_bytes()).hexdigest() for name in sorted(set(files)) if (project / name).is_file()}
            (args.output / (label + "-source.json")).write_text(json.dumps(proof, indent=2) + "\n")
    args.server_commit = subprocess.check_output(
        ["git", "-C", str(args.server_project), "rev-parse", "HEAD"], text=True
    ).strip()
    args.client_commit = subprocess.check_output(
        ["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True
    ).strip()
    args.godot_version = subprocess.check_output(
        [str(args.godot), "--version"], text=True
    ).strip()
    args.release_version = tomllib.loads(
        (args.server_project / "pyproject.toml").read_text()
    )["project"]["version"]
    client_version = re.search(
        r'^config/version="([^"]+)"$',
        (ROOT / "project.godot").read_text(),
        re.MULTILINE,
    )
    if client_version is None or client_version[1] != args.release_version:
        parser.error("Servidor y cliente deben declarar exactamente la misma versión")
    if args.seconds >= 1800:
        if args.client_executable is None or args.headless:
            parser.error(
                "R10 prolongada requiere --client-executable y ejecución gráfica"
            )
        for project in (ROOT, args.server_project):
            if subprocess.check_output(
                ["git", "-C", str(project), "status", "--porcelain"], text=True
            ).strip():
                parser.error(
                    "La aceptación prolongada exige ambos checkouts limpios y commits fijos"
                )
    manifest = json.loads((ROOT / "tools/godot-release.json").read_text())
    if args.godot_version != manifest["editor_version"]:
        parser.error("Motor distinto del manifiesto fijado")
    if args.client_executable:
        verify_native_export(
            args.client_executable, args.client_commit, long_run=args.seconds >= 1800
        )
        profile = args.client_executable.parent / "override.cfg"
        if (
            not profile.is_file()
            or profile.read_bytes() != (ROOT / "tests/r10-export.cfg").read_bytes()
        ):
            parser.error(
                "El export de aceptación requiere su override.cfg fijado junto al ejecutable"
            )
        exported_version = subprocess.check_output(
            [str(args.client_executable), "--headless", "--version"], text=True
        ).strip()
        if exported_version != args.godot_version:
            parser.error("El export nativo usa un motor distinto del manifiesto")
    if args.worker:
        worker(args)
        return
    environment = {
        k: v for k, v in os.environ.items() if not k.startswith(("PYAO_", "SNAP"))
    }
    environment.update(PYTHONPATH="", PYTHONNOUSERSITE="1")
    with tempfile.TemporaryDirectory(prefix="pyao-godot-world-") as temporary:
        work = Path(temporary)
        if args.source:
            python = args.server_project / (".venv/Scripts/python.exe" if os.name == "nt" else ".venv/bin/python")
            if not python.is_file():
                parser.error("El modo fuente necesita el entorno uv .venv del servidor")
            environment["PYTHONPATH"] = str(args.server_project)
        else:
            run(
                ["uv", "venv", "--python", sys.executable, str(work / "venv")],
                cwd=work,
                env=environment,
            )
            python = work / ("venv/Scripts/python.exe" if os.name == "nt" else "venv/bin/python")
            runtime = subprocess.check_output(
                ["uv", "export", "--locked", "--no-dev", "--no-emit-project"],
                cwd=args.server_project,
                text=True,
            )
            run(
                [
                    "uv",
                    "pip",
                    "install",
                    "--python",
                    str(python),
                    "--require-hashes",
                    "-r",
                    "-",
                ],
                input=runtime,
                cwd=work,
                env=environment,
            )
            run(
                [
                    "uv",
                    "pip",
                    "install",
                    "--python",
                    str(python),
                    "--no-deps",
                    str(args.wheel),
                ],
                cwd=work,
                env=environment,
            )
        # Argumentos absolutos para que el proceso instalado trabaje fuera de los checkouts.
        arguments = [
            str(python),
            str(Path(__file__).resolve()),
            "--worker",
            "--server-project",
            str(args.server_project),
            "--godot",
            str(args.godot),
            "--output",
            str(args.output),
            "--seconds",
            str(args.seconds),
            "--scenario",
            args.scenario,
        ]
        arguments += ["--source"] if args.source else ["--wheel", str(args.wheel)]
        if args.headless:
            arguments.append("--headless")
        if args.server_debug:
            arguments.append("--server-debug")
        if args.redis_runtime:
            arguments += ["--redis-runtime", str(args.redis_runtime)]
        if args.client_executable:
            arguments += ["--client-executable", str(args.client_executable)]
        if args.snap_installed:
            arguments.append("--snap-installed")
        if args.ui_executable:
            arguments += ["--ui-executable", str(args.ui_executable)]
        arguments += ["--snap-audio", args.snap_audio]
        arguments += ["--snap-source", args.snap_source]
        child = subprocess.Popen(
            arguments, cwd=work, env=environment, **({"creationflags": subprocess.CREATE_NEW_PROCESS_GROUP} if os.name == "nt" else {"start_new_session": True})
        )
        try:
            if (
                child.wait(
                    timeout=args.seconds + SCENARIO_TIMEOUT_SECONDS[args.scenario] + 120
                )
                != 0
            ):
                raise RuntimeError(
                    "Falló el ensayo instalado; revisar los logs conservados"
                )
        finally:
            if child.poll() is None:
                child.send_signal(signal.CTRL_BREAK_EVENT if os.name == "nt" else signal.SIGTERM)
                try:
                    child.wait(timeout=120)
                except subprocess.TimeoutExpired:
                    # El grupo contiene únicamente worker, servidor, Redis y Godot propios.
                    if os.name == "nt": child.kill()
                    else: os.killpg(child.pid, signal.SIGKILL)
                    child.wait(timeout=5)


if __name__ == "__main__":
    main()
