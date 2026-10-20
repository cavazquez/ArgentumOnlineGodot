"""Login y meditación visibles en dos Godot reales, sin exportar paquetes."""

from r10_world import R10World, prepare_fixture

REQUIRED = {"login-fx", "meditation"}


def acceptance(steps, _seconds, **_kwargs):
    missing = sorted(REQUIRED - {s["id"] for s in steps if s.get("passed")})
    return {"test_execution_passed": not missing, "missing": missing, "r10_gameplay_passed": False}


def login_effect_seen(view, actor):
    packet = any(
        p.get("kind") == "fx" and p.get("char_index") == actor
        and p.get("fx") == 1 and p.get("loops") == 1
        for p in view.get("fx_packets", [])
    )
    frames = {
        f["frame"] for f in view.get("fx_frames", [])
        if f.get("char_index") == actor and f.get("fx") == 1
        and f.get("visible") and f.get("playing")
    }
    return packet and len(frames) >= 2


class VisualSyncWorld(R10World):
    def run(self, locations):
        self.wait(
            lambda: all("INTEGRATION_WORLD: READY" in (self.output / f"godot-{i}.log").read_text() for i in (1, 2)),
            "alta de ambos clientes", 60,
        )
        with self.fixture.client() as store:
            self.ids = {i: int(store.hget(f"account:{self.names[i-1]}:data", "user_id")) for i in (1, 2)}
            x, y = locations["base"]
            self.data["skills"]["meditar"] = 100
            self.relocate(store, {1: (1, x, y), 2: (1, x+1, y)}, reset=True,
                          stats={1: {"min_mana": 1000}})
            for actor in (1, 2):
                self.command(actor, "logout")
                self.wait(lambda: not store.exists(f"session:{self.ids[actor]}:owner"), "liberar actor antes de login")
                for viewer in (1, 2):
                    self.command(viewer, "capture_reset", label=f"login-{actor}", actor=self.ids[actor])
                self.command(actor, "login")
                for viewer in (1, 2):
                    self.view(viewer, lambda v: login_effect_seen(v, self.ids[actor]),
                              f"efecto de login {actor} animado en cliente {viewer}")
                    self.view(viewer, lambda v: v.get("character_effects", {}).get(str(self.ids[actor]), {}).get("id") == 0,
                              f"efecto finito de login {actor} finalizado en cliente {viewer}")
                    self.command(viewer, "capture", label=f"login-{actor}-ended")
            self.passed("login-fx", "Login y reconexión con animación finita en ambos clientes",
                        actors=[1, 2], both_clients_animated=True, both_stopped=True)
            self.meditation(store, x, y, self.stats(store, 1)["min_mana"])
        for viewer in (1, 2): self.command(viewer, "soak")
        return self.steps
