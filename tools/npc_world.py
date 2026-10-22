"""Muestra breve de NPC con dos Godot, sin sustituir los spawns del mundo.

Sólo prepara posiciones y salud de cuentas efímeras desconectadas. El catálogo,
las zonas y el comportamiento de los NPC permanecen intactos. No es la campaña
prolongada de jugabilidad ni demuestra que funcionen voces ausentes del catálogo.
"""

import hashlib
import json
import time
import tomllib

from r10_world import R10World

REQUIRED = {"npc-identities", "npc-reconnect", "npc-map-transition", "npc-service-interaction", "npc-hostile-visual"}


def acceptance(steps, seconds, *, graphical, **_):
    completed = {step["id"] for step in steps if step.get("passed") is True}
    missing = sorted(REQUIRED - completed)
    return {"required": sorted(REQUIRED), "missing": missing,
            "test_execution_passed": not missing and graphical,
            "r10_gameplay_passed": False, "npc_sounds_in_live_catalog_proven": False}


def representation_differences(expected, actual, player, update_range):
    """Identidad/apariencia global; posición sólo donde el protocolo la actualiza."""
    result = []
    for key in sorted(expected.keys() | actual.keys()):
        want, have = expected.get(key), actual.get(key)
        if want is None or have is None or want[2:] != have[2:]:
            result.append({"char_index": key, "expected": want, "actual": have})
            continue
        near = any(max(abs(pose[0] - player[0]), abs(pose[1] - player[1])) <= update_range for pose in (want, have))
        if near and want[:2] != have[:2]:
            result.append({"char_index": key, "expected": want, "actual": have})
    return result


def prepare_fixture(work, output):
    from src.core.server_initializer import ServerInitializer
    from src.game.map_manager import MapManager
    from src.runtime_paths import data_dir

    manager = MapManager()
    ServerInitializer._load_map_tiles(manager)
    with (data_dir() / "world/map_npcs.toml").open("rb") as file:
        spawns = {int(key): row for key, row in tomllib.load(file)["map_npcs"].items()}
    occupied = {(m, p["x"], p["y"]) for m, row in spawns.items() for p in row.get("spawn_points", [])}

    def clear(map_id, x, y):
        return (manager.can_move_to(map_id, x, y) and (map_id, x, y) not in occupied
                and manager.get_exit_tile(map_id, x, y) is None)

    base = next((x, y) for y in range(53, 60) for x in range(50, 57)
                if all(clear(1, x + dx, y + dy) for dx in range(3) for dy in range(3)))
    exit_sample = None
    for (map_id, x, y), destination in sorted(manager._exit_tiles.items()):
        if map_id != 1:
            continue
        for dx, dy, action in ((0, 1, "ui_up"), (1, 0, "ui_left"), (-1, 0, "ui_right"), (0, -1, "ui_down")):
            if clear(1, x + dx, y + dy) and manager.can_move_to(1, x, y):
                exit_sample = (1, x + dx, y + dy, action, destination["to_map"])
                break
        if exit_sample:
            break
    if not exit_sample:
        raise RuntimeError("El dataset no permite la muestra de transición")
    return data_dir(), {"base": base, "exit": exit_sample,
                        "spawn_sha256": hashlib.sha256((data_dir() / "world/map_npcs.toml").read_bytes()).hexdigest()}


class NPCWorld(R10World):
    def current(self, store, map_id):
        return [row for instance in store.smembers(f"npc:map:{map_id}")
                if (row := store.hgetall(f"npc:instance:{instance}"))]

    def represented(self, store, index, map_id):
        def matches(view):
            if view.get("map") != map_id:
                return False
            expected = {row["char_index"]: [int(row[k]) for k in ("x", "y", "body_id", "head_id")]
                        for row in self.current(store, map_id)}
            actual = {key: value for key, value in view.get("world_characters", {}).items() if int(key) >= 10001}
            differences = representation_differences(expected, actual, (view["x"], view["y"]), self.update_range)
            for row in self.current(store, map_id):
                key = row["char_index"]
                label = view.get("actor_visibility", {}).get(key, {})
                visible = (row.get("role", "inhabitant") in {"inhabitant", "guard"}
                           and row.get("is_hostile", "False") == "False"
                           and row.get("is_tamed", "False") == "False"
                           and row.get("summoned_by_user_id", "0") == "0")
                if label.get("name") != row["name"] or label.get("name_visible") != visible:
                    differences.append({"char_index": key, "name": row["name"],
                                        "expected_name_visible": visible, "actual_label": label})
            (self.output / f"npc-difference-{index}.json").write_text(json.dumps({
                "map_id": map_id, "expected_count": len(expected), "actual_count": len(actual),
                "update_range": self.update_range, "differences": differences,
                "offscreen_positions_follow_last_received_packet": True,
            }, indent=2) + "\n")
            return not differences
        return self.view(index, matches, f"NPC autoritativos del mapa {map_id}")

    def hostile_sample(self, store, health):
        from src.core.server_initializer import ServerInitializer
        from src.game.map_manager import MapManager

        manager = MapManager()
        ServerInitializer._load_map_tiles(manager)
        rows = self.current(store, 1)
        target = next(row for row in rows if row["npc_id"] == "536")
        nx, ny = int(target["x"]), int(target["y"])
        occupied = {(int(row["x"]), int(row["y"])) for row in rows}
        clear = [(x, y) for y in range(ny - 3, ny + 4) for x in range(nx - 3, nx + 4)
                 if manager.can_move_to(1, x, y) and (x, y) not in occupied
                 and manager.get_exit_tile(1, x, y) is None]
        if len(clear) < 2:
            raise RuntimeError("No hay acceso a la criatura de la muestra")
        self.relocate(store, {i: (1, *clear[i - 1]) for i in (1, 2)}, stats=health)
        for i in (1, 2):
            self.represented(store, i, 1)
            key = target["char_index"]
            self.view(i, lambda v: key in v.get("actor_visibility", {}) and
                      v["actor_visibility"][key]["renderer_visible"] and
                      v["actor_visibility"][key]["visible_in_tree"] and
                      abs(v["world_characters"][key][0] - v["x"]) <= 8 and
                      abs(v["world_characters"][key][1] - v["y"]) <= 5,
                      "criatura hostil visible junto al jugador")
            self.command(i, "capture", label="npc-hostile")
        self.passed("npc-hostile-visual", "Criatura hostil real visible en dos clientes", npc_id=536, instance_id=target["instance_id"], char_index=target["char_index"])

    def run(self, locations):
        from src.services.multiplayer_broadcast_service import MultiplayerBroadcastService
        self.update_range = MultiplayerBroadcastService.VISIBLE_RANGE
        self.deadline = time.monotonic() + 500
        self.wait(lambda: all("INTEGRATION_WORLD: READY" in (self.output / f"godot-{i}.log").read_text() for i in (1, 2)), "dos clientes listos", 90)
        with self.fixture.client() as store:
            self.ids = {i: int(store.hget(f"account:{self.names[i - 1]}:data", "user_id")) for i in (1, 2)}
            x, y = locations["base"]
            positions = {1: (1, x, y), 2: (1, x + 1, y)}
            health = {i: {"min_hp": 30000, "max_hp": 30000} for i in (1, 2)}
            self.relocate(store, positions, stats=health)
            for i in (1, 2):
                self.represented(store, i, 1)
                self.command(i, "capture", label="npc-world")
            rows = self.current(store, 1)
            assert any(row["is_hostile"] == "True" for row in rows)
            assert any(row["is_hostile"] == "False" for row in rows)
            self.passed("npc-identities", "Amistosos y hostiles: posición y apariencia desde Redis", instances=[{k: row[k] for k in ("instance_id", "char_index", "npc_id", "is_hostile")} for row in rows], clients=2)
            self.relocate(store, {1: positions[1]}, stats=health)
            self.represented(store, 1, 1)
            self.passed("npc-reconnect", "Reconexión conserva el mundo y no duplica NPC")
            merchant = next(row for row in self.current(store, 1) if row["npc_id"] == "2")
            self.command(1, "click", x=int(merchant["x"]), y=int(merchant["y"]))
            self.view(1, lambda v: v.get("panel") == "merchant", "interacción comercial del NPC real")
            self.command(1, "close")
            self.passed("npc-service-interaction", "Comerciante configurado abre su interfaz real")
            old = set(self.command(1, "snapshot")["world_characters"])
            map_id, ex, ey, action, destination = locations["exit"]
            self.relocate(store, {1: (map_id, ex, ey)}, stats=health)
            self.command(1, "step", action=action)
            self.view(1, lambda v: v.get("map") == destination, "transición de mapa por entrada real")
            view = self.represented(store, 1, destination)
            old_npcs = {key for key in old if int(key) >= 10001}
            assert not old_npcs.intersection(view["world_characters"])
            self.command(1, "capture", label="npc-map-change")
            self.passed("npc-map-transition", "El cambio de mapa retira los NPC anteriores", destination=destination)
            self.hostile_sample(store, health)
            self.relocate(store, positions, stats=health)
            for i in (1, 2):
                self.represented(store, i, 1)
                self.command(i, "capture", label="npc-reconnected")
            from src.runtime_paths import data_dir
            digest = hashlib.sha256((data_dir() / "world/map_npcs.toml").read_bytes()).hexdigest()
            assert digest == locations["spawn_sha256"]
            for i in (1, 2):
                self.command(i, "soak")
        return self.steps
