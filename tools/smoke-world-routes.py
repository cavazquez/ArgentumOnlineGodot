#!/usr/bin/env python3
"""Renderiza todos los mapas y pares de cruce en Linux con OpenGL real.

Esta prueba acredita carga/renderizado/caché. Las transiciones por TCP y las
condiciones de cada casilla se verifican por separado.
"""

import argparse
import base64
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

ROOT = Path(__file__).resolve().parents[1]


def validate_evidence(proof, topology):
    expected_maps = set(topology["maps"])
    expected_pairs = {(int(edge["from"]), int(edge["to"])) for edge in topology["edges"]}
    if proof.get("passed") is not True or proof.get("display_server") != "X11":
        raise ValueError("Falta renderizado real satisfactorio")
    if proof.get("network_crossings") is not False:
        raise ValueError("La evidencia debe distinguir renderizado y cruces de red")
    if set(proof.get("maps", {})) != expected_maps:
        raise ValueError("No se renderizaron todos los mapas")
    actual_pairs = proof.get("rendered_pairs", [])
    if any(
        not isinstance(pair, list)
        or len(pair) != 2
        or any(type(value) is not int for value in pair)
        for pair in actual_pairs
    ):
        raise ValueError("Par de mapas inválido")
    actual_set = {tuple(pair) for pair in actual_pairs}
    if actual_set != expected_pairs or len(actual_pairs) != len(actual_set):
        raise ValueError("No se renderizaron exactamente todos los pares dirigidos")
    for value in proof["maps"].values():
        if (
            not value.get("rendered")
            or len(base64.b64decode(value["flags"], validate=True)) != 10000
        ):
            raise ValueError("Falta una máscara completa del mapa renderizado")
        budget = value["cache"]
        if (
            not 0 <= budget["views"] <= budget["limit_views"] <= 3
            or not 0 <= budget["estimated_bytes"] <= budget["limit_bytes"] <= 67108864
        ):
            raise ValueError("La caché superó su presupuesto")
    return {"maps_rendered": len(expected_maps), "directed_pairs_rendered": len(expected_pairs)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    runtime = parser.add_mutually_exclusive_group(required=True)
    runtime.add_argument("--godot", type=Path)
    runtime.add_argument("--client-executable", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    topology = json.loads((ROOT / "protocol/world-topology.json").read_text())
    started = datetime.now(UTC).isoformat()
    clock = time.monotonic()
    timed_out = False
    export_hash = None
    with tempfile.TemporaryDirectory(prefix="pyao-all-world-routes-") as directory:
        work = Path(directory)
        environment = {
            key: value for key, value in os.environ.items() if not key.startswith(("PYAO_", "SNAP"))
        }
        for key in ("WAYLAND_DISPLAY", "WAYLAND_SOCKET"):
            environment.pop(key, None)
        for suffix in ("DATA", "CONFIG", "CACHE"):
            folder = work / suffix.lower()
            folder.mkdir()
            environment[f"XDG_{suffix}_HOME"] = str(folder)
        environment.update(
            LIBGL_ALWAYS_SOFTWARE="1",
            GODOT_SILENCE_ROOT_WARNING="1",
            PYAO_MAP_AUDIT_OUTPUT=str(output / "rendered-world.json"),
        )
        if args.client_executable:
            source = args.client_executable.resolve()
            executable = work / source.name
            shutil.copy2(source, executable)
            executable.chmod(0o755)
            export_hash = hashlib.sha256(executable.read_bytes()).hexdigest()
            if source.with_suffix(".pck").exists():
                shutil.copy2(source.with_suffix(".pck"), executable.with_suffix(".pck"))
            (work / "override.cfg").write_text(
                '[application]\nrun/main_scene="res://tests/world_routes_audit.tscn"\nrun/flush_stdout_on_print=true\n'
            )
            command = [str(executable)]
        else:
            command = [
                str(args.godot.resolve()),
                "--path",
                str(ROOT),
                "res://tests/world_routes_audit.tscn",
            ]
        command = [
            "xvfb-run",
            "-a",
            "-s",
            "-screen 0 1024x768x24",
            *command,
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
                cwd=work,
                env=environment,
                stdout=log,
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )
            try:
                process.wait(timeout=390)
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
    problem = ""
    counts = {}
    try:
        counts = validate_evidence(
            json.loads((output / "rendered-world.json").read_text()), topology
        )
    except (OSError, ValueError, KeyError, TypeError) as exc:
        problem = str(exc)
    passed = (
        process.returncode == 0
        and not timed_out
        and errors == 0
        and not problem
        and "ALL_MAPS_AUDIT: PASS" in log
    )
    result = {
        "passed": passed,
        **counts,
        "network_crossings": False,
        "native_export": bool(args.client_executable),
        "export_sha256": export_hash,
        "topology_sha256": hashlib.sha256(
            (ROOT / "protocol/world-topology.json").read_bytes()
        ).hexdigest(),
        "render_errors": errors,
        "exit_code": process.returncode,
        "timed_out": timed_out,
        "diagnostic": problem,
        "started_at": started,
        "completed_at": datetime.now(UTC).isoformat(),
        "seconds": time.monotonic() - clock,
    }
    (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
