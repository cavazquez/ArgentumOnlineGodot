"""Prueba nativa corta del portable: los escenarios completos se ejecutan aparte."""

import json
import platform
import sys
import time

from r10_world import R10World, prepare_fixture


def acceptance(steps, seconds, *, graphical, exported):
    done = {row["id"] for row in steps if row.get("passed") is True}
    passed = graphical and exported and {"platform-1", "platform-2"} <= done
    return {"test_execution_passed": passed, "functional_passed": passed}


class PlatformWorld(R10World):
    def wait_for_ready(self):
        # Son dos arranques fríos, altas y primeros frames; no el login del producto.
        budget = 180 if sys.platform == "darwin" and platform.machine() == "x86_64" else 90
        started = time.monotonic()
        ready_seconds = {}
        passed = False

        def both_ready():
            for index in (1, 2):
                if index not in ready_seconds and "INTEGRATION_WORLD: READY" in (self.output / f"godot-{index}.log").read_text():
                    ready_seconds[index] = round(time.monotonic() - started, 3)
            return len(ready_seconds) == 2

        try:
            self.wait(both_ready, "dos clientes nativos", budget)
            passed = True
        finally:
            proof = {
                "passed": passed,
                "platform": sys.platform,
                "architecture": platform.machine(),
                "startup_budget_seconds": budget,
                "elapsed_seconds": round(time.monotonic() - started, 3),
                "ready_seconds": ready_seconds,
                "login_budget_changed": False,
            }
            pending = self.output / "platform-readiness.pending"
            pending.write_text(json.dumps(proof, indent=2) + "\n")
            pending.replace(self.output / "platform-readiness.json")

    def run(self, locations):
        self.wait_for_ready()
        for index in (1, 2):
            if sys.platform == "win32":
                # Como al alternar con Alt-Tab: sólo un cliente posee el foco
                # nativo. El otro conserva su sesión y su loop de red activos.
                self.command(3 - index, "native_window", action="minimize")
                self.command(index, "native_window", action="restore")
            # Esta operación abre ventanas y prueba teclado, preferencias y audio.
            # El renderer software del runner macOS Intel puede trabajar a 1 FPS.
            # Su plazo es independiente del login y de los demás comandos (40 s).
            view = self.command(index, "platform_probe", response_timeout=90)
            probe = view.get("platform_probe", {})
            if not all(probe.get(key) is True for key in ("rendering", "audio", "input", "preferences")):
                raise RuntimeError("Portable incompleto: " + json.dumps(probe))
            self.command(index, "screenshot", path=str(self.output / f"platform-{index}.png"))
            self.passed(f"platform-{index}", "Renderizado, audio, controles y preferencias nativos", **probe)
        for index in (1, 2):
            if sys.platform == "win32": self.command(index, "native_window", action="restore")
            self.command(index, "soak")
        return self.steps
