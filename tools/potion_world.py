"""Verificación acotada: las acciones se ejecutan mediante dos Godot reales."""
import asyncio
import json
import time

from r10_world import R10World, prepare_fixture

REQUIRED = {"cure-poison", "hp", "mana", "agility", "strength", "resource-caps", "black-invisibility"}


def acceptance(steps, seconds, *, graphical, **_):
    inspected = {step["id"] for step in steps if step.get("passed")}
    return {
        "test_execution_passed": REQUIRED <= inspected and graphical,
        "diagnostic_only": False,
        "all_potions_work_correctly": REQUIRED <= inspected and all(step["observations"].get("mechanic_ok", False) for step in steps),
        "r10_gameplay_passed": False,
        "inspected": sorted(inspected),
    }


class PotionWorld(R10World):
    def record(self, key, label, **values):
        self.passed(key, label, **values)
        (self.output / "potions.json").write_text(json.dumps(self.steps, indent=2) + "\n")

    def setup(self, store, locations):
        for index in (1, 2):
            self.command(index, "logout")
            self.wait(lambda: not store.exists(f"session:{self.ids[index]}:owner"), "liberar sesión")
        x, y = locations["base"]
        inventory = {1: (38, 5), 2: (37, 5), 3: (36, 3), 4: (39, 3), 5: (166, 2), 6: (645, 2), 30: (1, 10)}
        for index in (1, 2):
            uid = self.ids[index]
            store.hset(f"player:{uid}:position", mapping={"map": 1, "x": x + index - 1, "y": y, "heading": 1})
            store.hset(f"player:{uid}:user_stats", mapping={**self.data["player"], "poisoned_until": str(time.time() + 300) if index == 1 else "0", "invisible_until": "0"})
            store.hset(f"player:{uid}:stats", mapping={"strength": 20, "agility": 20, "intelligence": 30,
                "strength_modifier_until": 0, "strength_modifier_value": 0,
                "agility_modifier_until": 0, "agility_modifier_value": 0})
            store.delete(f"player:{uid}:inventory", f"player:{uid}:equipment")
            store.hset(f"player:{uid}:inventory", mapping={f"slot_{s}": f"{i}:{q}" for s, (i, q) in inventory.items()})
            self.command(index, "login")
            self.view(index, lambda v: v.get("name") == self.names[index - 1] and v.get("x") == x + index - 1 and v.get("y") == y, "posición inicial de pociones")

    def use(self, store, slot, item):
        before = self.count(store, 1, item)
        started = time.time()
        self.command(1, "use", slot=slot)
        self.wait(lambda: self.count(store, 1, item) == before - 1, "consumir exactamente una poción")
        view = self.view(1, lambda v: v["items"].get(str(slot), [0, 0])[1] == before - 1, "inventario visible actualizado")
        return started, view

    def attributes(self):
        """Consulta el repositorio real sobre el Redis propiedad de este ensayo."""
        async def read():
            from redis.asyncio import Redis
            from src.repositories.player_repository import PlayerRepository
            class Adapter:
                async def hgetall(self, key):
                    return await connection.hgetall(key)
                async def hget(self, key, field):
                    return await connection.hget(key, field)
            async with Redis(host="127.0.0.1", port=self.fixture.port,
                             password=self.fixture.password_file.read_text().strip(), decode_responses=True) as connection:
                attrs = await PlayerRepository(Adapter()).get_player_attributes(self.ids[1])
                return attrs.to_dict()
        return asyncio.run(read())

    def attribute_potion(self, store, slot, item, name, minimum, maximum):
        key = f"player:{self.ids[1]}:stats"
        self.command(1, "stats_open")
        before = self.view(1, lambda v: "attributes" in v, "ventana de atributos abierta")
        started, view = self.use(store, slot, item)
        until = float(store.hget(key, f"{name}_modifier_until"))
        modifier = int(store.hget(key, f"{name}_modifier_value"))
        effective = self.attributes()
        assert minimum <= modifier <= maximum
        assert effective[name] == 20 + modifier, (effective, modifier)
        assert 39 <= until - started <= 42, (until, started)
        label = "Agilidad" if name == "agility" else "Fuerza"
        during = self.view(1, lambda v: v.get("attributes", {}).get(label) == str(20 + modifier), "atributo visible durante el efecto")
        # Espera real, sin cambiar el reloj ni el estado del servidor.
        self.wait(lambda: time.time() > until + 1.2, "vencimiento real del modificador", 45)
        expired = self.attributes()
        after = self.view(1, lambda v: v.get("attributes", {}).get(label) == "20", "atributo visible al vencer")
        assert expired[name] == 20
        self.command(1, "capture", label=f"{name}-expired")
        self.record("agility" if name == "agility" else "strength", "Uso, atributos efectivos y vencimiento real", item=item,
            modifier=modifier, configured_duration_seconds=40.0, expiry_minus_click_start_seconds=round(until - started, 3),
            effective_during=effective, effective_after_expiry=expired,
            labels_before=before.get("attributes"), labels_during=view.get("attributes"), labels_after_expiry=after.get("attributes"),
            mechanic_ok=True, finding=None)
        self.command(1, "close_mechanics")

    def run(self, locations):
        self.deadline = time.monotonic() + 900
        self.wait(lambda: all("INTEGRATION_WORLD: READY" in (self.output / f"godot-{i}.log").read_text() for i in (1, 2)), "dos clientes listos", 90)
        with self.fixture.client() as store:
            self.ids = {i: int(store.hget(f"account:{self.names[i - 1]}:data", "user_id")) for i in (1, 2)}
            self.setup(store, locations)
            key = f"player:{self.ids[1]}:user_stats"
            assert float(store.hget(key, "poisoned_until")) > time.time()
            self.use(store, 5, 166)
            self.wait(lambda: float(store.hget(key, "poisoned_until")) == 0, "veneno curado")
            self.console(1, "Te has curado del envenenamiento")
            self.record("cure-poison", "Violeta elimina veneno activo y actualiza inventario", item=166, mechanic_ok=True)
            for slot, item, resource, minimum, maximum in ((1, 38, "hp", 30, 30), (2, 37, "mana", 12, 20)):
                before = int(store.hget(key, f"min_{resource}"))
                self.use(store, slot, item)
                after = int(store.hget(key, f"min_{resource}"))
                assert minimum <= after - before <= maximum, (resource, before, after)
                view = self.view(1, lambda v: v[resource] == after, f"barra de {resource} actualizada")
                self.record(resource, "Restaura recurso en Redis y en la barra del cliente", item=item, before=before, after=after, visible=view[resource], mechanic_ok=True)
            for slot, item, name, lo, hi in ((3, 36, "agility", 3, 5), (4, 39, "strength", 2, 6)):
                self.attribute_potion(store, slot, item, name, lo, hi)
            # Fixture de topes preparada con el personaje desconectado.
            self.command(1, "logout")
            self.wait(lambda: not store.exists(f"session:{self.ids[1]}:owner"), "liberar sesión para topes")
            store.hset(key, mapping={"min_hp": 1999, "max_hp": 2000, "min_mana": 4999, "max_mana": 5000})
            self.command(1, "login")
            for slot, item, resource, cap in ((1, 38, "hp", 2000), (2, 37, "mana", 5000)):
                self.use(store, slot, item)
                assert int(store.hget(key, f"min_{resource}")) == cap
                self.view(1, lambda v: v[resource] == cap, "tope visible del recurso")
            self.record("resource-caps", "Roja y azul respetan máximos", hp=2000, mana=5000, mechanic_ok=True)
            owner = str(self.ids[1])
            self.view(2, lambda v: owner in v.get("actor_visibility", {}), "segundo cliente ve al personaje")
            started, _ = self.use(store, 6, 645)
            until = float(store.hget(key, "invisible_until"))
            self.console(1, "Te has vuelto invisible")
            self.wait(lambda: time.time() > started + 1.4, "publicación de visibilidad", 3)
            hidden = {i: self.command(i, "snapshot") for i in (1, 2)}
            for i in (1, 2):
                self.command(i, "capture", label="black-active")
            assert 298 <= until - started <= 302
            assert owner in hidden[2].get("actor_visibility", {})
            assert hidden[2]["actor_visibility"][owner]["internal_invisible"] is True
            self.wait(lambda: time.time() > until + 1.3, "vencimiento real de la poción negra", 310)
            expired = {i: self.command(i, "snapshot") for i in (1, 2)}
            for i in (1, 2):
                self.command(i, "capture", label="black-expired")
            observer_restored = owner in expired[2].get("actor_visibility", {}) and expired[2]["actor_visibility"][owner]["internal_invisible"] is False
            assert observer_restored, expired[2].get("actor_visibility", {})
            self.record("black-invisibility", "Poción negra observada desde dos clientes", item=645,
                duration_seconds=round(until - started, 3), expiration_advanced_in_owned_redis=False,
                active={i: v.get("actor_visibility", {}).get(owner) for i, v in hidden.items()},
                expired={i: v.get("actor_visibility", {}).get(owner) for i, v in expired.items()},
                observer_actor_restored=observer_restored, mechanic_ok=observer_restored,
                finding=None if observer_restored else "CHARACTER_REMOVE borra el actor remoto; SET_INVISIBLE al vencer no lo recrea.")
            # Restauración de la observación para que el runner compruebe también
            # reconexión, inventario y cierre de las dos sesiones.
            self.relocate(store, {2: (1, locations["base"][0] + 1, locations["base"][1])})
            for i in (1, 2):
                self.command(i, "close_mechanics")
                self.command(i, "soak")
        return self.steps
