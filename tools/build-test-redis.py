#!/usr/bin/env python3
"""Compila Redis oficial fijado para fixtures nativas; nunca instala un servicio."""

import argparse
import hashlib
import http.client
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import time
import urllib.error
import urllib.request

URL = "https://codeload.github.com/redis/redis/tar.gz/refs/tags/8.10.2"
SHA256 = "541a374b753a8405683dd88560465791acc98cf09445ef10ec1bd286904273e8"


def download(archive):
    """Recupera caídas de red sin reutilizar parciales ni aceptar otro contenido."""
    for attempt in range(3):
        archive.unlink(missing_ok=True)
        try:
            with urllib.request.urlopen(URL, timeout=120) as source, archive.open("wb") as target:
                shutil.copyfileobj(source, target)
        except (urllib.error.URLError, TimeoutError, ConnectionError, http.client.IncompleteRead) as error:
            permanent = isinstance(error, urllib.error.HTTPError) and error.code not in {408, 429, 500, 502, 503, 504}
            if permanent or attempt == 2:
                raise
            print(f"Redis source download attempt {attempt + 1}/3: {type(error).__name__}; retrying", flush=True)
            time.sleep(2 ** (attempt + 1))
            continue
        with archive.open("rb") as stream:
            if hashlib.file_digest(stream, "sha256").hexdigest() != SHA256:
                raise ValueError("SHA256 de Redis distinto del manifiesto oficial")
        return


def wsl(path):
    return subprocess.check_output(["wsl", "--exec", "wslpath", "-u", str(path)], text=True).strip()


def build(destination):
    destination.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="pyao-redis-build-") as temporary:
        root = Path(temporary)
        archive = root / "redis.tar.gz"
        download(archive)
        with tarfile.open(archive) as package:
            package.extractall(root, filter="data")
        source = root / "redis-8.10.2"
        command = ["make", "-C", str(source), "MALLOC=libc", "BUILD_TLS=no", f"-j{min(4, os.cpu_count() or 2)}"]
        if os.name == "nt":
            command = ["wsl", "--exec", "make", "-C", wsl(source), *command[3:]]
        subprocess.run(command, check=True)
        for name in ("redis-server", "redis-cli", "redis-check-rdb"):
            shutil.copy2(source / "src" / name, destination / name)
            (destination / name).chmod(0o755)
        (destination / "runtime.json").write_text(json.dumps({"version": "8.10.2", "url": URL, "sha256": SHA256, "wsl": os.name == "nt"}) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", type=Path, required=True)
    build(parser.parse_args().destination.resolve())
