"""Recoge fotos del temporizador nativo sin usar el controlador ya finalizado."""

import hashlib
from pathlib import Path
import re

NAME = re.compile(r"godot-([12])-([0-9]{4,})s\.png")
PNG_START = b"\x89PNG\r\n\x1a\n"
PNG_END = b"\x00\x00\x00\x00IEND\xaeB`\x82"


def ensure_fresh_captures(output: Path) -> None:
    if any(NAME.fullmatch(path.name) for path in output.glob("godot-*-*s.png")):
        raise ValueError("La aceptación prolongada requiere una salida sin capturas anteriores")


def collect_native_captures(output: Path, previous: list[dict]) -> list[dict]:
    records = {row["file"]: row for row in previous}
    observed = set()
    for path in sorted(output.glob("godot-*-*s.png")):
        match = NAME.fullmatch(path.name)
        if match is None:
            continue
        if path.is_symlink():
            raise ValueError("Una captura nativa no puede ser un enlace")
        data = path.read_bytes()
        complete = data.startswith(PNG_START) and data.endswith(PNG_END)
        if not complete:
            if path.name in records:
                raise ValueError("Una captura completa fue alterada")
            continue  # Godot todavía puede estar escribiendo el PNG.
        elapsed = int(match[2])
        if elapsed < 300:
            raise ValueError("Tiempo inválido de una captura periódica nativa")
        digest = hashlib.sha256(data).hexdigest()
        if path.name in records and records[path.name]["sha256"] != digest:
            raise ValueError("Una captura completa fue alterada")
        observed.add(path.name)
        records[path.name] = {
            "client": int(match[1]), "minute": round(elapsed / 60, 2),
            "elapsed_seconds": elapsed, "file": path.name, "sha256": digest,
            "source": "native-timer",
        }
    if set(records) - observed:
        raise ValueError("Desapareció una captura previamente recogida")
    return sorted(records.values(), key=lambda row: (row["elapsed_seconds"], row["client"]))


def require_native_captures(records: list[dict], duration: int) -> None:
    expected = (duration - 1) // 300
    for client in (1, 2):
        count = sum(row["client"] == client for row in records)
        if count < expected:
            raise RuntimeError(f"Godot {client} no acredita sus {expected} capturas periódicas")
