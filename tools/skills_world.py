"""Regresión gráfica de las 22 habilidades en Redis descartable."""

import json
import time
from mechanics_world import MechanicsWorld as SpellWorld, SKILLS
from r10_world import prepare_fixture as base_fixture


def prepare_fixture(work, output):
    from src.services.map.map_resources_service import MapResourcesService

    target, locations = base_fixture(work, output)
    terrain = MapResourcesService()
    values = terrain.resources["map_2"]
    blocked = values["blocked"] | values["water"]
    x, y = next(
        (x, y)
        for x in range(20, 75)
        for y in range(20, 75)
        if all(
            (a, b) not in blocked
            for a in range(x - 3, x + 11)
            for b in range(y - 3, y + 5)
        )
    )
    locations["skills_base"] = (2, x, y)
    with (target / "world/map_npcs.toml").open("a") as f:
        for template, tx in ((7778, x + 1),):
            f.write(
                f"\n[[map_npcs.2.spawn_points]]\nnpc_id={template}\nx={tx}\ny={y}\ndirection=3\n"
            )
    with (target / "npcs/friendly.toml").open("a") as f:
        for template, hostile in ((7778, False),):
            f.write(f"""
[[npc]]
id={template}
nombre="Criatura de prueba {template}"
descripcion="Fixture controlado con cuerpo del catálogo propio"
body_id=9
head_id=0
hp_max=30000
nivel=10
es_hostil={str(hostile).lower()}
es_atacable=true
rango_agresion=1
cooldown_ataque=0.8
flags={{domable=400,attackable=1}}
""")
    for name, layer in [("anvil", "anvils"), ("forge", "forges")]:
        found = None
        for key, rows in terrain.resources.items():
            for tx, ty in rows.get(layer, set()):
                for dx, dy in [(1, 0), (-1, 0), (0, 1), (0, -1)]:
                    px, py = tx + dx, ty + dy
                    if (
                        1 < px < 100
                        and 1 < py < 100
                        and (px, py) not in rows["blocked"] | rows["water"]
                    ):
                        found = (int(key.split("_")[1]), px, py)
                        break
                if found:
                    break
            if found:
                break
        if not found:
            raise RuntimeError("No hay taller real " + name)
        locations[name] = found
    (output / "skills-fixture.json").write_text(
        json.dumps(locations, indent=2, default=list) + "\n"
    )
    return target, locations


def acceptance(steps, seconds, **_):
    ids = {
        int(row["observations"]["skill"])
        for row in steps
        if row.get("id", "").startswith("skill-")
    }
    return {
        "kind": "22 habilidades con dos clientes Godot gráficos instrumentados",
        "test_execution_passed": ids == set(range(1, 23)),
        "skills": sorted(ids),
        "r10_gameplay_passed": False,
    }


class MechanicsWorld(SpellWorld):
    def reset(
        self,
        store,
        positions=None,
        *,
        items=None,
        skills=None,
        stats=None,
        attrs=None,
        points=0,
    ):
        positions = positions or self.base

        def seed():
            for index in positions:
                uid = self.ids[index]
                # Login deriva la clase del personaje persistido en la cuenta.
                # Sembrar sólo user_stats se sobrescribe legítimamente al entrar.
                store.hset(f"account:{self.names[index-1]}:data", "char_job", int((stats or {}).get("class_id", 1)))
                current = store.hgetall(f"player:{uid}:user_stats")
                store.hset(
                    f"player:{uid}:user_stats",
                    mapping={
                        **{k: 0 for k in current if k.endswith("_until")},
                        "level": 40,
                        "experience": 0,
                        "elu": 9999999,
                        "min_hp": 30000,
                        "max_hp": 30000,
                        "min_mana": 30000,
                        "max_mana": 30000,
                        "min_sta": 30000,
                        "max_sta": 30000,
                        "gold": 1000000,
                        "safe_mode": 0,
                        "meditating": 0,
                        "sailing": 0,
                        "death_state": "complete",
                        **(stats or {}),
                    },
                )
                store.hset(
                    f"player:{uid}:stats",
                    mapping={
                        "strength": 20,
                        "agility": 20,
                        "intelligence": 20,
                        "charisma": 20,
                        "constitution": 20,
                        **(attrs or {}),
                    },
                )
                store.hset(
                    f"player:{uid}:hunger_thirst",
                    mapping={
                        "min_water": 100,
                        "max_water": 100,
                        "min_hunger": 100,
                        "max_hunger": 100,
                        "hunger_flag": 0,
                        "thirst_flag": 0,
                    },
                )
                store.delete(
                    f"player:{uid}:inventory",
                    f"player:{uid}:equipment",
                    f"player:{uid}:spellbook",
                    f"player:{uid}:skills",
                )
                if items:
                    store.hset(
                        f"player:{uid}:inventory",
                        mapping={
                            f"slot_{s}": f"{item}:{q}" for s, (item, q) in items.items()
                        },
                    )
                store.hset(f"player:{uid}:spellbook", mapping={"1": 3, "2": 2, "3": 46})
                progress = {
                    "progress_version": 2,
                    "natural_xp_base": 200,
                    "points": points,
                    "points_granted_through": 40,
                    "assigned_points": 10,
                }
                for definition in SKILLS:
                    key = definition["key"]
                    level = (skills or {}).get(key, 90)
                    progress.update(
                        {
                            f"level:{key}": level,
                            f"xp:{key}": 0,
                            f"partial:{key}": max(0, round(200 * 1.05**level) - 20),
                        }
                    )
                store.hset(f"player:{uid}:skills", mapping=progress)

        self.offline(store, positions, seed)

    def proof(self, store, skill, before, **evidence):
        definition = next(s for s in SKILLS if s["id"] == skill)
        key = definition["key"]
        after = self.skill_state(store)
        if skill in (16, 20, 21, 22):
            if after.get(f"xp:{key}", "0") != before.get(f"xp:{key}", "0"):
                raise RuntimeError("Entrenamiento natural indebido de " + key)
        elif int(after.get(f"xp:{key}", 0)) <= int(before.get(f"xp:{key}", 0)):
            raise RuntimeError("Falta entrenamiento real de " + key)
        self.passed(
            f"skill-{skill}-{len(self.steps)}",
            skill=skill,
            name=definition["name"],
            before=before,
            after=after,
            **evidence,
        )

    def attempt(self, store, skill, x, y):
        key = next(s for s in SKILLS if s["id"] == skill)["key"]
        before = int(self.skill_state(store).get(f"xp:{key}", 0))
        self.command(1, "ability", skill=skill)
        self.view(1, lambda v: v["using_skill"] == skill, "cursor de habilidad")
        self.command(1, "work", skill=skill, x=x, y=y)
        self.wait(
            lambda: int(self.skill_state(store).get(f"xp:{key}", 0)) > before,
            "entrenamiento confirmado",
        )

    def run(self, locations):
        self.deadline = time.monotonic() + 1800
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
            births = {i: self.skill_state(store, i) for i in (1, 2)}
            if any(int(s["points"]) != 10 for s in births.values()):
                raise RuntimeError("Alta sin diez puntos")
            _, x, y = locations["skills_base"]
            self.base = {1: (2, x, y), 2: (2, x, y + 2)}
            self.manual_all(store, births)
            self.gathering(store, locations)
            self.crafting(store, locations)
            self.meditation_and_magic(store, x, y)
            self.physical(store, x, y)
            self.personal(store, x, y)
            self.navigation(store, locations)
            self.leadership(store, locations)
            self.level_and_reconnect(store, locations)
            # El NPC usado para Domar ocupa x+1,y; el primer paso de la
            # observación corta debe quedar libre para ambos participantes.
            self.base = {1: (2, x + 4, y), 2: (2, x + 4, y + 2)}
            self.reset(store)
            for index in (1, 2):
                self.command(index, "soak")
        return self.steps

    def manual_all(self, store, births):
        self.reset(store, skills={s["key"]: 0 for s in SKILLS}, points=22)
        self.command(1, "skills_open")
        self.view(
            1,
            lambda v: (
                len(v.get("skill_rows", [])) == 22 and v.get("skills", {}).get("ready")
            ),
            "22 filas editables",
        )
        self.command(1, "allocate_batch", ids=list(range(1, 23)))
        self.wait(
            lambda: self.skill_state(store).get("points") == "0",
            "asignación de las 22 habilidades",
        )
        view = self.view(
            1,
            lambda v: v.get("skills", {}).get("ready") and v["skills"]["points"] == 0,
            "ACK de 22 habilidades",
        )
        if any(value != 1 for value in view["skills"]["values"]):
            raise RuntimeError("Fila manual sin confirmar")
        self.screen("skills-22-manual")
        self.command(1, "close_mechanics")
        self.command(1, "stats_open")
        self.view(1, lambda v: len(v.get("attributes", {})) == 5, "cinco atributos")
        self.screen("attributes-and-skills")
        self.command(1, "close_mechanics")
        self.passed("all-manual", births=births, view=view)

    def gathering(self, store, locations):
        for name, skill, key, tool, item in [
            ("wood", 9, "talar", 127, 58),
            ("mine", 13, "mineria", 187, 192),
            ("fish", 12, "pesca", 138, 139),
        ]:
            map_id, x, y, tx, ty = locations[name]
            self.reset(store, {1: (map_id, x, y)}, items={1: (tool, 1)})
            self.command(1, "equip", slot=1)
            before = self.skill_state(store)
            for _ in range(25):
                self.attempt(store, skill, tx, ty)
                if self.count(store, 1, item) > 0:
                    break
            if not self.count(store, 1, item):
                raise RuntimeError("No se obtuvo recurso " + key)
            self.command(1, "skills_open")
            view = self.view(
                1, lambda v: v.get("skills", {}).get("ready"), "progreso en ventana"
            )
            self.screen("gather-" + key)
            self.command(1, "close_mechanics")
            self.proof(
                store, skill, before, quantity=self.count(store, 1, item), view=view
            )

    def crafting(self, store, locations):
        for skill, button, recipe, result, items, position in [
            (
                15,
                15,
                "herreria:15",
                15,
                {1: (565, 1), 2: (386, 100)},
                locations["anvil"],
            ),
            (14, 14, "carpinteria:480", 480, {1: (564, 1), 2: (58, 100)}, self.base[1]),
            (13, 88, "fundir:192", 386, {1: (192, 100)}, locations["forge"]),
        ]:
            self.reset(store, {1: position}, items=items)
            before = self.skill_state(store)
            self.command(1, "ability", skill=button)
            self.view(
                1,
                lambda v: (
                    v.get("craft", {}).get("ready") and len(v["craft"]["recipes"]) > 0
                ),
                "recetas del servidor",
            )
            for _ in range(5):
                self.command(1, "craft_submit", recipe=recipe, quantity=2)
                self.view(
                    1,
                    lambda v: v.get("craft", {}).get("ready"),
                    "resultado de fabricar",
                )
                if self.count(store, 1, result) > 0:
                    break
            if self.count(store, 1, result) != 2:
                raise RuntimeError("Fabricación sin producto " + recipe)
            self.screen("craft-" + str(skill))
            self.command(1, "close_mechanics")
            self.proof(store, skill, before, recipe=recipe, quantity=2)

    def meditation_and_magic(self, store, x, y):
        self.reset(store, stats={"min_mana": 20000})
        before = self.skill_state(store)
        self.command(1, "ability", skill=5)
        self.wait(
            lambda: int(self.skill_state(store).get("xp:meditar", 0)) > 0,
            "tick real de meditación",
            30,
        )
        self.proof(store, 5, before, stats=self.stats(store, 1))
        self.command(1, "ability", skill=5)
        self.reset(store)
        before = self.skill_state(store)
        self.command(1, "cast", slot=2, x=x, y=y + 2)
        self.wait(
            lambda: int(self.skill_state(store).get("xp:magia", 0)) > 0,
            "entrenamiento de magia",
        )
        self.proof(store, 1, before, stats=self.stats(store, 1))

    def physical(self, store, x, y):
        for skill, items, equip in [
            (4, {1: (15, 1)}, True),
            (19, {}, False),
            (18, {1: (665, 1), 2: (480, 10)}, True),
        ]:
            self.reset(store, items=items)
            before = self.skill_state(store)
            if equip:
                self.command(1, "equip", slot=1)
            if skill == 18:
                self.attempt(store, 18, x + 1, y)
            else:
                self.command(1, "face", heading=2)
                self.command(1, "attack")
                key = next(s for s in SKILLS if s["id"] == skill)["key"]
                self.wait(
                    lambda: int(self.skill_state(store).get(f"xp:{key}", 0)) > 0,
                    "golpe físico válido",
                )
            self.proof(store, skill, before, items=self.items(store, 1))
            if skill == 4:
                for _ in range(20):
                    if int(self.skill_state(store).get("xp:apunalar", 0)) > 0:
                        break
                    time.sleep(0.6)
                    self.command(1, "attack")
                self.wait(
                    lambda: int(self.skill_state(store).get("xp:apunalar", 0)) > 0,
                    "apuñalar elegible",
                )
                self.proof(store, 6, before)
        self.reset(
            store,
            {1: (2, x, y), 2: (2, x - 1, y)},
            items={1: (404, 1)},
            skills={"robustez": 100, "agilidad": 100},
        )
        before = self.skill_state(store)
        hp = self.stats(store, 1)["min_hp"]
        attrs = store.hgetall(f"player:{self.ids[1]}:stats")
        self.command(1, "equip", slot=1)
        self.command(2, "face", heading=2)
        for _ in range(40):
            self.command(2, "attack")
            if (
                int(self.skill_state(store).get("xp:tacticas", 0)) > 0
                and int(self.skill_state(store).get("xp:defensa", 0)) > 0
                and self.stats(store, 1)["min_hp"] < hp
            ):
                break
            time.sleep(0.6)
        self.wait(
            lambda: (
                int(self.skill_state(store).get("xp:tacticas", 0)) > 0
                and int(self.skill_state(store).get("xp:defensa", 0)) > 0
                and self.stats(store, 1)["min_hp"] < hp
            ),
            "evasión, escudo y mitigación en PvP real",
        )
        for skill in (3, 11, 21, 22):
            self.proof(
                store,
                skill,
                before,
                hp_before=hp,
                hp_after=self.stats(store, 1)["min_hp"],
                attributes=attrs,
            )

    def personal(self, store, x, y):
        self.reset(store, stats={"class_id": 5})
        before = self.skill_state(store)
        for _ in range(30):
            self.command(1, "ability", skill=7)
            self.wait(
                lambda: int(self.skill_state(store).get("xp:ocultarse", 0)) > 0,
                "intento de ocultarse",
            )
            if (
                float(
                    store.hget(f"player:{self.ids[1]}:user_stats", "hidden_until") or 0
                )
                > time.time()
            ):
                break
            time.sleep(0.6)
        if (
            float(store.hget(f"player:{self.ids[1]}:user_stats", "hidden_until") or 0)
            <= time.time()
        ):
            raise RuntimeError("No se ocultó")
        self.view(
            2,
            lambda v: not v["actor_visibility"][str(self.ids[1])]["renderer_visible"],
            "oculto para observador",
        )
        self.proof(store, 7, before)
        self.command(1, "ability", skill=7)
        self.reset(store, items={1: (58, 20)})
        before = self.skill_state(store)
        self.attempt(store, 8, x - 1, y)
        self.wait(
            lambda: store.exists(f"world:campfire:2:{x - 1}:{y}"), "fogata persistida"
        )
        self.screen("campfire")
        self.proof(
            store, 8, before, fire=store.hgetall(f"world:campfire:2:{x - 1}:{y}")
        )
        self.reset(store, {1: (2, x, y), 2: (2, x, y + 1)}, items={1: (58, 10)})
        before = self.skill_state(store)
        gold = self.stats(store, 1)["gold"]
        for _ in range(30):
            self.attempt(store, 2, x, y + 1)
            if self.stats(store, 1)["gold"] > gold:
                break
            time.sleep(0.6)
        if self.stats(store, 1)["gold"] <= gold:
            raise RuntimeError("No hubo transferencia de oro")
        self.proof(
            store, 2, before, gold_before=gold, gold_after=self.stats(store, 1)["gold"]
        )
        self.reset(store)
        before = self.skill_state(store)
        for _ in range(35):
            self.attempt(store, 17, x + 1, y)
            if self.pets(store):
                break
            time.sleep(0.6)
        if not any(p.get("is_tamed") == "True" for p in self.pets(store)):
            raise RuntimeError("No se domó")
        self.proof(store, 17, before, pets=self.pets(store))

    def navigation(self, store, locations):
        map_id, x, y, tx, ty = locations["fish"]
        self.reset(store, {1: (map_id, x, y)}, items={1: (474, 1)})
        before = self.skill_state(store)
        self.command(1, "use", slot=1)
        self.view(1, lambda v: v.get("sailing", False), "barco visible")
        self.command(1, "logout")
        self.wait(
            lambda: not store.exists(f"session:{self.ids[1]}:owner"), "liberar barco"
        )
        self.command(1, "login")
        view = self.view(
            1,
            lambda v: v.get("sailing", False) and v["appearance"] == [84, 0],
            "barco reconectado",
        )
        self.screen("navigation-reconnected")
        self.proof(store, 20, before, view=view)
        self.command(1, "use", slot=1)
        self.view(1, lambda v: not v.get("sailing", False), "desembarcar")

    def leadership(self, store, locations):
        x, y = locations["base"]
        self.reset(store, {1: (1, x, y), 2: (1, x + 1, y)})
        before = self.skill_state(store)
        self.command(1, "chat", text="/crearparty")
        self.wait(
            lambda: store.get(f"user:{self.ids[1]}:party"),
            "crear grupo con Liderazgo",
            10,
        )
        self.proof(store, 16, before, party=True)
        self.command(1, "chat", text="/salirparty")
        self.command(1, "click", x=x, y=y - 2)
        self.view(1, lambda v: v["panel"] == "merchant", "comercio real")
        before = self.skill_state(store)
        self.command(1, "merchant", slot=1, amount=1, buy=True)
        self.wait(
            lambda: int(self.skill_state(store).get("xp:comerciar", 0)) > 0,
            "comercio entrenado",
        )
        self.proof(store, 10, before)
        self.command(1, "close")

    def level_and_reconnect(self, store, locations):
        map_id, x, y, tx, ty = locations["wood"]
        position = {1: (map_id, x, y)}
        self.reset(
            store,
            position,
            items={1: (127, 1)},
            skills={"talar": 0},
            stats={"level": 1, "experience": 299, "elu": 1},
        )

        def seed():
            store.hset(
                f"player:{self.ids[1]}:skills",
                mapping={"partial:talar": 180, "points_granted_through": 1},
            )

        self.offline(store, position, seed)
        self.command(1, "equip", slot=1)
        self.attempt(store, 9, tx, ty)
        self.wait(lambda: self.stats(store, 1)["level"] == 2, "nivel por entrenamiento")
        self.command(1, "skills_open")
        view = self.view(
            1,
            lambda v: v.get("skills", {}).get("points") == 10,
            "diez puntos nivel dos",
        )
        self.screen("level-up-training")
        self.command(1, "close_mechanics")
        saved = self.skill_state(store)
        self.command(1, "logout")
        self.wait(
            lambda: not store.exists(f"session:{self.ids[1]}:owner"),
            "desconectar progreso",
        )
        self.command(1, "login")
        if self.skill_state(store) != saved:
            raise RuntimeError("Progreso cambió al reconectar")
        self.passed(
            "level-and-reconnect", skills=saved, view=view, pets=self.pets(store)
        )
        for i in (1, 2):
            self.command(i, "logout")
            self.wait(
                lambda i=i: not store.exists(f"session:{self.ids[i]}:owner"),
                "liberar antes de reiniciar",
            )
        skills_before = {i: self.skill_state(store, i) for i in (1, 2)}
        pets_before = self.pets(store)
        self.server = self.restart_server()
        for i in (1, 2):
            self.command(i, "login")
        if any(self.skill_state(store, i) != skills_before[i] for i in (1, 2)):
            raise RuntimeError("El reinicio cambió progreso persistido")
        if not self.pets(store) or not any(
            p.get("is_tamed") == "True" for p in self.pets(store)
        ):
            raise RuntimeError("El reinicio perdió la mascota domada")
        self.passed(
            "server-restart",
            skills=skills_before,
            pets_before=pets_before,
            pets_after=self.pets(store),
        )
