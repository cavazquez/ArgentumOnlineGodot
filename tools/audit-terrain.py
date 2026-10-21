"""Contrasta todas las celdas renderizadas con el terreno estático del servidor."""

import argparse
import base64
import hashlib
import json
from pathlib import Path

BLOCKED, WATER = 1, 4  # Enums.TileState; Roof occupies bit 1.


def inspect(source, rendered):
    maps, sources = {}, {}
    for path in sorted(source.glob("metadata_*.json")):
        sources[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
        for line in path.read_text().splitlines():
            if line.strip(): maps[json.loads(line)["i"]] = bytearray(10000)
    for prefix, kinds in (("blocked", {"b": BLOCKED, "t": BLOCKED, "m": BLOCKED, "w": BLOCKED | WATER}), ("objects", {"tree": BLOCKED, "mine": BLOCKED, "anvil": BLOCKED, "forge": BLOCKED, "water": WATER})):
        for path in sorted(source.glob(prefix + "_*.json")):
            sources[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
            for line in path.read_text().splitlines():
                if not line.strip(): continue
                row = json.loads(line)
                value = kinds.get(row.get("t"), 0)
                if not value: continue
                mid, x, y = row["m"], row["x"], row["y"]
                if mid not in maps or not 1 <= x <= 100 or not 1 <= y <= 100:
                    raise ValueError("Coordenada de terreno inválida")
                maps[mid][x-1+(y-1)*100] |= value
    proof = json.loads(rendered.read_text())
    if {str(mid) for mid in maps} != set(proof["maps"]):
        raise ValueError("El render no contiene exactamente los mapas del servidor")
    differences, water_errors, solid_errors = [], 0, 0
    for mid, server in sorted(maps.items()):
        client = base64.b64decode(proof["maps"][str(mid)]["flags"], validate=True)
        if len(client) != 10000: raise ValueError("Faltan celdas renderizadas")
        for index, (a, b) in enumerate(zip(server, client)):
            water = bool(a & WATER) != bool(b & WATER)
            solid = bool(a & BLOCKED and not a & WATER) != bool(b & BLOCKED and not b & WATER)
            if water or solid:
                differences.append({"map": mid, "x": index%100+1, "y": index//100+1, "server": a, "client": b})
                water_errors += water
                solid_errors += solid
    return {"passed": not differences, "maps_compared": len(maps), "tiles_compared": len(maps)*10000, "water_mismatches": water_errors, "solid_mismatches": solid_errors, "differences": differences, "sources": sources, "rendered_sha256": hashlib.sha256(rendered.read_bytes()).hexdigest(), "scope": "Static masks only. Door/workshop overlays are verified separately through the network; water is not counted as a solid wall."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--rendered", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = inspect(args.source, args.rendered)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({key: result[key] for key in ("passed", "maps_compared", "tiles_compared", "water_mismatches", "solid_mismatches")}))
    if not result["passed"]: raise SystemExit(1)
