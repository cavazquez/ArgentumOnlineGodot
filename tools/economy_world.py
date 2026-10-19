"""Regresión de economía y ventanas con dos Godot y Redis descartable propios."""

from decimal import Decimal
import time

from r10_world import R10World, acceptance as r10_acceptance, prepare_fixture

REQUIRED = {"economy-ui", "economy-offline-tax", "economy-stock-restart"}


def acceptance(steps, seconds, **kwargs):
    base = r10_acceptance(steps, seconds, **kwargs)
    done = {step["id"] for step in steps if step.get("passed")}
    missing = sorted(REQUIRED - done)
    return {
        **base,
        "economy_missing": missing,
        "test_execution_passed": base["functional_passed"] and not missing,
    }


class EconomyWorld(R10World):
    def open(self, index, topic):
        self.command(index, "close")
        self.command(index, "world_open", topic=topic)
        return self.view(index, lambda v: v.get("world_window") == topic and bool(v.get("world_window_state")), "ventana " + topic)

    def changed(self, index, condition, label):
        return self.view(index, lambda v: not v.get("world_pending", True) and condition(v.get("world_window_state", {})), label)

    def social_ui(self, store):
        for index in (1, 2):
            self.command(index, "chat", text="/SALIRPARTY")
        for index in (1, 2):
            self.open(index, "party")
            self.changed(index, lambda s: s.get("party_id") == 0, "grupo vacío confirmado")
        self.command(1, "world_action", topic="party", action="create")
        self.changed(1, lambda s: s.get("leader") == self.ids[1], "crear grupo desde su panel")
        self.command(1, "world_action", topic="party", action="invite", username=self.names[1])
        self.changed(2, lambda s: len(s.get("invitations", [])) == 1, "invitación de grupo visible")
        self.command(2, "world_action", topic="party", action="accept")
        self.changed(1, lambda s: len(s.get("members", [])) == 2, "dos miembros confirmados")
        self.command(1, "world_action", topic="party", action="leader", user=self.ids[2])
        state = self.changed(1, lambda s: s.get("leader") == self.ids[2], "transferir liderazgo desde el panel")
        assert "kick" not in state["world_window_state"]["permissions"]
        self.command(1, "capture", label="party")
        for index in (1, 2):
            self.command(index, "world_action", topic="party", action="leave")
            self.changed(index, lambda s: s.get("party_id") == 0, "salir de grupo confirmado")
        for index in (1, 2):
            self.command(index, "close")
            self.command(index, "chat", text="/SALIRCLAN")
            self.open(index, "clan")
        current = self.command(1, "snapshot")["world_window_state"]
        if current["clan_id"] == 0:
            self.command(1, "world_action", topic="clan", action="create", name="Economy" + str(self.ids[1]))
        self.changed(1, lambda s: s.get("leader") == self.ids[1], "crear clan desde el panel")
        self.command(1, "world_action", topic="clan", action="invite", username=self.names[1])
        self.changed(2, lambda s: bool(s.get("invitation")), "invitación de clan visible")
        self.command(2, "world_action", topic="clan", action="accept")
        self.changed(1, lambda s: len(s.get("members", [])) == 2, "roster de clan confirmado")
        for action, rank in (("promote", 2), ("demote", 1)):
            self.command(1, "world_action", topic="clan", action=action, user=self.ids[2])
            self.changed(1, lambda s: any(m["id"] == self.ids[2] and m["rank"] == rank for m in s.get("members", [])), "rango confirmado: " + action)
        self.command(1, "world_action", topic="clan", action="transfer", user=self.ids[2])
        self.changed(1, lambda s: s.get("leader") == self.ids[2] and "transfer" not in s.get("permissions", []), "liderazgo de clan y permisos nuevos")
        self.command(1, "capture", label="clan")
        self.command(1, "world_action", topic="clan", action="leave")
        self.changed(1, lambda s: s.get("clan_id") == 0, "salida de clan confirmada")
        self.changed(2, lambda s: len(s.get("members", [])) == 1 and "leave" not in s.get("permissions", []), "el líder conserva la regla de transferir antes de salir")
        for index in (1, 2): self.command(index, "close")
        self.passed("economy-ui", "Grupo y clan por UI", create=True, invite_accept=True, ranks=True, leadership=True, leave=True)

    def fiscal_and_stock(self, store, locations):
        day = int(time.time()) // 86400
        user = self.ids[1]
        self.command(1, "logout")
        self.wait(lambda: not store.exists(f"session:{user}:owner"), "liberar sesión fiscal")
        store.hset("config:economy:daily_tax", "activation_day", day - 90)
        store.hset(f"player:{user}:user_stats", "gold", 1000)
        store.set(f"bank:{user}:gold", 2000)
        store.hset(f"tax:{user}:state", mapping={"version": 1, "last_day": day-90, "remainder": 0, "total_paid": 0, "last_receipt": "", "last_charge": 0})
        total, fractional = 3000, Decimal(0)
        for _ in range(90):
            amount = Decimal(total) / 100 + fractional
            charge = int(amount)
            fractional = amount - charge
            total -= charge
        self.command(1, "login")
        self.open(1, "tax")
        view = self.changed(1, lambda s: s.get("wallet", 0) + s.get("bank", 0) == total and s.get("last_day") == day, "90 días offline en el panel fiscal")
        status = view["world_window_state"]
        self.command(1, "capture", label="tax")
        assert view["gold"] == status["wallet"]
        assert status["total_paid"] == 3000-total
        assert status["rate_bps"] == 100 and status["scope"] == "wallet_and_bank"
        paid = store.hget(f"tax:{user}:state", "total_paid")
        self.open(1, "tax")
        self.open(1, "tax")
        assert store.hget(f"tax:{user}:state", "total_paid") == paid
        self.passed("economy-offline-tax", "1% diario", days=90, initial_total=3000, final_total=total, rereads_do_not_charge=True)
        self.command(1, "close")
        x, y = locations["base"]
        self.bank(store, x, y)
        assert store.hget(f"tax:{user}:state", "total_paid") == paid
        self.command(1, "click", x=x, y=y-2, double=True)
        self.view(1, lambda v: v["panel"] == "merchant", "mercader con stock persistido")
        count = self.count(store, 1, 15)
        self.command(1, "merchant", buy=True, slot=1, amount=1)
        self.wait(lambda: self.count(store, 1, 15) == count+1, "compra con cargo fiscal ya liquidado")
        self.command(1, "close")
        keys = ["merchant:7:inventory", "merchant:7:catalog"]
        before = {key: store.hgetall(key) for key in keys}
        assert all(before.values())
        for index in (1, 2): self.command(index, "logout")
        self.wait(lambda: not any(store.exists(f"session:{uid}:owner") for uid in self.ids.values()), "liberar clientes antes de reinicio")
        self.server = self.restart_server()
        assert {key: store.hgetall(key) for key in keys} == before
        for index in (1, 2):
            self.command(index, "login")
            self.view(index, lambda v: bool(v.get("world_states", {}).get("tax")), "reconexión con estado fiscal")
        assert store.hget(f"tax:{user}:state", "total_paid") == paid
        self.passed("economy-stock-restart", "Redis autoritativo", stock_preserved=True, catalog_preserved=True, tax_not_repeated=True)

    def run(self, locations):
        super().run(locations, soak=False)
        self.deadline = time.monotonic() + 600
        with self.fixture.client() as store:
            self.social_ui(store)
            self.fiscal_and_stock(store, locations)
        for index in (1, 2): self.command(index, "soak")
        return self.steps


def ui_acceptance(steps, _seconds, **_kwargs):
    missing = sorted(REQUIRED - {s["id"] for s in steps if s.get("passed")})
    return {"kind": "Economía y ventanas, sin repetir campaña R10", "test_execution_passed": not missing, "economy_missing": missing, "r10_gameplay_passed": False}


class EconomyUIWorld(EconomyWorld):
    def run(self, locations):
        self.wait(lambda: all("INTEGRATION_WORLD: READY" in (self.output / f"godot-{i}.log").read_text() for i in (1, 2)), "alta de dos clientes", 60)
        with self.fixture.client() as store:
            self.ids = {i: int(store.hget(f"account:{self.names[i-1]}:data", "user_id")) for i in (1, 2)}
            x, y = locations["base"]
            self.relocate(store, {1: (1, x, y), 2: (1, x+1, y)}, reset=True)
            self.social_ui(store)
            self.fiscal_and_stock(store, locations)
        for index in (1, 2): self.command(index, "soak")
        return self.steps
