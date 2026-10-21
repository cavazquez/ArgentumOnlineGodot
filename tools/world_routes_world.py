"""Cruces reales por TLS, con actor, observador y Redis descartable."""

import json
import time

from full_world import DIRECTIONS, FullWorld, prepare_fixture

REQUIRED = {"route-outbound", "route-return", "route-interior", "route-same-map", "route-occupied", "route-embark", "route-disembark", "route-no-boat", "route-dead", "route-navigation-skill", "full-sea-exit", "route-door-state", "route-sign-collision", "route-tree-collision"}


def acceptance(steps, _seconds, **_kwargs):
    complete = {row["id"] for row in steps if row.get("passed")}
    return {"test_execution_passed": REQUIRED <= complete, "missing": sorted(REQUIRED - complete), "r10_gameplay_passed": False}


class WorldRoutesWorld(FullWorld):
    def records(self):
        from src.runtime_paths import maps_dir
        from src.services.map.map_resources_service import MapResourcesService

        self.terrain = MapResourcesService()
        self.routes = []
        for path in sorted(maps_dir().glob("transitions_*.json")):
            for line in path.read_text().splitlines():
                row = json.loads(line)
                self.routes.extend((row["from_map"], e["x"], e["y"], e["to_map"], e["to_x"], e["to_y"]) for e in row["exits"])
        self.exits = {row[:3] for row in self.routes}

    def free(self, mid, x, y, water=False):
        t = self.terrain
        return (8 <= x <= 92 and 8 <= y <= 93 and (mid, x, y) not in self.exits
                and t.has_water(mid, x, y) == water and (water or not t.is_blocked(mid, x, y))
                and not t.has_tree(mid, x, y) and not t.has_mine(mid, x, y))

    def pick(self, predicate):
        for row in self.routes:
            a, x, y, b, tx, ty = row
            source_water = self.terrain.has_water(a, x, y)
            target_water = self.terrain.has_water(b, tx, ty)
            if not predicate(row, source_water, target_water): continue
            if self.terrain.is_blocked(b, tx, ty) and not target_water: continue
            for dx, dy in DIRECTIONS:
                start = (x - dx, y - dy)
                if not self.free(a, *start, source_water): continue
                for ox, oy in DIRECTIONS:
                    observer = (tx + ox, ty + oy)
                    if self.free(b, *observer, target_water) and (a != b or observer != start):
                        return row, start, DIRECTIONS[dx, dy], observer
        raise RuntimeError("No existe una ruta real adecuada para el caso solicitado")

    def crossing(self, store, case, selected, *, reject=None, stats=None, items=None):
        row, start, action, observer = selected
        a, x, y, b, tx, ty = row
        water_a = self.terrain.has_water(a, x, y)
        water_b = self.terrain.has_water(b, tx, ty)
        self.data["items"] = {"1": [474, 1], "30": [1, 10]} if items is None else items
        self.data["skills"]["navegacion"] = 100
        self.data["player"].update(sailing=0, boat_slot=1, boat_item=474)
        changes = {1: {"sailing": int(water_a)}, 2: {"sailing": int(water_b)}}
        if stats: changes[1].update(stats)
        self.relocate(store, {1: (a, *start), 2: (b, *( (tx, ty) if reject == "occupied" else observer))}, reset=True, stats=changes)
        before = self.items(store, 1)
        if case == "route-navigation-skill":
            # Disconnected fixture setup is required for skill changes too.
            self.command(1, "logout")
            self.wait(lambda: not store.exists(f"session:{self.ids[1]}:owner"), "salir antes del cambio de habilidad")
            store.hset(f"player:{self.ids[1]}:skills", "level:navegacion", 0)
            self.command(1, "login")
        self.command(1, "move", action=action, seconds=0.07)
        if reject:
            self.console(1, {"occupied": "ocupada", "boat": "embarcación", "dead": "vivo", "skill": "habilidad"}[reject])
            self.view(1, lambda v: (v["map"], v["x"], v["y"]) == (a, *start), "origen conservado tras rechazo")
            actual = store.hgetall(f"player:{self.ids[1]}:position")
            if tuple(int(actual[k]) for k in ("map", "x", "y")) != (a, *start):
                raise RuntimeError("El rechazo alteró la posición persistida")
        else:
            self.view(1, lambda v: (v["map"], v["x"], v["y"]) == (b, tx, ty) and v.get("sailing", False) == water_b, "destino y medio confirmados")
            self.view(2, lambda v: str(self.ids[1]) in v.get("actor_equipment", {}), "actor visible para observador del destino")
            if before != self.items(store, 1): raise RuntimeError("El cruce modificó el inventario/barco")
        for viewer in (1, 2): self.command(viewer, "capture", label=case)
        self.passed(case, source=list(row[:3]), destination=list(row[3:]), rejected=reject, inventory_preserved=True)

    def doors(self, store):
        # The map 111 graphic sits in an isolated outer buffer; never carve a
        # path to make it traversable. The two authored Ullathorpe door halves
        # are the functional case for crossing and reconnecting.
        mid, tx, ty = 1, 48, 65
        starts = [(tx+dx, ty+dy) for dx, dy in DIRECTIONS if (tx+dx, ty+dy) != (49,65) and not self.terrain.is_blocked(mid, tx+dx, ty+dy)]
        start = starts[0]
        observer = next((x, y) for x in range(tx-3, tx+3) for y in range(ty-3, ty+3) if (x, y) not in (start, (tx, ty), (49,65)) and not self.terrain.is_blocked(mid, x, y) and not self.terrain.has_water(mid, x, y))
        self.reset(store, {1: (mid, *start), 2: (mid, *observer)}, items={1: (1, 10)})

        def visible(blocked, graphic):
            for viewer in (1, 2):
                self.wait(lambda: self.command(viewer, "terrain_probe", x=tx, y=ty)["terrain_probe"]["blocked"] == blocked, "misma colisión de puerta en ambos clientes")
                self.wait(lambda: all(self.command(viewer, "loot_probe", x=tx, y=ty, graphic=graphic)["loot_probe"].values()), "mismo gráfico dinámico de puerta")

        visible(True, 5593)
        self.command(1, "click", x=tx, y=ty)
        self.wait(lambda: store.get("door:1:48:65") == "7:1", "puerta abierta en Redis")
        visible(False, 5592)
        delta = (tx-start[0], ty-start[1])
        self.command(1, "step", action=DIRECTIONS[delta])
        self.view(1, lambda v: (v["x"], v["y"]) == (tx, ty), "atravesar la puerta abierta")
        self.command(2, "click", x=tx, y=ty)
        self.console(2, "ocupada")
        self.command(1, "step", action=DIRECTIONS[-delta[0], -delta[1]])
        self.command(2, "click", x=tx, y=ty)
        self.wait(lambda: store.get("door:1:48:65") == "8:0", "cierre tras liberar el paso")
        visible(True, 5593)
        if store.get("door:1:49:65") != "8:0": raise RuntimeError("La otra mitad de la puerta no se confirmó")
        self.command(2, "logout")
        self.wait(lambda: not store.exists(f"session:{self.ids[2]}:owner"), "liberar observador")
        self.command(2, "login")
        visible(True, 5593)
        for viewer in (1, 2): self.command(viewer, "capture", label="door-persisted")
        self.passed("route-door-state", both_clients=True, reconnected=True, cannot_close_on_player=True)

    def obstacles(self, store):
        from src.command_handlers.left_click_tile_handler import _SIGNS_CATALOG
        from src.runtime_paths import data_dir

        review = json.loads((data_dir() / "world/route-repairs.json").read_text())
        for kind in ("sign", "tree"):
            selected = None
            for row in review["collisions"]:
                mid, x, y = row["map"], row["x"], row["y"]
                if row["kind"] != kind or (mid, x, y) in self.exits: continue
                for dx, dy in DIRECTIONS:
                    starts = [(x-dx, y-dy), (x+dx, y+dy)]
                    if all(self.free(mid, *at) for at in starts):
                        selected = mid, x, y, starts
                        break
                if selected: break
            if selected is None: raise RuntimeError("No hay dos aproximaciones reales al obstáculo " + kind)
            mid, x, y, starts = selected
            self.reset(store, {i: (mid, *starts[i-1]) for i in (1, 2)}, items={1: (127, 1), 30: (1, 10)})
            for viewer in (1, 2):
                probe = self.command(viewer, "terrain_probe", x=x, y=y)["terrain_probe"]
                if not probe["blocked"]: raise RuntimeError("El cliente permite atravesar " + kind)
                at = starts[viewer-1]
                # step exige avanzar; aquí acreditamos precisamente el bloqueo
                # mediante Input y luego contrastamos las dos posiciones.
                self.command(viewer, "move", action=DIRECTIONS[x-at[0], y-at[1]], seconds=0.1)
                self.view(viewer, lambda v: (v["map"], v["x"], v["y"]) == (mid, *at), "colisión conserva posición local")
                position = store.hgetall(f"player:{self.ids[viewer]}:position")
                if (int(position["x"]), int(position["y"])) != at: raise RuntimeError("Colisión alteró posición Redis")
                if kind == "sign":
                    graphic = self.terrain.get_sign_at(mid, x, y)
                    text = _SIGNS_CATALOG.get(graphic, {}).get("text", "[Cartel sin texto]")
                    self.command(viewer, "click", x=x, y=y)
                    self.console(viewer, text)
            if kind == "tree":
                self.command(1, "equip", slot=1)
                for _ in range(25):
                    self.attempt(store, 9, x, y)
                    if self.count(store, 1, 58): break
                if not self.count(store, 1, 58): raise RuntimeError("El árbol revisado perdió su recurso talable")
            for viewer in (1, 2): self.command(viewer, "capture", label="collision-" + kind)
            self.passed("route-" + kind + "-collision", map=mid, tile=[x, y], opposite_approaches=True, interaction=True)

    def run(self, locations):
        self.deadline = time.monotonic() + 1800
        self.wait(lambda: all("INTEGRATION_WORLD: READY" in (self.output / f"godot-{i}.log").read_text() for i in (1, 2)), "dos clientes TLS", 60)
        self.records()
        with self.fixture.client() as store:
            self.ids = {i: int(store.hget(f"account:{self.names[i-1]}:data", "user_id")) for i in (1, 2)}
            outbound = self.pick(lambda r, a, b: r[0] != r[3] and not a and not b and (r[1] <= 9 or r[1] >= 92))
            self.crossing(store, "route-outbound", outbound)
            self.crossing(store, "route-return", self.pick(lambda r, a, b: (r[0], r[3]) == (outbound[0][3], outbound[0][0]) and not a and not b))
            self.crossing(store, "route-occupied", outbound, reject="occupied")
            self.crossing(store, "route-interior", self.pick(lambda r, a, b: r[0] != r[3] and 12 < r[1] < 89 and 10 < r[2] < 91 and not a and not b))
            self.crossing(store, "route-same-map", self.pick(lambda r, a, b: r[0] == r[3] and not a and not b and r[1:3] != r[4:6]))
            embark = self.pick(lambda _r, a, b: not a and b)
            self.crossing(store, "route-no-boat", embark, reject="boat", items={"30": [1, 10]})
            self.crossing(store, "route-dead", embark, reject="dead", stats={"min_hp": 0})
            self.crossing(store, "route-navigation-skill", embark, reject="skill")
            self.crossing(store, "route-embark", embark)
            self.crossing(store, "route-disembark", self.pick(lambda _r, a, b: a and not b))
            self.sea_exit(store, locations)
            self.doors(store)
            self.obstacles(store)
            _, x, y = locations["skills_base"]
            self.reset(store, {1: (2, x, y), 2: (2, x+1, y)}, items={1: (1, 10)})
        for index in (1, 2): self.command(index, "soak")
        return self.steps
