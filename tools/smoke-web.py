#!/usr/bin/env python3
"""Export web real, Chromium, HTTPS/WSS y Redis efímero: sin publicar candidatos."""

import argparse
import contextlib
import functools
import hashlib
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import importlib.util
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import ssl
import subprocess
import sys
import tempfile
import threading
import time

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]


def port():
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


def smoke(candidate, server, output):
    from src.operations.redis_sandbox import RedisSandbox
    from r10_world import prepare_fixture

    output.mkdir(parents=True, exist_ok=False)
    manifest = candidate / "candidate-manifest.json"
    record = json.loads(manifest.read_text())
    if record["dirty"] or record["platform"] != "web": raise ValueError("Se requiere un candidato web limpio")
    for name, digest in record["files"].items():
        with (candidate / name).open("rb") as stream:
            if hashlib.file_digest(stream, "sha256").hexdigest() != digest: raise ValueError("Candidato alterado")
    spec = importlib.util.spec_from_file_location("world_runner", ROOT / "tools/integration-world.py")
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    with tempfile.TemporaryDirectory(prefix="pyao-web-") as temporary, RedisSandbox() as fixture, contextlib.ExitStack() as stack:
        work = Path(temporary)
        web_root = work / "web-portable"
        shutil.copytree(candidate, web_root)
        data, _ = prepare_fixture(work, output)
        certificate, key = work / "server.crt", work / "server.key"
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1", "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost,IP:127.0.0.1", "-keyout", str(key), "-out", str(certificate)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        public = subprocess.check_output(["openssl", "x509", "-in", str(certificate), "-pubkey", "-noout"])
        der = subprocess.check_output(["openssl", "pkey", "-pubin", "-outform", "DER"], input=public)
        import base64
        spki = base64.b64encode(hashlib.sha256(der).digest()).decode()
        web_port, wss_port, tcp_port = port(), port(), port()
        origin = f"https://127.0.0.1:{web_port}"
        endpoint = f"wss://127.0.0.1:{wss_port}"
        http = ThreadingHTTPServer(("127.0.0.1", web_port), functools.partial(SimpleHTTPRequestHandler, directory=str(web_root)))
        tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        tls.load_cert_chain(certificate, key)
        http.socket = tls.wrap_socket(http.socket, server_side=True)
        stack.callback(http.server_close)
        stack.callback(http.shutdown)
        threading.Thread(target=http.serve_forever, daemon=True).start()
        env = {k: v for k, v in os.environ.items() if not k.startswith(("PYAO_", "SNAP"))}
        env.update(PYTHONPATH=str(server), PYAO_REDIS__HOST="127.0.0.1", PYAO_REDIS__PORT=str(fixture.port), PYAO_REDIS__PASSWORD_FILE=str(fixture.password_file), PYAO_STATE_DIR=str(work / "state"), PYAO_DATA_DIR=str(data), PYAO_SERVER__WSS_PORT=str(wss_port), PYAO_SERVER__WSS_ORIGINS=json.dumps([origin]))
        log = stack.enter_context((output / "server.log").open("wb"))
        process = subprocess.Popen([str(server / ".venv/bin/python"), "-m", "src.run_server", "--host", "127.0.0.1", "--port", str(tcp_port), "--ssl", "--ssl-cert", str(certificate), "--ssl-key", str(key)], cwd=work, env=env, stdout=log, stderr=subprocess.STDOUT)
        stack.callback(runner.stop, process)
        # El Redis vacío migra el catálogo completo antes de admitir conexiones.
        deadline = time.monotonic() + 240
        while True:
            try:
                with socket.create_connection(("127.0.0.1", wss_port), timeout=0.2): break
            except OSError:
                if process.poll() is not None or time.monotonic() > deadline: raise RuntimeError("WSS no inició; revisar server.log")
                time.sleep(0.1)
        observations = []
        errors = []
        def console(message):
            with (output / "browser-console.log").open("a") as log:
                log.write(message.type + ": " + message.text + "\n")
            if message.type == "error": errors.append(message.text)
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-certificate-errors-spki-list=" + spki])
            context = browser.new_context(viewport={"width": 1000, "height": 750})
            for index in (1, 2):
                username, password = "Web" + secrets.token_hex(4) + str(index), secrets.token_urlsafe(18)
                page = context.new_page()
                page.on("pageerror", lambda error: errors.append(str(error)))
                page.on("console", console)
                page.add_init_script("window.PYAO_TEST_CONTEXT=" + json.dumps({"endpoint": endpoint, "username": username, "password": password, "mode": "login"}))
                page.goto(origin + "/index.html?pyao_acceptance=1", timeout=120000)
                page.wait_for_function("window.PYAO_AUDIO_READY === true", timeout=120000)
                page.locator("canvas").click(position={"x": 20, "y": 20})
                page.evaluate("window.PYAO_AUDIO_CLICKED = true")
                page.wait_for_function("window.PYAO_PROOF !== undefined", timeout=120000)
                proof = page.evaluate("window.PYAO_PROOF")
                observations.append(proof)
                page.screenshot(path=str(output / f"web-{index}.png"))
                if proof.get("passed") is not True: raise RuntimeError("Web: " + json.dumps(proof))
                with fixture.client() as store:
                    uid = store.hget(f"account:{username}:data", "user_id")
                    if not uid or not store.exists(f"session:{uid}:owner"): raise RuntimeError("Login web no confirmado en Redis")
                page.add_init_script("window.PYAO_TEST_CONTEXT=" + json.dumps({"endpoint": endpoint, "username": username, "mode": "persistence"}))
                page.reload(timeout=120000)
                page.wait_for_function("window.PYAO_PROOF !== undefined", timeout=120000)
                restored = page.evaluate("window.PYAO_PROOF")
                if restored.get("passed") is not True: raise RuntimeError("Preferencias perdidas al recargar")
                entries = page.evaluate("Object.entries(localStorage)")
                if password in json.dumps(entries) or any(secret in key.lower() for key, _ in entries for secret in ("password", "account_hash", "session_password")):
                    raise RuntimeError("Un secreto se escribió en el almacenamiento web")
                observations.append(restored)
            blocked = browser.new_context()
            blocked.add_init_script("Storage.prototype.setItem=function(){throw new Error('quota')};Storage.prototype.getItem=function(){throw new Error('blocked')};window.PYAO_TEST_CONTEXT=" + json.dumps({"endpoint": endpoint, "mode": "storage_blocked"}))
            page = blocked.new_page()
            page.on("pageerror", lambda error: errors.append(str(error)))
            page.on("console", console)
            page.goto(origin + "/index.html?pyao_acceptance=1", timeout=120000)
            page.wait_for_function("window.PYAO_PROOF !== undefined", timeout=120000)
            fallback = page.evaluate("window.PYAO_PROOF")
            if fallback.get("passed") is not True: raise RuntimeError("Sin fallback web visible")
            observations.append(fallback)
            blocked.close()
            context.close()
            browser.close()
        runner.stop(process)
        if process.returncode != 0 or errors: raise RuntimeError("Errores del navegador o cierre WSS incompleto: " + str(errors))
        result = {"passed": True, "platform": "web", "client_commit": record["commit"], "server_commit": subprocess.check_output(["git", "-C", str(server), "rev-parse", "HEAD"], text=True).strip(), "candidate_manifest_sha256": hashlib.sha256(manifest.read_bytes()).hexdigest(), "rendering": True, "audio": True, "input": True, "login": True, "preferences": True, "outside_checkout": True, "wss": True, "browser": "Chromium", "certificate": "fixture SPKI pin only", "observations": observations}
        (output / "web-proof.json").write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("candidate", "server", "output"): parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    smoke(args.candidate.resolve(), args.server.resolve(), args.output.resolve())
