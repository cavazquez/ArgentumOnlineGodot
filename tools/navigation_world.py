"""Regresión acotada y gráfica de barcos, pesca marina y navegación de interfaz."""

import time

from full_world import FullWorld, prepare_fixture


def acceptance(steps, seconds, **_):
    required = {"full-navigation", "full-sea-exit", "full-fishing-zones", "full-ui"}
    completed = {step["id"] for step in steps if step.get("passed")}
    return {
        "kind": "Navegación de dos clientes; no sustituye la campaña completa",
        "test_execution_passed": required <= completed,
        "missing": sorted(required - completed),
        "r10_gameplay_passed": False,
    }


class NavigationWorld(FullWorld):
    def run(self, locations):
        self.deadline = time.monotonic() + 900
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
            self.base = {1: (2, x, y), 2: (2, x, y + 2)}
            self.boats(store, locations)
            self.sea_exit(store, locations)
            self.ui_checks(store, x + 4, y)
            self.base = {1: (2, x + 4, y), 2: (2, x + 4, y + 2)}
            self.reset(store)
            for i in (1, 2):
                self.command(i, "soak")
        return self.steps
