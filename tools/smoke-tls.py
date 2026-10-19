#!/usr/bin/env python3
"""Prueba Godot real contra endpoints locales TLS/TCP y certificados descartables."""

import asyncio
from contextlib import AsyncExitStack
import os
from pathlib import Path
import ssl
import subprocess
import tempfile

PROJECT = Path(__file__).resolve().parent.parent
CANARY = b"SYNTHETIC_TLS_CANARY_3"
# WORLD_STATE (512) está incluido; WEATHER (64) sigue reservado.
BURST_CAPABILITIES = b"\xfa\x01\xbf\x03\x00\x00"


def certificates(root: Path) -> dict[str, ssl.SSLContext]:
    def openssl(*args: str) -> None:
        subprocess.run(["openssl", *args], cwd=root, check=True, capture_output=True)

    openssl("req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", "ca.key",
            "-out", "ca.crt", "-subj", "/CN=ProyectoAO Synthetic CA", "-days", "2")
    openssl("req", "-newkey", "rsa:2048", "-nodes", "-keyout", "server.key",
            "-out", "server.csr", "-subj", "/CN=localhost")
    contexts = {}
    for case in ["valid", "hostname", "expired"]:
        extension = root / (case + ".ext")
        extension.write_text("subjectAltName=" + ("DNS:other.invalid" if case == "hostname"
                                                  else "DNS:localhost,IP:127.0.0.1") + "\n")
        if case == "expired":
            (root / "index.txt").write_text("")
            (root / "serial").write_text("1000\n")
            (root / "newcerts").mkdir()
            (root / "ca.cnf").write_text("[ca]\ndefault_ca=local\n[local]\n"
                "database=index.txt\nserial=serial\nnew_certs_dir=newcerts\n"
                "certificate=ca.crt\nprivate_key=ca.key\ndefault_md=sha256\n"
                "default_days=1\npolicy=subject_policy\n[subject_policy]\ncommonName=supplied\n")
            openssl("ca", "-batch", "-notext", "-config", "ca.cnf", "-in", "server.csr",
                    "-out", "expired.crt", "-startdate", "20200101000000Z",
                    "-enddate", "20200102000000Z", "-extfile", extension.name)
        else:
            openssl("x509", "-req", "-in", "server.csr", "-CA", "ca.crt", "-CAkey", "ca.key",
                    "-CAcreateserial", "-out", case + ".crt", "-days", "1", "-extfile", extension.name)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(root / (case + ".crt"), root / "server.key")
        contexts[case] = context
    return contexts


async def run() -> None:
    engine = os.environ.get("GODOT_BIN", "godot")
    with tempfile.TemporaryDirectory(prefix="pyao-tls-") as directory:
        root = Path(directory)
        contexts = certificates(root)
        async with AsyncExitStack() as stack:
            captured: dict[str, bytearray] = {case: bytearray() for case in ["valid", "hostname", "expired", "stall", "tcp", "burst"]}
            clients: set[asyncio.Task] = set()

            async def handle(reader, writer, case):
                task = asyncio.current_task()
                clients.add(task)
                try:
                    while data := await reader.read(65536):
                        captured[case].extend(data)
                        if case == "burst":
                            writer.write(b"\x00\x01")
                            await writer.drain()
                            request = await reader.readexactly(6)
                            captured[case].extend(request)
                            if request != BURST_CAPABILITIES:
                                raise RuntimeError("El cliente no negoció después de Logged")
                            for _ in range(480):
                                writer.write(b"\x58")
                                await writer.drain()
                                await asyncio.sleep(0)
                            writer.write(BURST_CAPABILITIES)
                            await writer.drain()
                        elif case != "stall":
                            writer.write(b"\x58")
                            await writer.drain()
                except (ConnectionError, ssl.SSLError):
                    pass
                finally:
                    writer.close()
                    try:
                        await writer.wait_closed()
                    except (ConnectionError, ssl.SSLError):
                        pass
                    clients.discard(task)

            ports = {}
            for case in captured:
                server = await asyncio.start_server(lambda r, w, name=case: handle(r, w, name),
                                                    "127.0.0.1", 0, ssl=contexts.get("valid" if case == "burst" else case))
                await stack.enter_async_context(server)
                ports[case] = server.sockets[0].getsockname()[1]
            try:
                for case in ["valid", "untrusted", "hostname", "expired", "stall", "cancel", "immediate", "tcp", "ui", "burst"]:
                    profile = root / case
                    profile.mkdir()
                    endpoint = "stall" if case in ["cancel", "ui"] else "valid" if case in ["untrusted", "immediate"] else case
                    before = {key: len(value) for key, value in captured.items()}
                    env = dict(os.environ, PYAO_TLS_CASE=case, PYAO_TLS_PORT=str(ports[endpoint]),
                               PYAO_TLS_RETRY_PORT=str(ports["valid"]), PYAO_TLS_CA=str(root / "ca.crt"),
                               XDG_DATA_HOME=str(profile / "data"), XDG_CONFIG_HOME=str(profile / "config"),
                               XDG_CACHE_HOME=str(profile / "cache"))
                    process = await asyncio.create_subprocess_exec(engine, "--headless", "--path", str(PROJECT),
                                                                  "res://tests/tls_smoke.tscn", env=env,
                                                                  stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT)
                    try:
                        output, _ = await asyncio.wait_for(process.communicate(), timeout=20)
                    except TimeoutError:
                        process.kill()
                        await process.wait()
                        raise RuntimeError(f"Timeout del escenario TLS {case}") from None
                    log = output.decode(errors="replace")
                    # Errores TLS del motor son esperados en certificados rechazados; scripts nunca.
                    if process.returncode or "SCRIPT ERROR:" in log or f"TLS_SMOKE: {case} PASS" not in log:
                        print(log)
                        raise RuntimeError(f"Falló el escenario TLS {case}")
                    for representation in [CANARY, CANARY.hex().encode(), CANARY.hex(" ").encode()]:
                        if representation.lower() in output.lower():
                            raise RuntimeError("El canario TLS apareció en los logs")
                    if case in ["hostname", "expired"] and len(captured[case]) != before[case]:
                        raise RuntimeError("Se enviaron credenciales antes de verificar el certificado")
                    if case in ["stall", "cancel", "ui"] and CANARY in captured["stall"][before["stall"]:]:
                        raise RuntimeError("Se enviaron credenciales durante el handshake")
                    if case in ["valid", "tcp", "burst"] and CANARY not in captured[case][before[case]:]:
                        raise RuntimeError("Las credenciales sintéticas no llegaron al endpoint validado")
                    for line in log.splitlines():
                        if line.startswith("TLS_BURST:"):
                            print(line)
                    print(f"TLS_SMOKE: {case} PASS")
            finally:
                for client in clients:
                    client.cancel()
                await asyncio.gather(*clients, return_exceptions=True)


if __name__ == "__main__":
    asyncio.run(run())
