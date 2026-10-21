"""Audita fuentes de atlas sin tiles sin modificar escenas ni celdas de mapas."""

import argparse
import json
from pathlib import Path
import re

ATLAS = re.compile(r'^\[sub_resource type="TileSetAtlasSource" id="([^"]+)"\]\n(.*?)(?=^\[|\Z)', re.M | re.S)
TILE = re.compile(r"^\d+:\d+/0\s*=", re.M)


def repair(text):
    empty = [match[1] for match in ATLAS.finditer(text) if not TILE.search(match[2])]
    for identity in empty:
        references = re.findall(r'^.*SubResource\("' + re.escape(identity) + r'"\).*$', text, re.M)
        if not references or any(not row.startswith("sources/") for row in references):
            raise ValueError("Referencia inesperada al atlas vacío " + identity)
    result = ATLAS.sub(lambda match: "" if match[1] in empty else match[0], text)
    for identity in empty:
        result = re.sub(r'^sources/\d+ = SubResource\("' + re.escape(identity) + r'"\)\n', "", result, flags=re.M)
    if empty:
        result = re.sub(r"load_steps=(\d+)", lambda match: "load_steps=" + str(int(match[1]) - len(empty)), result, count=1)
    return result, empty


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--maps", type=Path, default=Path(__file__).resolve().parents[1] / "Maps")
    args = parser.parse_args()
    changed = {}
    for path in sorted(args.maps.glob("Map*.tscn")):
        text = path.read_text(encoding="utf-8")
        corrected, identities = repair(text)
        if identities:
            changed[path.name] = identities
    print(json.dumps({"maps": len(list(args.maps.glob("Map*.tscn"))), "empty_atlases": changed}, indent=2))
    if changed:
        parser.exit(1, "Los mapas contienen atlas vacíos; revisar sus celdas con Godot antes de corregir.\n")


if __name__ == "__main__":
    main()
