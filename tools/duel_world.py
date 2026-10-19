"""Duelo gráfico reproducible con muerte PvP y resurrección por el compañero."""

import time

from full_world import FullWorld
from skills_world import prepare_fixture


def acceptance(steps, seconds, **_):
    passed = any(
        step.get("passed") is True
        and step["id"] == "full-pvp"
        and step.get("observations", {}).get("death_and_revive") is True
        for step in steps
    )
    return {
        "kind": "Duelo de dos clientes; no sustituye la campaña completa",
        "test_execution_passed": passed,
        "death_and_revive": passed,
        "r10_gameplay_passed": False,
    }


class DuelWorld(FullWorld):
    def run(self, locations):
        self.deadline = time.monotonic() + 600
        self.wait(
            lambda: all(
                "INTEGRATION_WORLD: READY"
                in (self.output / f"godot-{i}.log").read_text()
                for i in (1, 2)
            ),
            "dos clientes gráficos",
            60,
        )
        with self.fixture.client() as store:
            self.ids = {
                i: int(store.hget(f"account:{self.names[i - 1]}:data", "user_id"))
                for i in (1, 2)
            }
            _, x, y = locations["skills_base"]
            self.base = {1: (2, x + 4, y), 2: (2, x + 4, y + 2)}
            self.pvp_both(store, x + 4, y)
            self.reset(store)
            for i in (1, 2):
                self.command(i, "soak")
        return self.steps
