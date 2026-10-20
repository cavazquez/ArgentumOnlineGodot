#!/usr/bin/env python3
"""Campaña completa de la tanda: ningún escenario ausente acredita la publicación."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def campaign(args):
    args.output.mkdir(parents=True, exist_ok=False)
    sources = {name: subprocess.check_output(["git", "-C", str(path), "rev-parse", "HEAD"], text=True).strip() for name, path in (("client", ROOT), ("server", args.server_project))}
    records = []
    for scenario, seconds in (("expansion", 20), ("npc-policy", 20), ("potions", 20), ("economy", 20), ("npcs", 20), ("full", 1800)):
        output = args.output / scenario
        command = [sys.executable, str(ROOT / "tools/integration-world.py"), "--scenario", scenario, "--seconds", str(seconds), "--server-project", str(args.server_project), "--godot", str(args.godot), "--client-executable", str(args.client_executable), "--output", str(output), "--wheel", str(args.wheel)]
        subprocess.run(command, check=True)
        result = json.loads((output / "result.json").read_text())
        if not result.get("passed", result.get("regression_passed")) or result.get("client_commit") != sources["client"] or result.get("server_commit") != sources["server"]:
            raise ValueError("Escenario fallido o de otros commits: " + scenario)
        records.append({"scenario": scenario, "sha256": hashlib.sha256((output / "result.json").read_bytes()).hexdigest(), "proof": str(output.relative_to(args.output) / "result.json")})
        (args.output / "campaign-progress.json").write_text(json.dumps({"complete": False, "sources": sources, "records": records}, indent=2) + "\n")
    (args.output / "campaign-50.json").write_text(json.dumps({"passed": True, "sources": sources, "records": records, "platform_distribution_proofs_required_separately": True}, indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("server-project", "godot", "client-executable", "wheel", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    for name in vars(args): setattr(args, name, getattr(args, name).resolve())
    campaign(args)
