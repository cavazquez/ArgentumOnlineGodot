"""Limpieza acotada de la copia temporal propia, sin repetir pruebas nativas."""
from contextlib import contextmanager
import json
from pathlib import Path
import sys
import tempfile
import time


def cleanup_owned(temporary, output, *, platform_name=None, timeout=10.0):
    platform_name = sys.platform if platform_name is None else platform_name
    started = time.monotonic()
    attempts = 0
    while True:
        attempts += 1
        try:
            temporary.cleanup()
            break
        except OSError as error:
            elapsed = time.monotonic() - started
            retryable = (platform_name == "win32" and isinstance(error, PermissionError)
                         and getattr(error, "winerror", None) in (32, 33))
            if not retryable or elapsed >= timeout:
                (output / "portable-cleanup.json").write_text(json.dumps({
                    "passed": False, "attempts": attempts, "elapsed_seconds": elapsed,
                    "timeout_seconds": timeout, "winerror": getattr(error, "winerror", None),
                    "error_type": type(error).__name__, "owned_temporary_directory": True,
                }, indent=2) + "\n")
                raise
            time.sleep(min(0.1 * 2 ** min(attempts - 1, 4), 1.0, timeout - elapsed))
    (output / "portable-cleanup.json").write_text(json.dumps({
        "passed": True, "attempts": attempts,
        "elapsed_seconds": time.monotonic() - started, "timeout_seconds": timeout,
        "owned_temporary_directory": True,
    }, indent=2) + "\n")


@contextmanager
def portable_runtime(output):
    # delete=False evita un segundo borrado implícito fuera del control acotado.
    # cleanup() sigue siendo la API pública que trata archivos sólo de lectura.
    temporary = tempfile.TemporaryDirectory(prefix="PyAO portable con espacios ", delete=False)
    try:
        yield Path(temporary.name)
    finally:
        cleanup_owned(temporary, output)
