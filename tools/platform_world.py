"""Prueba nativa corta del portable: los escenarios completos se ejecutan aparte."""

import json
import sys

from r10_world import R10World, prepare_fixture


def acceptance(steps, seconds, *, graphical, exported):
    done = {row["id"] for row in steps if row.get("passed") is True}
    passed = graphical and exported and {"platform-1", "platform-2"} <= done
    return {"test_execution_passed": passed, "functional_passed": passed}


class PlatformWorld(R10World):
    def run(self, locations):
        self.wait(lambda: all("INTEGRATION_WORLD: READY" in (self.output / f"godot-{i}.log").read_text() for i in (1, 2)), "dos clientes nativos", 90)
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
