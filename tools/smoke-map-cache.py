#!/usr/bin/env python3
"""Ejercita caché y teardown con el export nativo y render OpenGL real."""

import argparse
from datetime import UTC, datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--client-executable", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cycles", type=int, default=80)
    args = parser.parse_args()
    if not 10 <= args.cycles <= 300:
        parser.error("Usar entre 10 y 300 ciclos")
    source = args.client_executable.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    started = datetime.now(UTC).isoformat()
    clock = time.monotonic()
    timed_out = False
    with tempfile.TemporaryDirectory(prefix="pyao-map-cache-stress-") as directory:
        root = Path(directory)
        executable = root / source.name
        shutil.copy2(source, executable)
        executable.chmod(0o755)
        with executable.open("rb") as binary:
            export_sha256 = hashlib.file_digest(binary, "sha256").hexdigest()
        pack = source.with_suffix(".pck")
        if pack.exists():
            shutil.copy2(pack, executable.with_suffix(".pck"))
        (root / "override.cfg").write_text(
            '[application]\nrun/main_scene="res://tests/map_cache_stress.tscn"\nrun/flush_stdout_on_print=true\n'
        )
        environment = {
            key: value
            for key, value in os.environ.items()
            if not key.startswith(("PYAO_", "SNAP"))
        }
        for key in ("WAYLAND_DISPLAY", "WAYLAND_SOCKET"):
            environment.pop(key, None)
        for suffix in ("DATA", "CONFIG", "CACHE"):
            path = root / suffix.lower()
            path.mkdir()
            environment[f"XDG_{suffix}_HOME"] = str(path)
        environment.update(
            LIBGL_ALWAYS_SOFTWARE="1",
            GODOT_SILENCE_ROOT_WARNING="1",
            PYAO_MAP_STRESS_CYCLES=str(args.cycles),
        )
        command = [
            "xvfb-run",
            "-a",
            "-s",
            "-screen 0 800x600x24",
            str(executable),
            "--display-driver",
            "x11",
            "--audio-driver",
            "Dummy",
            "--rendering-method",
            "gl_compatibility",
        ]
        with (output / "render.log").open("w") as log:
            process = subprocess.Popen(
                command,
                cwd=root,
                env=environment,
                stdout=log,
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )
            try:
                process.wait(timeout=210)
            except subprocess.TimeoutExpired:
                timed_out = True
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
    log = (output / "render.log").read_text()
    errors = len(re.findall(r"(?:^|\n)\s*(?:ERROR:|SCRIPT ERROR:)", log))
    passed = (
        process.returncode == 0
        and not timed_out
        and errors == 0
        and f"MAP_CACHE_STRESS: PASS cycles={args.cycles}" in log
    )
    result = {
        "passed": passed,
        "native_export": True,
        "renderer": "gl_compatibility",
        "cycles": args.cycles,
        "map_switches": args.cycles * 4,
        "render_errors": errors,
        "timed_out": timed_out,
        "exit_code": process.returncode,
        "started_at": started,
        "completed_at": datetime.now(UTC).isoformat(),
        "seconds": time.monotonic() - clock,
        "export_sha256": export_sha256,
    }
    (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
