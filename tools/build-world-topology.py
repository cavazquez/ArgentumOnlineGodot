#!/usr/bin/env python3
"""Genera enlaces y una disposición del mundo desde las salidas propias de PyAO."""

import argparse
from collections import deque
import hashlib
import json
from pathlib import Path
import tomllib


def build(source, scene_dir, metadata):
    maps = {
        int(p.stem.removeprefix("Map"))
        for p in scene_dir.glob("Map*.tscn")
        if p.stem.removeprefix("Map").isdigit()
    }
    names = {}
    if metadata and metadata.exists():
        names = {
            int(k.removeprefix("map_")): v.get("name", k)
            for k, v in tomllib.loads(metadata.read_text()).items()
        }
    grouped = {}
    errors = []
    sources = {}
    for path in sorted(source.glob("transitions_*.json")):
        sources[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
        for line in path.read_text().splitlines():
            if not line.strip():
                continue
            row = json.loads(line)
            a = int(row["from_map"])
            if a not in maps:
                continue
            for e in row.get("exits", []):
                b = int(e["to_map"])
                x, y, tx, ty = (int(e[k]) for k in ("x", "y", "to_x", "to_y"))
                if b not in maps or any(not 1 <= n <= 100 for n in (x, y, tx, ty)):
                    errors.append(
                        {"from": a, "to": b, "reason": "mapa o coordenada ausente"}
                    )
                    continue
                dx = -1 if x <= 9 and tx >= 92 else 1 if x >= 92 and tx <= 9 else 0
                dy = -1 if y <= 9 and ty >= 92 else 1 if y >= 92 and ty <= 9 else 0
                kind = (
                    "diagonal" if dx and dy else "cardinal" if dx or dy else "teleport"
                )
                key = (a, b, kind, dx, dy)
                edge = grouped.setdefault(
                    key,
                    {
                        "from": a,
                        "to": b,
                        "kind": kind,
                        "direction": [dx, dy],
                        "exits": [],
                    },
                )
                edge["exits"].append([x, y, tx, ty])
    edges = sorted(grouped.values(), key=lambda e: (e["from"], e["to"], e["kind"]))
    pairs = {(e["from"], e["to"], e["kind"]) for e in edges}
    for e in edges:
        e["reciprocal"] = (e["to"], e["from"], e["kind"]) in pairs
    positions = {}
    conflicts = []
    component = 0
    for seed in sorted(maps):
        if seed in positions:
            continue
        local = {seed: (0, 0)}
        occupied = {(0, 0): seed}
        queue = deque([seed])
        while queue:
            a = queue.popleft()
            for e in edges:
                if e["from"] != a or not e["reciprocal"] or e["kind"] == "teleport":
                    continue
                b = e["to"]
                dx, dy = e["direction"]
                desired = (local[a][0] + dx, local[a][1] + dy)
                if b in local:
                    if local[b] != desired:
                        conflicts.append(
                            {
                                "from": a,
                                "to": b,
                                "reason": "ciclo geográfico contradictorio",
                            }
                        )
                    continue
                if desired in occupied:
                    conflicts.append(
                        {"from": a, "to": b, "reason": "posición geográfica ocupada"}
                    )
                    continue
                local[b] = desired
                occupied[desired] = b
                queue.append(b)
        minx = min(x for x, y in local.values())
        miny = min(y for x, y in local.values())
        width = max(x for x, y in local.values()) - minx + 1
        for key, (x, y) in local.items():
            positions[key] = [x - minx + component, y - miny]
        component += width + 3
    return {
        "version": 1,
        "sources": sources,
        "maps": {
            str(i): {"name": names.get(i, f"Mapa {i}"), "position": positions[i]}
            for i in sorted(maps)
        },
        "edges": edges,
        "errors": errors,
        "layout_conflicts": conflicts,
    }


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--source", type=Path, required=True)
    p.add_argument("--scenes", type=Path, default=Path("Maps"))
    p.add_argument("--metadata", type=Path)
    p.add_argument("--output", type=Path, default=Path("protocol/world-topology.json"))
    a = p.parse_args()
    data = build(a.source, a.scenes, a.metadata)
    a.output.write_text(
        json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n"
    )
    print(
        json.dumps(
            {
                "maps": len(data["maps"]),
                "edges": len(data["edges"]),
                "invalid": len(data["errors"]),
                "layout_conflicts": len(data["layout_conflicts"]),
            }
        )
    )
    if data["errors"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
