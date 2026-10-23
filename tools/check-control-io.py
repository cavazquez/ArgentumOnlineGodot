"""Exercise the actual Godot reader with real file locks and invalid requests."""
import argparse
from contextlib import contextmanager
import ctypes
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
# Separate engine startup from the reader's unchanged 1000 ms I/O budget.
# Child logs go directly to files so waiting for its signal never blocks stdout.
ENGINE_STARTUP_SECONDS = 30


@contextmanager
def locked(path):
    if os.name == "nt":
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.CreateFileW.argtypes = [ctypes.c_wchar_p, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_void_p, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_void_p]
        kernel.CreateFileW.restype = ctypes.c_void_p
        kernel.CloseHandle.argtypes = [ctypes.c_void_p]
        handle = kernel.CreateFileW(str(path), 0x80000000, 0, None, 3, 0x80, None)
        if handle == ctypes.c_void_p(-1).value:
            raise ctypes.WinError(ctypes.get_last_error())
        try:
            yield
        finally:
            if not kernel.CloseHandle(handle):
                raise ctypes.WinError(ctypes.get_last_error())
    else:
        mode = path.stat().st_mode & 0o777
        path.chmod(0)
        try:
            yield
        finally:
            path.chmod(mode)


def run(godot, output):
    output.mkdir(parents=True, exist_ok=False)
    records = []
    case_started = {}
    with tempfile.TemporaryDirectory(prefix="pyao control con espacios ñ ") as temporary:
        project = Path(temporary)
        (project / "project.godot").write_text('[application]\nconfig/name="Control IO fixture"\n', encoding="utf-8")
        (project / "tests").mkdir()
        shutil.copyfile(ROOT / "tests/control_request_reader.gd", project / "tests/control_request_reader.gd")
        shutil.copyfile(ROOT / "tools/control-io-probe.gd", project / "probe.gd")

        def file_snapshot():
            entries = []
            for folder, _, names in os.walk(project):
                for name in names:
                    path = Path(folder) / name
                    row = {"file": str(path.relative_to(project))}
                    try:
                        stat = path.stat()
                        row.update(bytes=stat.st_size, modified_unix=stat.st_mtime)
                    except OSError as error:
                        row.update(stat_errno=error.errno, stat_winerror=getattr(error, "winerror", None))
                    entries.append(row)
            return entries

        def start(name, body, mode="reader", timeout=1000):
            case_started[name] = time.time()
            request = project / (name + ".request.json")
            request.write_bytes(body)
            result = project / (name + ".result.json")
            observed = project / (name + ".observed.json")
            command = [str(godot), "--headless", "--audio-driver", "Dummy", "--path", str(project), "--script", "res://probe.gd", "--",
                       "--mode", mode, "--request", str(request), "--result", str(result), "--observed", str(observed), "--timeout-ms", str(timeout)]
            return request, result, observed, command

        def launch(name, command):
            # Drain output while waiting for the child signal, also on Windows.
            with (output / (name + ".log")).open("wb") as log:
                return subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)

        def finish(name, process, result):
            try:
                process.wait(timeout=ENGINE_STARTUP_SECONDS + 2)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
                (output / (name + "-timeout.json")).write_text(json.dumps({
                    "phase": "process-timeout", "process_returncode": process.returncode,
                    "case_started_unix": case_started[name], "observed_unix": time.time(),
                    "files": file_snapshot(),
                }, indent=2) + "\n", encoding="utf-8")
                raise
            log = (output / (name + ".log")).read_bytes()
            assert process.returncode == 0 and b"ERROR:" not in log, name
            value = json.loads(result.read_text(encoding="utf-8"))
            value["process_seconds"] = round(time.time() - case_started[name], 3)
            (output / (name + ".json")).write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
            records.append({"case": name, **value})
            return value

        def wait_observed(name, process, observed, result):
            deadline = time.monotonic() + ENGINE_STARTUP_SECONDS
            while not observed.exists():
                if process.poll() is not None or time.monotonic() >= deadline:
                    (output / (name + "-wait-failure.json")).write_text(json.dumps({
                        "case_started_unix": case_started[name], "observed_unix": time.time(),
                        "expected_signal": str(observed), "signal_exists": observed.exists(),
                        "process_returncode": process.poll(),
                        "files": file_snapshot(),
                    }, indent=2) + "\n", encoding="utf-8")
                    finish(name, process, result)
                    raise AssertionError("The reader never reached the controlled file operation")
                time.sleep(0.005)

        body = json.dumps({"op": "snapshot", "text": "lectura ñ"}, ensure_ascii=False).encode("utf-8")
        request, result, _, command = start("healthy", body)
        value = finish("healthy", launch("healthy", command), result)
        assert value["ok"] and value["attempts"] == 1 and value["operation"] == "snapshot" and value["byte_count"] == len(body)

        request, result, observed, command = start("legacy-locked", body, mode="legacy")
        process = launch("legacy-locked", command)
        try:
            wait_observed("legacy-locked", process, observed, result)
            # Lock after the old reader checked existence, before it opens the file.
            with locked(request):
                Path(str(observed) + ".continue").write_bytes(b"")
                value = finish("legacy-locked", process, result)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
        assert value["file_exists"] and value["byte_count"] == 0 and value["io_error"] != 0

        request, result, observed, command = start("transient-lock", body)
        with locked(request):
            process = launch("transient-lock", command)
            wait_observed("transient-lock", process, observed, result)
        value = finish("transient-lock", process, result)
        assert value["ok"] and value["attempts"] > 1 and value["io_errors"] and value["byte_count"] == len(body)

        request, result, _, command = start("permanent-lock", body, timeout=200)
        with locked(request):
            value = finish("permanent-lock", launch("permanent-lock", command), result)
        assert not value["ok"] and value["kind"] == "open" and value["io_error"] != 0 and value["elapsed_ms"] >= 200

        for name, payload, kind in (("empty", b"", "empty"), ("truncated", b'{"op":', "json"),
                                    ("array", b"[]", "shape"), ("null", b"null", "shape"),
                                    ("missing-op", b"{}", "shape"), ("invalid-op", b'{"op":42}', "shape")):
            _, result, _, command = start(name, payload)
            value = finish(name, launch(name, command), result)
            assert not value["ok"] and value["kind"] == kind and value["attempts"] == 1 and value["io_error"] == 0
    proof = {"passed": True, "platform": sys.platform, "native_windows_lock": os.name == "nt", "cases": records,
             "production_data_used": False, "login_budget_changed": False,
             "engine_startup_budget_seconds": ENGINE_STARTUP_SECONDS, "read_budget_ms": 1000,
             "output_transport": "regular-file"}
    (output / "result.json").write_text(json.dumps(proof, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"passed": True, "cases": len(records), "platform": sys.platform}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    run(args.godot.resolve(), args.output.resolve())
