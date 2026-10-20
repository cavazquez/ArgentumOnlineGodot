"""Profile actual TLS gameplay and tick distributions without a capacity claim."""

import json
import threading
import time

from full_world import FullWorld, prepare_fixture
from structure_profile_matrix import run_matrix


def acceptance(steps, seconds, **_):
    passed = any(
        s.get("passed") is True and s.get("id") == "structure-profile" for s in steps
    )
    return {
        "kind": "Profile with two real clients and one slow reader",
        "test_execution_passed": passed,
        "r10_gameplay_passed": False,
    }


def percentiles(values):
    values = sorted(values)
    return (
        {
            name: values[min(len(values) - 1, int(len(values) * fraction))]
            for name, fraction in (("p50", 0.5), ("p95", 0.95), ("p99", 0.99))
        }
        if values
        else {}
    )


class StructureProfileWorld(FullWorld):
    def run(self, locations):
        self.deadline = time.monotonic() + 900
        self.wait(
            lambda: all(
                "INTEGRATION_WORLD: READY"
                in (self.output / f"godot-{i}.log").read_text()
                for i in (1, 2)
            ),
            "two graphical clients",
            60,
        )
        done = threading.Event()
        samples, gaps, intervals = [], [], []

        def collect():
            previous = None
            while not done.wait(0.01):
                path = self.output / "server-ticks.json"
                if not path.exists():
                    continue
                try:
                    current = json.loads(path.read_text())
                except (OSError, ValueError):
                    continue
                if (
                    previous
                    and current["total_ticks"] == previous[0]["total_ticks"] + 1
                ):
                    samples.append(
                        current["total_time_ms"] - previous[0]["total_time_ms"]
                    )
                    intervals.append((time.monotonic() - previous[1]) * 1000)
                elif (
                    previous and current["total_ticks"] > previous[0]["total_ticks"] + 1
                ):
                    gaps.append(current["total_ticks"] - previous[0]["total_ticks"])
                if (
                    previous is None
                    or current["total_ticks"] != previous[0]["total_ticks"]
                ):
                    previous = current, time.monotonic()

        thread = threading.Thread(
            target=collect, name="fixture-tick-sampler", daemon=True
        )
        thread.start()
        try:
            with self.fixture.client() as store:
                self.ids = {
                    i: int(store.hget(f"account:{self.names[i - 1]}:data", "user_id"))
                    for i in (1, 2)
                }
                _, x, y = locations["skills_base"]
                run_matrix(self, store, x, y)
                frames = {
                    i: self.command(i, "performance_probe")["platform_probe"][
                        "performance"
                    ]
                    for i in (1, 2)
                }
                assert len(samples) >= 10
                result = {
                    "tick_elapsed_ms": percentiles(samples),
                    "tick_measurement": "Elapsed wall time includes Redis waits, not isolated CPU",
                    "tick_publication_interval_ms": percentiles(intervals),
                    "tick_samples": len(samples),
                    "missed_tick_groups": gaps,
                    "interval_poll_resolution_ms": 10,
                    "clients": frames,
                    "not_a_production_capacity_result": True,
                }
                (self.output / "structure-profile.json").write_text(
                    json.dumps(result, indent=2) + "\n"
                )
                self.passed("structure-profile", **result)
                for i in (1, 2):
                    self.command(i, "close_mechanics")
                    self.command(i, "soak")
        finally:
            done.set()
            thread.join(timeout=2)
        return self.steps
