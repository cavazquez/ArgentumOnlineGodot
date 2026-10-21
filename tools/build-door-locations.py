"""Extrae sólo las ubicaciones de puertas que reciben snapshots dinámicos."""

import argparse
import hashlib
import json
from pathlib import Path
import tomllib


def build(server):
    cells, hashes = {}, {}
    for path in sorted((server / "map_data").glob("objects_*.json")):
        hashes[str(path.relative_to(server))] = hashlib.sha256(path.read_bytes()).hexdigest()
        for line in path.read_text().splitlines():
            row = json.loads(line)
            if row.get("t") == "door": cells.setdefault(row["m"], set()).add((row["x"], row["y"]))
    path = server / "data/world/map_doors.toml"
    hashes[str(path.relative_to(server))] = hashlib.sha256(path.read_bytes()).hexdigest()
    for row in tomllib.loads(path.read_text()).get("door", []):
        cells.setdefault(row["map_id"], set()).add((row["x"], row["y"]))
    catalog = server / "data/items/world_objects/doors.toml"
    hashes[str(catalog.relative_to(server))] = hashlib.sha256(catalog.read_bytes()).hexdigest()
    graphics = sorted({r["GrhIndex"] for r in tomllib.loads(catalog.read_text()).get("item", []) if r.get("ObjType") == 6 and r.get("Llave", 0) != 1})
    return {"graphics": graphics, "sources": hashes, "maps": {str(mid): sorted(values) for mid, values in sorted(cells.items())}}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path("protocol/door-locations.json"))
    args = parser.parse_args()
    args.output.write_text(json.dumps(build(args.server), indent=2) + "\n")
