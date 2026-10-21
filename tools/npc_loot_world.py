"""Todos los tipos de botín: dos Godot, muertes de red y recogida/equipo reales."""

import json
import re
import time

from full_world import FullWorld
from skills_world import prepare_fixture as skills_fixture


def prepare_fixture(work, output):
    from src.services.map.map_resources_service import MapResourcesService
    from src.services.npc.loot_table_service import LootTableService

    target, locations = skills_fixture(work, output)
    policy = LootTableService()
    terrain = MapResourcesService()
    text = (target / "npcs/loot_tables.toml").read_text()
    text = re.sub(r"(?m)^equipment_probability = [^\n]+", "equipment_probability = 1.0", text)
    cases, spawns = [], []
    templates = []
    available = []
    for map_id in range(2, 291):
        rows = terrain.resources.get(f"map_{map_id}")
        if not rows: continue
        blocked = rows["blocked"] | rows["water"]
        point = next(((x, y) for x in range(20, 80) for y in range(20, 80)
                      if all((a, b) not in blocked for a in range(x-2, x+3) for b in range(y-2, y+3))), None)
        if point: available.append((map_id, *point))
        if len(available) == len(policy.item_rules.categories): break
    if len(available) != len(policy.item_rules.categories):
        raise RuntimeError("No hay suficientes mapas transitables para ensayar todas las categorías")
    # Sólo en la copia descartable: fuerza un resultado por categoría para que la
    # aceptación de red/UI no dependa de esperar cientos de tiradas. El servidor
    # prueba aparte las probabilidades normales y cada uno de los IDs elegibles.
    for index, (category, spec) in enumerate(policy.item_rules.categories.items()):
        map_id, x, y = available[index]
        template = 7800 + index
        level = max([2, 18, 38, 55, 100][index % 5], policy.bands[min(policy.item_rules.pools[category])].min_level)
        text += f"\n[profiles.fixture_{category}]\ngold_probability=1.0\nequipment_multiplier={1.0 if spec['slot']=='equipment' else 0.0}\nconsumable_probability={1.0 if spec['slot']=='consumable' else 0.0}\nmisc_probability={1.0 if spec['slot']=='misc' else 0.0}\ncategories=[{json.dumps(category)}]\n"
        templates.append(f"""
[[npc]]
id={template}
nombre="Botín de prueba: {category}"
descripcion="Objetivo exclusivo del ensayo de botín"
body_id=9
head_id=0
hp_max=1
nivel={level}
loot_profile="fixture_{category}"
es_hostil=false
es_atacable=true
rango_agresion=1
flags={{attackable=1}}
""")
        spawns.append(f"\n[[map_npcs.{map_id}.spawn_points]]\nnpc_id={template}\nx={x}\ny={y}\ndirection=3\n")
        cases.append({"category": category, "template": template, "map": map_id, "x": x, "y": y, "level": level})
    (target / "npcs/loot_tables.toml").write_text(text)
    with (target / "npcs/friendly.toml").open("a") as file:
        file.write("".join(templates))
    (target / "world/map_npcs.toml").write_text("".join(spawns))
    locations["loot_cases"] = cases
    (output / "npc-loot-fixture.json").write_text(json.dumps({
        "test_only_probability_override": "One result in each selected category plus gold; actual production pools/stats/quantities/quality selection",
        "normal_policy_probabilities": {str(b.min_level): policy.probabilities(b.min_level, "humanoid") for b in policy.bands},
        "cases": cases,
    }, indent=2) + "\n")
    return target, locations


def acceptance(steps, seconds, *, graphical, **_):
    rows = [s for s in steps if s.get("id", "").startswith("npc-loot-") and s.get("passed")]
    return {"test_execution_passed": graphical and len(rows) == 29,
            "categories": [s["observations"]["category"] for s in rows],
            "normal_probability_distribution_proven_here": False,
            "r10_gameplay_passed": False}


def ground(store, map_id):
    from src.utils.ground_storage import decode_fields
    from src.utils.redis_config import RedisKeys

    return decode_fields(map_id, store.hgetall(RedisKeys.ground_items(map_id)))


class NPCLootWorld(FullWorld):
    def run(self, locations):
        self.deadline = time.monotonic() + 1200
        self.wait(lambda: all("INTEGRATION_WORLD: READY" in (self.output / f"godot-{i}.log").read_text() for i in (1, 2)), "dos clientes de botín", 90)
        with self.fixture.client() as store:
            self.ids = {i: int(store.hget(f"account:{self.names[i-1]}:data", "user_id")) for i in (1, 2)}
            case = locations["loot_cases"][0]
            positions = {1: (case["map"], case["x"], case["y"]+1), 2: (case["map"], case["x"]+1, case["y"]+1)}
            self.reset(store, positions, stats={"class_id": 3, "gold": 0}, skills={"magia": 100})
            for index, case in enumerate(locations["loot_cases"]):
                self.exercise(store, case, index)
            for i in (1, 2):
                self.command(i, "close_mechanics")
                self.command(i, "soak")
        return self.steps

    def exercise(self, store, case, index):
        from src.models.item_catalog import ItemCatalog

        catalog = ItemCatalog()
        map_id, x, y = case["map"], case["x"], case["y"]
        positions = {1: (map_id, x, y+1), 2: (map_id, x+1, y+1)}
        def spells():
            store.hset(f"player:{self.ids[1]}:spellbook", mapping={"1": 3, "2": 2, "3": 4})
        self.offline(store, positions, spells)
        key = next(k for k in store.scan_iter("npc:instance:*") if store.hget(k, "npc_id") == str(case["template"]))
        npc = store.hgetall(key)
        for i in (1, 2):
            self.view(i, lambda v: str(npc["char_index"]) in v["world_characters"], "NPC visible en ambos clientes")
        if index == 0:
            self.command(1, "face", heading=1)
            for _ in range(15):
                if not store.exists(key): break
                self.command(1, "attack")
                time.sleep(.15)
            method = "physical"
        else:
            self.command(1, "cast", slot=3 if index == 1 else 2, actor=int(npc["char_index"]), x=x, y=y)
            method = "poison" if index == 1 else "spell"
        self.wait(lambda: not store.exists(key), "muerte de NPC y liquidación durable", 25)
        receipt = json.loads(store.get("npc:death:" + npc["instance_id"]))
        assert receipt["level"] == case["level"]
        expected = receipt["result"]["items"]
        assert len(expected) == 2 and expected[0]["item_id"] == 12
        drops = []
        while ground(store, map_id).positions():
            state = ground(store, map_id)
            (tx, ty), rows = next(iter(state.positions().items()))
            item = rows[0]
            for i in (1, 2):
                self.wait(lambda i=i: all(self.command(i, "loot_probe", x=tx, y=ty, graphic=item["grh_index"])["loot_probe"].values()), "mismo sprite de botín visible en ambos clientes")
            if item["item_id"] != 12:
                self.both_screens("loot-" + case["category"])
            picker = 1 if item["item_id"] == 12 else index % 2 + 1
            observer = 3 - picker
            self.offline(store, {picker: (map_id, tx, ty), observer: (map_id, tx+1, ty)})
            before_gold = int(store.hget(f"player:{self.ids[picker]}:user_stats", "gold") or 0)
            self.command(picker, "pickup")
            self.wait(lambda: not any(r["stack_id"] == item["stack_id"] for r in ground(store, map_id).tile(tx, ty)), "recogida por identidad de pila")
            if item["item_id"] == 12:
                balance = int(store.hget(f"player:{self.ids[picker]}:user_stats", "gold"))
                assert balance == before_gold + item["quantity"]
                self.view(picker, lambda v: v["gold"] == balance, "oro en UI y Redis")
                drops.append({"id": 12, "quantity": item["quantity"], "picker": picker})
                continue
            inv = store.hgetall(f"player:{self.ids[picker]}:inventory")
            slot = int(next(k.removeprefix("slot_") for k, row in inv.items() if row == f"{item['item_id']}:{item['quantity']}"))
            raw = catalog.get_item_data(item["item_id"])
            view = self.view(picker, lambda v: v["items"].get(str(slot), [0])[0] == item["item_id"], "objeto recogido en inventario")
            details = view["item_details"][str(slot)]
            assert details["name"] == raw["Name"] and details["icon_loaded"]
            assert details["type"] == raw["ObjType"]
            for field, key_name in (("min_hit", "MinHit"), ("max_hit", "MaxHit"), ("min_def", "MinDef"), ("max_def", "MaxDef")):
                if raw["ObjType"] == 18:
                    key_name = {"MinDef": "DefensaMagicaMin", "MaxDef": "DefensaMagicaMax"}.get(key_name, key_name)
                assert details[field] == int(raw.get(key_name, 0))
            equipped = False
            if raw["ObjType"] in (2, 3, 16, 17):
                self.command(picker, "equip", slot=slot)
                equipped_view = self.view(picker, lambda v: v["items"][str(slot)][2], "equipo confirmado por servidor")
                equipment_key = {2: "weapon", 3: "armor", 16: "shield", 17: "helmet"}[raw["ObjType"]]
                assert store.hget(f"player:{self.ids[picker]}:equipment", equipment_key) == str(slot)
                if equipment_key in equipped_view["gear_labels"]:
                    pair = ("MinHit", "MaxHit") if equipment_key == "weapon" else ("MinDef", "MaxDef")
                    assert equipped_view["gear_labels"][equipment_key] == f"{raw.get(pair[0],0)}/{raw.get(pair[1],0)}"
                self.screen("equipped-" + case["category"], picker)
                self.command(picker, "equip", slot=slot)
                cleared = self.view(picker, lambda v: not v["items"][str(slot)][2], "desequipar tras comprobar stats")
                if equipment_key in cleared["gear_labels"]:
                    assert cleared["gear_labels"][equipment_key] == "0/0"
                equipped = True
            used = False
            effects = {}
            if raw["ObjType"] in (1, 11, 13, 34):
                def needs():
                    store.hset(f"player:{self.ids[picker]}:user_stats", mapping={"min_hp": 15000, "min_mana": 10000})
                    store.hset(f"player:{self.ids[picker]}:hunger_thirst", mapping={"min_hunger": 10, "min_water": 10})
                current_positions = {i: (map_id, int(store.hget(f"player:{self.ids[i]}:position", "x")), int(store.hget(f"player:{self.ids[i]}:position", "y"))) for i in (1, 2)}
                self.offline(store, current_positions, needs)
                self.command(picker, "use", slot=slot)
                self.wait(lambda: store.hget(f"player:{self.ids[picker]}:inventory", f"slot_{slot}") != f"{item['item_id']}:{item['quantity']}", "uso real del consumible recogido")
                if raw["ObjType"] in (1, 13, 34):
                    field = "min_hunger" if raw["ObjType"] == 1 else "min_water"
                    self.wait(lambda: int(store.hget(f"player:{self.ids[picker]}:hunger_thirst", field)) > 10, "efecto real de comida o bebida recogida")
                    effects = store.hgetall(f"player:{self.ids[picker]}:hunger_thirst")
                used = True
            drops.append({"id": item["item_id"], "quantity": item["quantity"], "picker": picker, "metadata": details, "equipped": equipped, "used": used, "effects": effects})
        self.passed("npc-loot-" + case["category"], category=case["category"], npc_level=case["level"], kill_method=method, items=drops, both_clients_observed=True, test_only_probabilities=True)
