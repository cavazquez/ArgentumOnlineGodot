"""Equipo por UI real y representación del mismo actor en las dos ventanas."""

from r10_world import R10World, prepare_fixture

SAMPLES = ((30, "armor"), (15, "weapon"), (563, "weapon"), (561, "weapon"),
           (562, "weapon"), (564, "weapon"), (128, "shield"), (132, "helmet"),
           (2, "weapon"), (31, "armor"), (659, "weapon"),
           (1058, "helmet"), (401, "weapon"), (543, "weapon"),
           (1055, "boots"), (1059, "boots"), (1063, "boots"), (1067, "boots"), (1071, "boots"))
FOLDERS = {"body": ("Bodies", "body"), "weapon": ("Weapons", "weapon"),
           "shield": ("Shields", "shield"), "helmet": ("Helmets", "helmet")}


def acceptance(steps, _seconds, **_kwargs):
    required = {"equipment-1", "equipment-2", "equipment-reconnect", "equipment-remove", "equipment-map-exit"}
    missing = sorted(required - {row["id"] for row in steps if row.get("passed")})
    return {"test_execution_passed": not missing, "missing": missing, "r10_gameplay_passed": False}


def rendered_as(view, actor, expected):
    layers = view.get("actor_equipment", {}).get(str(actor), {})
    for key, graphic in expected.items():
        layer = layers.get(key, {})
        if layer.get("id") != graphic:
            return False
        if graphic > 0:
            if key == "boots":
                if not layer.get("visible") or layer.get("frame_count", 0) < 1: return False
                continue
            folder, prefix = FOLDERS[key]
            if not layer.get("visible") or layer.get("frame_count", 0) < 1 or layer.get("resource") != f"res://Resources/Character/{folder}/{prefix}_{graphic}.tres":
                return False
            if key == "helmet" and graphic == 3:
                cap = layer.get("position", [])
                head = layers.get("head", {}).get("position", [])
                if len(cap) != 2 or len(head) != 2 or cap[1] - head[1] != -23:
                    return False
    return True


class EquipmentWorld(R10World):
    def see(self, actor, expected):
        for viewer in (1, 2):
            self.view(viewer, lambda v: rendered_as(v, self.ids[actor], expected),
                      f"equipo real de {actor} visible en cliente {viewer}: {expected}")

    def run(self, locations):
        from src.models.items_catalog import ITEMS_CATALOG

        self.wait(lambda: all("INTEGRATION_WORLD: READY" in (self.output / f"godot-{i}.log").read_text() for i in (1, 2)), "alta de ambos clientes", 60)
        with self.fixture.client() as store:
            self.ids = {i: int(store.hget(f"account:{self.names[i-1]}:data", "user_id")) for i in (1, 2)}
            self.data["player"]["class_id"] = 3
            self.data["items"] = {str(slot): [item, 1] for slot, (item, _kind) in enumerate(SAMPLES, 1)}
            x, y = locations["base"]
            self.relocate(store, {1: (1, x, y), 2: (1, x+1, y)}, reset=True, accounts={1: {"char_job": 3}, 2: {"char_job": 3, "char_race": 4, "char_body": 4, "char_head": 3}})
            expected = {}
            bases = {}
            for actor in (1, 2):
                account = store.hgetall(f"account:{self.names[actor-1]}:data")
                baseline = int(account.get("char_body", account.get("char_race", 1))) or 1
                bases[actor] = baseline
                visual = {"body": baseline, "weapon": 0, "shield": 0, "helmet": 0, "boots": 0}
                for slot, (item_id, kind) in enumerate(SAMPLES, 1):
                    item = ITEMS_CATALOG[item_id]
                    self.command(actor, "equip", slot=slot)
                    self.wait(lambda: store.hget(f"player:{self.ids[actor]}:equipment", kind) == str(slot), "equipo confirmado en Redis")
                    visual["body" if kind == "armor" else kind] = item.body_animation if kind == "armor" else (item.dwarf_animation or item.animation) if kind == "weapon" and actor == 2 else item.animation
                    self.see(actor, visual)
                    if kind in ("armor", "helmet", "shield", "boots") or item_id in (15, 563, 401, 543):
                        for viewer in (1, 2): self.command(viewer, "capture", label=f"equip-{actor}-{item_id}")
                origin = (x+actor-1, y)
                actions = ("ui_down", "ui_left", "ui_up", "ui_right") if actor == 1 else ("ui_right", "ui_down", "ui_left", "ui_up")
                for action in actions:
                    self.command(actor, "step", action=action)
                    self.see(actor, visual)
                self.view(actor, lambda v: (v["x"], v["y"]) == origin, "equipo conservado tras cuatro orientaciones")
                expected[actor] = visual.copy()
                self.passed(f"equipment-{actor}", "Equipo y herramientas visibles en ambas ventanas", samples=[item for item, _kind in SAMPLES], four_directions=True)
            for actor in (1, 2):
                self.command(actor, "logout")
                self.wait(lambda: not store.exists(f"session:{self.ids[actor]}:owner"), "liberar sesión con equipo")
                self.command(actor, "login")
                self.see(actor, expected[actor])
            self.passed("equipment-reconnect", "Equipo restaurado al reconectar ambos jugadores", preserved=True)
            from src.core.server_initializer import ServerInitializer
            from src.game.map_manager import MapManager

            maps = MapManager()
            ServerInitializer._load_map_tiles(maps)
            source_map, px, py, action, destination = locations["exit"]
            dx, dy = {"ui_up": (0, -1), "ui_down": (0, 1), "ui_left": (-1, 0), "ui_right": (1, 0)}[action]
            arrival = maps.get_exit_tile(source_map, px+dx, py+dy)
            ax, ay = arrival["to_x"], arrival["to_y"]
            observer = next((xx, yy) for xx, yy in ((ax+1, ay), (ax, ay+1), (ax-1, ay), (ax, ay-1))
                            if maps.can_move_to(destination, xx, yy) and maps.get_exit_tile(destination, xx, yy) is None)
            self.relocate(store, {1: (source_map, px, py), 2: (destination, *observer)})
            self.command(1, "move", action=action)
            self.view(1, lambda v: v["map"] == destination, "cruce real del portal con equipo")
            for actor in (1, 2): self.see(actor, expected[actor])
            for viewer in (1, 2): self.command(viewer, "capture", label="equip-map-exit")
            self.passed("equipment-map-exit", "Equipo conservado para el actor y el observador al cruzar un portal",
                        from_map=source_map, to_map=destination)
            self.relocate(store, {1: (1, x, y), 2: (1, x+1, y)})
            for actor in (1, 2):
                equipped = store.hgetall(f"player:{self.ids[actor]}:equipment")
                for kind, slot in equipped.items():
                    self.command(actor, "equip", slot=int(slot))
                    self.wait(lambda: store.hget(f"player:{self.ids[actor]}:equipment", kind) in (None, "0"), "desequipado confirmado")
                    expected[actor]["body" if kind == "armor" else kind] = bases[actor] if kind == "armor" else 0
                    self.see(actor, expected[actor])
            self.passed("equipment-remove", "Retirar equipo se ve en ambas ventanas", removed=True)
            if hasattr(self, "extra_checks"): self.extra_checks(store, locations)
        for viewer in (1, 2): self.command(viewer, "soak")
        return self.steps
