"""Prueba nativa corta del portable: los escenarios completos se ejecutan aparte."""

import json

from r10_world import R10World, prepare_fixture


def acceptance(steps, seconds, *, graphical, exported):
    done = {row["id"] for row in steps if row.get("passed") is True}
    passed = graphical and exported and {"platform-1", "platform-2"} <= done
    return {"test_execution_passed": passed, "functional_passed": passed}


class PlatformWorld(R10World):
    def run(self, locations):
        self.wait(lambda: all("INTEGRATION_WORLD: READY" in (self.output / f"godot-{i}.log").read_text() for i in (1, 2)), "dos clientes nativos", 90)
        for index in (1, 2):
            view = self.command(index, "platform_probe")
            probe = view.get("platform_probe", {})
            if not all(probe.get(key) is True for key in ("rendering", "audio", "input", "preferences")):
                raise RuntimeError("Portable incompleto: " + json.dumps(probe))
            self.command(index, "screenshot", path=str(self.output / f"platform-{index}.png"))
            self.passed(f"platform-{index}", "Renderizado, audio, controles y preferencias nativos", **probe)
        for index in (1, 2): self.command(index, "soak")
        return self.steps
