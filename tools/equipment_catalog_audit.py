"""Audita todo el catálogo contra las animaciones del avatar, sin contar iconos."""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import tomllib

LAYERS = {
    2: ("weapon", "Weapons", "weapon", "Anim"),
    3: ("armor", "Bodies", "body", "NumRopaje"),
    16: ("shield", "Shields", "shield", "Anim"),
    17: ("helmet", "Helmets", "helmet", "Anim"),
}


def audit(server, client):
    items = {}
    hashes = {}
    for path in sorted((server / "data/items").rglob("*.toml")):
        hashes[str(path.relative_to(server))] = hashlib.sha256(
            path.read_bytes()
        ).hexdigest()
        for row in tomllib.loads(path.read_text()).get("item", []):
            items[row["id"]] = row
    counts, rows, missing, unsupported = Counter(), [], [], []
    for item_id, item in sorted(items.items()):
        kind = item.get("ObjType")
        if kind not in LAYERS:
            if kind == 18 or "botas" in item.get("Name", "").lower():
                unsupported.append(
                    {
                        "item_id": item_id,
                        "name": item["Name"],
                        "obj_type": kind,
                        "reason": "no_equipment_slot_or_avatar_layer",
                    }
                )
            continue
        slot, folder, prefix, field = LAYERS[kind]
        counts[slot] += 1
        variants = [("normal", int(item.get(field, 0)))]
        if kind == 2 and item.get("RazaEnanaAnim"):
            variants.append(("small_race", int(item["RazaEnanaAnim"])))
        for variant, graphic in variants:
            relative = f"Resources/Character/{folder}/{prefix}_{graphic}.tres"
            exists = graphic > 0 and (client / relative).is_file()
            row = {
                "item_id": item_id,
                "name": item["Name"],
                "slot": slot,
                "variant": variant,
                "animation": graphic,
                "resource": relative,
                "resource_exists": exists,
            }
            rows.append(row)
            if not exists:
                missing.append(row)
    return {
        "catalogue_files_sha256": hashes,
        "items_by_slot": dict(counts),
        "animation_references": len(rows),
        "rows": rows,
        "missing_resources": missing,
        "unsupported_equipment": unsupported,
        "complete_avatar_coverage": not missing and not unsupported,
        "missing_resource_issue": "https://github.com/cavazquez/ArgentumOnlineGodot/issues/180",
        "boots_issue": "https://github.com/cavazquez/ArgentumOnlineGodot/issues/181",
        "rings_issue": "https://github.com/cavazquez/pyao-server/issues/367",
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server-project", type=Path, required=True)
    parser.add_argument(
        "--client-project", type=Path, default=Path(__file__).resolve().parents[1]
    )
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = audit(args.server_project, args.client_project)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(
        json.dumps(
            {
                key: report[key]
                for key in (
                    "items_by_slot",
                    "animation_references",
                    "complete_avatar_coverage",
                )
            }
        )
    )
