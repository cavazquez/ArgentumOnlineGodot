"""Misiones, facciones, grupos, clanes y magia ampliada mediante dos Godot reales."""

import json
import secrets
import time

from r10_world import R10World
from skills_world import prepare_fixture as skills_fixture
from mechanics_world import MechanicsWorld as SpellWorld

REQUIRED = {"expansion-finder", "expansion-clans", "expansion-factions", "expansion-quests", "expansion-magic"}


def acceptance(steps, seconds, *, graphical, **_):
    done = {row["id"] for row in steps if row.get("passed") is True}
    return {"test_execution_passed": graphical and REQUIRED <= done, "missing": sorted(REQUIRED - done)}


def prepare_fixture(work, output):
    target, locations = skills_fixture(work, output)
    x, y = locations["base"]
    _, bx, by = locations["skills_base"]
    with (target / "world/map_npcs.toml").open("a") as file:
        file.write(f"\n[[map_npcs.1.spawn_points]]\nnpc_id=2\nx={x}\ny={y+2}\ndirection=3\n")
        for offset in range(3):
            file.write(f"\n[[map_npcs.2.spawn_points]]\nnpc_id=500\nx={bx+5}\ny={by+offset}\ndirection=3\n")
    return target, locations


class Phase50World(R10World):
    offline = SpellWorld.offline

    def open(self, index, topic):
        time.sleep(0.4)
        self.command(index, "close")
        self.command(index, "world_open", topic=topic)
        return self.view(index, lambda value: value.get("world_window") == topic and bool(value.get("world_window_state")) and not value.get("world_pending", True), "abrir " + topic)["world_window_state"]

    def action(self, index, topic, action, **params):
        time.sleep(0.4)
        self.command(index, "world_action", topic=topic, action=action, **params)
        return self.view(index, lambda value: not value.get("world_pending", True), "confirmar " + topic + "." + action)["world_window_state"]

    def finder(self, store):
        self.open(1, "party")
        self.action(1, "party", "create")
        party = int(store.get(f"user:{self.ids[1]}:party"))
        self.open(1, "finder")
        self.action(1, "finder", "publish", controls={"activity": 1, "text": "Prueba de caza", "minimum": 1, "maximum": 100})
        self.open(2, "finder")
        self.action(2, "finder", "request", select=party)
        assert not store.get(f"user:{self.ids[2]}:party"), "Una solicitud no concede membresía"
        self.open(1, "finder")
        self.action(1, "finder", "invite", second=self.ids[2])
        self.open(2, "party")
        self.action(2, "party", "accept")
        self.wait(lambda: store.get(f"user:{self.ids[2]}:party") == str(party), "aceptación de ingreso real")
        self.open(1, "finder")
        self.action(1, "finder", "close")
        assert not store.get(f"finder:ad:{party}")
        self.passed("expansion-finder", "Anuncio, solicitud, invitación y consentimiento", party=party)

    def clans(self, store):
        names = {i: "Phase" + secrets.token_hex(3) + str(i) for i in (1, 2)}
        for i in (1, 2):
            self.open(i, "clan")
            self.action(i, "clan", "create", name=names[i])
        ids = {i: int(store.get(f"user:{self.ids[i]}:clan")) for i in (1, 2)}
        self.open(1, "depot")
        before = self.count(store, 1, 38)
        self.action(1, "depot", "deposit", second=1, controls={"quantity": 1})
        assert self.count(store, 1, 38) == before - 1
        state = self.open(1, "depot")
        slot = next(row["slot"] for row in state["rows"] if row["item"] == 38)
        self.action(1, "depot", "withdraw", select_key="slot", select=slot, controls={"quantity": 1})
        assert self.count(store, 1, 38) == before
        for actor, action in ((1, "propose"), (2, "accept"), (1, "cancel"), (1, "declare_war"), (2, "end_war")):
            self.open(actor, "diplomacy")
            self.action(actor, "diplomacy", action, controls={"clan": names[3-actor]})
            expected = {"propose": "proposed", "accept": "alliance", "cancel": "none", "declare_war": "war", "end_war": "none"}[action]
            assert store.hget(f"clan:relation:{min(ids.values())}:{max(ids.values())}", "state") == expected
        self.passed("expansion-clans", "Depósito íntegro y diplomacia desde líderes autorizados", clans=ids)

    def factions(self, store):
        for index, selection, expected in ((1, 0, "royal"), (2, 1, "chaos")):
            self.open(index, "faction")
            self.action(index, "faction", "join", controls={"faction": selection})
            assert store.hget(f"player:{self.ids[index]}:user_stats", "faction_id") == expected
            self.action(index, "faction", "leave")
            assert store.hget(f"player:{self.ids[index]}:user_stats", "faction_id") == "neutral"
        self.passed("expansion-factions", "Afiliación, rango visible y abandono persistidos", both=True)

    def quests(self, store, locations):
        x, y = locations["base"]
        self.command(1, "close")
        self.command(2, "close")
        self.relocate(store, {1: (1, x, y), 2: (1, x + 1, y)}, reset=True)
        def materials():
            store.hset(f"player:{self.ids[1]}:inventory", "slot_28", "58:10")
        self.offline(store, {1: (1, x, y)}, materials)
        self.open(1, "quests")
        self.action(1, "quests", "accept", select="primeros-suministros")
        before = self.count(store, 1, 58)
        self.action(1, "quests", "deliver", select="primeros-suministros")
        assert self.count(store, 1, 58) == before - 5
        self.action(1, "quests", "claim", select="primeros-suministros")
        state = json.loads(store.hget(f"quests:{self.ids[1]}", "primeros-suministros"))
        assert state["status"] == "claimed"
        self.action(1, "quests", "accept", select="senderos-seguros")
        self.command(1, "close")
        _, bx, by = locations["skills_base"]
        # Un NPC móvil puede ocupar la preparación antes de completar el login.
        # El servidor conserva autoridad para elegir una llegada segura cercana.
        self.relocate(store, {1: (2, bx, by + 2), 2: (2, bx + 1, by + 2)}, reset=True, allow_adjustment=True)
        targets = {key: npc for key in store.scan_iter("npc:instance:*")
                   if (npc := store.hgetall(key)).get("npc_id") == "500" and npc.get("map_id") == "2"}
        assert len(targets) == 3
        for key in targets:
            npc = store.hgetall(key)
            if not npc: continue  # Otro clic del grupo móvil ya pudo vencerlo.
            # Preparar cada encuentro con la cuenta desconectada; los NPC
            # conservan su vida, movimiento y catálogo originales.
            from src.services.map.map_resources_service import MapResourcesService
            terrain = MapResourcesService().resources["map_2"]
            occupied = {(int(row["x"]), int(row["y"])) for other in store.scan_iter("npc:instance:*")
                        if (row := store.hgetall(other)).get("map_id") == "2"}
            tx,ty = int(npc["x"]),int(npc["y"])
            at = next((tx+dx,ty+dy) for dx,dy in [(0,1),(1,0),(0,-1),(-1,0)]
                      if (tx+dx,ty+dy) not in terrain["blocked"] | terrain["water"] | occupied)
            self.relocate(store,{1:(2,*at)},allow_adjustment=True)
            def defeated():
                current = store.hgetall(key)
                if not current or int(current["hp"]) <= 0: return True
                self.command(1, "cast", slot=2, actor=int(current["char_index"]), x=int(current["x"]), y=int(current["y"]))
                time.sleep(1.2)
                return not store.exists(key) or int(store.hget(key, "hp") or 0) <= 0
            self.wait(defeated, "vencer al NPC móvil mediante el cliente", 90)
            self.wait(lambda: not store.exists(key), "liquidación de la baja confirmada")
        deaths = {npc["instance_id"]: json.loads(store.get("npc:death:" + npc["instance_id"]) or "null")
                  for npc in targets.values()}
        assert all(death and death["result"]["settled"] for death in deaths.values())
        killed = len(deaths)
        (self.output / "quest-kill-observations.json").write_text(json.dumps({
            "journal": store.hgetall(f"quests:{self.ids[1]}"),
            "events": {key: store.hgetall(key) for key in store.scan_iter("quest-event:*")},
            "npcs": {key: store.hgetall(key) for key in store.scan_iter("npc:instance:*")},
            "confirmed_deaths": deaths,
        }, indent=2) + "\n")
        self.wait(lambda: json.loads(store.hget(f"quests:{self.ids[1]}", "senderos-seguros"))["status"] == "completed", "tres bajas confirmadas")
        self.relocate(store, {1: (1, x, y), 2: (1, x+1, y)})
        self.open(1, "quests")
        self.action(1, "quests", "claim", select="senderos-seguros")
        self.open(2, "quests")
        self.action(2, "quests", "accept", select="primeros-suministros")
        self.action(2, "quests", "abandon", select="primeros-suministros")
        self.passed("expansion-quests", "Aceptar, entregar, matar, cobrar y abandonar mediante el diario", kills=killed)

    def magic(self, store, locations):
        _, x, y = locations["skills_base"]
        positions = {1: (2, x, y+2), 2: (2, x+1, y+2)}
        self.relocate(store, positions, reset=True)
        def resources():
            for index in (1, 2):
                uid = self.ids[index]
                store.hset(f"player:{uid}:user_stats", mapping={"safe_mode": 0, "min_hp": 1500, "max_hp": 2000})
                store.hset(f"player:{uid}:skills", mapping={"level:magia": 100, "assigned_points": 10, "progress_version": 2})
                store.delete(f"player:{uid}:spellbook")
                store.hset(f"player:{uid}:spellbook", mapping={str(i): sid for i, sid in enumerate((47, 48, 49, 50, 51), 1)})
                store.hset(f"player:{uid}:inventory", mapping={"slot_28": "406:5", "slot_29": "407:5"})
        self.offline(store, positions, resources)
        for caster, target in ((1, 2), (2, 1)):
            uid, victim = self.ids[caster], self.ids[target]
            pos = positions[target]
            for slot, sid in enumerate((47, 48, 49, 50, 51), 1):
                self.command(caster, "capture_reset", label=f"extended-{sid}-{caster}")
                self.command(target, "capture_reset", label=f"extended-{sid}-{caster}")
                before = store.hgetall(f"player:{uid}:user_stats")
                self.command(caster, "cast_probe", slot=slot, x=pos[1], y=pos[2], path=str(self.output / f"extended-{sid}-{caster}.png"))
                view = self.command(caster, "snapshot")
                messages = [row.get("message", "") for row in view["fx_packets"] if row["kind"] == "console"]
                assert any("Has lanzado" in message for message in messages), messages
                after = store.hgetall(f"player:{uid}:user_stats")
                assert int(after["min_mana"]) < int(before["min_mana"])
                assert any(row["kind"] == "fx" for row in self.command(target, "snapshot")["fx_packets"])
                victim_key = f"player:{victim}:user_stats"
                if sid in (48, 49):
                    mode = "damage" if sid == 48 else "heal"
                    initial_hp = int(store.hget(victim_key, "min_hp"))
                    effects = json.loads(store.hget(victim_key, "periodic_effects"))
                    next_pulse = next(row["next"] for row in effects if row["mode"] == mode)
                    self.wait(lambda: any(row["mode"] == mode and row["next"] > next_pulse for row in json.loads(store.hget(victim_key, "periodic_effects"))), "pulso real de " + mode, 10)
                    current_hp = int(store.hget(victim_key, "min_hp"))
                    assert current_hp < initial_hp if mode == "damage" else current_hp > initial_hp
                    self.command(caster, "cast", slot=5, x=pos[1], y=pos[2])
                    self.wait(lambda: store.hget(victim_key, "periodic_effects") == "[]", "disipar pulso confirmado")
                elif sid == 50:
                    hp = int(store.hget(victim_key, "min_hp"))
                    self.command(caster, "cast", slot=1, x=pos[1], y=pos[2])
                    self.wait(lambda: 0 < int(store.hget(victim_key, "barrier_capacity") or 0) < 100, "absorción real de la barrera")
                    assert int(store.hget(victim_key, "min_hp")) == hp
            assert store.hget(f"player:{victim}:user_stats", "barrier_capacity") == "0"
            assert store.hget(f"player:{victim}:user_stats", "periodic_effects") == "[]"
            assert self.count(store, caster, 406) == 3 and self.count(store, caster, 407) == 4
        self.passed("expansion-magic", "Área, componentes, pulsos, barrera y disipación en ambos sentidos", spells=[47,48,49,50,51])

    def run(self, locations):
        self.deadline = time.monotonic() + 1200
        self.wait(lambda: all("INTEGRATION_WORLD: READY" in (self.output / f"godot-{i}.log").read_text() for i in (1, 2)), "dos Godot para expansión", 90)
        with self.fixture.client() as store:
            self.ids = {i: int(store.hget(f"account:{self.names[i-1]}:data", "user_id")) for i in (1, 2)}
            x, y = locations["base"]
            self.relocate(store, {1:(1,x,y), 2:(1,x+1,y)}, reset=True)
            self.finder(store)
            self.clans(store)
            self.factions(store)
            self.quests(store, locations)
            self.magic(store, locations)
            for index in (1, 2):
                self.command(index, "close")
                self.command(index, "soak")
        return self.steps
