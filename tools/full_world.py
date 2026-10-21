"""Campaña gráfica de la fase: R10, 22 habilidades, magia bidireccional y mar.

Sólo prepara posiciones/recursos con las cuentas desconectadas. Toda actividad
que se acredita se ejecuta después mediante los dos clientes Godot reales.
"""

from collections import deque
import hashlib
import json
from pathlib import Path
import time
import shutil
import subprocess
import sys
import secrets

from r10_world import R10World
from full_evidence import acceptance
from skills_world import (
    MechanicsWorld as SkillsWorld,
    prepare_fixture as skills_fixture,
)
from mechanics_world import MechanicsWorld as SpellWorld, SPELLS

DIRECTIONS = {
    (1, 0): "ui_right",
    (-1, 0): "ui_left",
    (0, 1): "ui_down",
    (0, -1): "ui_up",
}


def water_path(water, start, goal):
    queue = deque([tuple(start)])
    parents = {tuple(start): None}
    while queue:
        at = queue.popleft()
        if goal(at):
            result = []
            while at is not None:
                result.append(at)
                at = parents[at]
            return list(reversed(result))
        for dx, dy in DIRECTIONS:
            other = at[0] + dx, at[1] + dy
            if (
                other in water
                and other not in parents
                and 8 <= other[0] <= 92
                and 8 <= other[1] <= 92
            ):
                parents[other] = at
                queue.append(other)
    return None


def prepare_fixture(work, output):
    from src.services.map.map_resources_service import MapResourcesService
    from src.services.fishing_zones import FishingZones

    target, locations = skills_fixture(work, output)
    from lifetime_stats_world import add_stats_npc
    add_stats_npc(target, locations)
    terrain = MapResourcesService()
    zones = FishingZones(terrain)
    exit_tiles = {}
    for chunk in sorted(terrain.maps_dir.glob("transitions_*.json")):
        for line in chunk.read_text().splitlines():
            if not line.strip():
                continue
            row = json.loads(line)
            exit_tiles.setdefault(int(row["from_map"]), set()).update(
                (int(e["x"]), int(e["y"])) for e in row.get("exits", [])
            )
    sea = None
    for mid in sorted(zones.sea_maps):
        rows = terrain.resources.get(f"map_{mid}", {})
        water = rows.get("water", set())
        blocked = rows.get("blocked", set())
        navigable = water - exit_tiles.get(mid, set())
        coasts = []
        for wx, wy in sorted(navigable):
            if not 9 <= wx <= 91 or not 9 <= wy <= 91:
                continue
            for dx, dy in DIRECTIONS:
                land = wx + dx, wy + dy
                if (
                    land not in water | blocked | exit_tiles.get(mid, set())
                    and 9 <= land[0] <= 91
                    and 9 <= land[1] <= 91
                ):
                    coasts.append((land, (wx, wy)))
        for coast, entry in coasts:
            zones.classify((mid, *entry))
            path = water_path(
                navigable,
                entry,
                lambda t: zones.classify((mid, *t))[0] == "mar adentro",
            )
            if not path:
                continue
            other = next(
                (
                    (a, b)
                    for a, b in coasts
                    if a != coast
                    and b != entry
                    and abs(a[0] - coast[0]) + abs(a[1] - coast[1]) < 8
                ),
                None,
            )
            if other:
                second = water_path(
                    navigable - {path[-1]},
                    other[1],
                    lambda t: (
                        zones.classify((mid, *t))[0] == "mar adentro"
                        and abs(t[0] - path[-1][0]) + abs(t[1] - path[-1][1]) <= 2
                    ),
                )
                if second:
                    sea = {
                        "map": mid,
                        "coast": [coast, other[0]],
                        "paths": [path, second],
                    }
                    break
        if sea:
            break
    if sea is None:
        raise RuntimeError(
            "El dataset propio no ofrece costa y mar adentro navegables para ambos jugadores"
        )
    locations["sea"] = sea
    exits = []
    for chunk in sorted(terrain.maps_dir.glob("transitions_*.json")):
        for line in chunk.read_text().splitlines():
            if not line.strip():
                continue
            row = json.loads(line)
            m = int(row["from_map"])
            for e in row.get("exits", []):
                a = (int(e["x"]), int(e["y"]))
                b = (int(e["to_x"]), int(e["to_y"]))
                dest = int(e["to_map"])
                if not terrain.has_water(m, *a) or not terrain.has_water(dest, *b):
                    continue
                start = next(
                    (
                        (a[0] + dx, a[1] + dy)
                        for dx, dy in DIRECTIONS
                        if terrain.has_water(m, a[0] + dx, a[1] + dy)
                        and 8 <= a[0] + dx <= 92
                        and 8 <= a[1] + dy <= 92
                    ),
                    None,
                )
                observer = next(
                    (
                        (b[0] + dx, b[1] + dy)
                        for dx, dy in DIRECTIONS
                        if terrain.has_water(dest, b[0] + dx, b[1] + dy)
                        and 8 <= b[0] + dx <= 92
                        and 8 <= b[1] + dy <= 92
                    ),
                    None,
                )
                if start and observer:
                    exits.append(
                        {
                            "from": m,
                            "start": start,
                            "tile": a,
                            "to": dest,
                            "landing": b,
                            "observer": observer,
                        }
                    )
    if not exits:
        raise RuntimeError("No hay salida acuática real verificable")
    locations["sea_exit"] = exits[0]
    (output / "full-fixture.json").write_text(
        json.dumps(
            {k: v for k, v in locations.items() if not k.startswith("_")},
            indent=2,
            default=list,
        )
        + "\n"
    )
    return target, locations


class FullWorld(SkillsWorld):
    _reverse = False

    def command(self, index, op, **values):
        return super().command(3 - index if self._reverse else index, op, **values)

    def passed(self, key, requirement="", **observations):
        self.steps.append(
            {
                "id": key,
                "requirement": requirement,
                "passed": True,
                "test_executed": True,
                "observations": observations,
            }
        )
        self.save()
        print("FULL_WORLD: PASS", key, flush=True)

    def save(self):
        super().save()
        (self.output / "full-actions.json").write_text(
            json.dumps(self.receipts, indent=2) + "\n"
        )
        (self.output / "full-scenarios.json").write_text(
            json.dumps(self.steps, indent=2) + "\n"
        )

    def both_screens(self, label):
        for i in (1, 2):
            self.screen(label, i)

    def run(self, locations):
        # Composición: el baseline conserva su clase y no invoca overrides de habilidades.
        baseline = R10World(
            self.fixture, self.work, self.output, self.names, self.clients, self.server
        )
        baseline.restart_server = self.restart_server
        baseline.run(locations, soak=False)
        for name in ("ids", "targets", "sequences", "receipts", "steps"):
            setattr(self, name, getattr(baseline, name))
        self.deadline = time.monotonic() + 7200
        with self.fixture.client() as store:
            _, x, y = locations["skills_base"]
            self.base = {1: (2, x, y), 2: (2, x, y + 2)}
            births = {i: self.skill_state(store, i) for i in (1, 2)}
            self.manual_all(store, births)
            self.gathering(store, locations)
            self.crafting(store, locations)
            self.meditation_and_magic(store, x, y)
            self.physical(store, x, y)
            self.personal(store, x, y)
            self.thief_objects(store, x + 4, y)
            self.leadership(store, locations)
            self.level_and_reconnect(store, locations)
            self.extra_mana(store)
            self.pvp_both(store, x + 4, y)
            self.boats(store, locations)
            self.sea_exit(store, locations)
            self.ui_checks(store, x + 4, y)
            from lifetime_stats_world import exercise as lifetime_statistics
            lifetime_statistics(self, store, locations)
            # Las capturas de condena dejan estadísticas abiertas. Cerrar el
            # modal antes del chat que libera mascotas para el catálogo mágico.
            for i in (1, 2):
                self.command(i, "close_mechanics")
                self.view(i, lambda v: "StatsWindow" not in v.get("modals", []),
                          "estadísticas cerradas antes del catálogo de hechizos")
            self.initial_points = int(self.skill_state(store).get("points", 0))
            for reverse, label in [(False, "a-to-b"), (True, "b-to-a")]:
                if reverse:
                    self._reverse = True
                    self.ids = {1: self.ids[2], 2: self.ids[1]}
                    self.names = list(reversed(self.names))
                SpellWorld.spells(self, store)
                records = json.loads((self.output / "spells.json").read_text())
                if len(records) != len(SPELLS):
                    raise RuntimeError("Catálogo de hechizos incompleto en " + label)
                evidence = self.output / ("spells-" + label)
                evidence.mkdir(exist_ok=True)
                for source in self.output.iterdir():
                    if source.is_file() and (
                        source.name.startswith("spell") or source.suffix == ".png"
                    ):
                        shutil.copy2(source, evidence / source.name)
                self.both_screens("spells-" + label)
                self.passed(
                    "spells-" + label,
                    catalog_count=len(records),
                    result_file="spells-" + label + "/spells.json",
                )
                # El último caso invoca una mascota. Liberarla antes de cambiar
                # emisor evita que siga al objetivo e intervenga en la otra tanda.
                for _ in range(10):
                    remaining = len(self.pets(store))
                    if not remaining:
                        break
                    self.command(1, "chat", text="/PET LIBERAR")
                    self.wait(
                        lambda: len(self.pets(store)) < remaining,
                        "liberar invocaciones al cambiar emisor",
                    )
                if self.pets(store):
                    raise RuntimeError("Quedaron invocaciones del emisor anterior")
                if reverse:
                    self._reverse = False
                    self.ids = {1: self.ids[2], 2: self.ids[1]}
                    self.names = list(reversed(self.names))
            self.base = {1: (2, x + 4, y), 2: (2, x + 4, y + 2)}
            self.reset(store)
            saved = {
                i: {"items": self.items(store, i), "skills": self.skill_state(store, i)}
                for i in (1, 2)
            }
            for i in (1, 2):
                self.command(i, "logout")
                self.wait(
                    lambda i=i: not store.exists(f"session:{self.ids[i]}:owner"),
                    "liberar sesión final",
                )
                self.command(i, "login")
                self.view(i, lambda v: v.get("in_game", False), "reconexión final")
                if (
                    self.items(store, i) != saved[i]["items"]
                    or self.skill_state(store, i) != saved[i]["skills"]
                ):
                    raise RuntimeError("Reconexión alteró inventario o progreso")
            self.both_screens("full-final")
            self.passed("full-reconnect", preserved=True)
            self.benchmark(store)
            for i in (1, 2):
                self.command(i, "soak")
        return self.steps

    def extra_mana(self, store):
        self.reset(
            store, items={1: (37, 4)}, stats={"min_mana": 1000}, skills={"meditar": 100}
        )
        recoveries = []
        for i in (1, 2):
            before = self.stats(store, i)["min_mana"]
            count = self.count(store, i, 37)
            self.command(i, "use", slot=1)
            self.wait(
                lambda i=i: self.stats(store, i)["min_mana"] > before,
                "poción de maná real",
            )
            if self.count(store, i, 37) != count - 1:
                raise RuntimeError("Poción sin consumo exacto")
            start = self.stats(store, i)["min_mana"]
            started = time.monotonic()
            self.command(i, "chat", text="/meditar")
            self.view(
                i,
                lambda v: "Meditando" in v.get("status_text", ""),
                "meditación activada en la interfaz",
            )
            self.wait(
                lambda i=i: (
                    float(
                        store.hget(f"player:{self.ids[i]}:user_stats", "meditation_due")
                        or 0
                    )
                    > 0
                ),
                "reloj de meditación activo",
            )
            self.wait(
                lambda i=i: self.stats(store, i)["min_mana"] > start,
                "recuperación probabilística de meditación",
                240,
            )
            recoveries.append(
                {
                    "client": i,
                    "before": start,
                    "after": self.stats(store, i)["min_mana"],
                    "seconds": time.monotonic() - started,
                }
            )
            self.command(i, "chat", text="/meditar")
        self.both_screens("mana-recovered")
        self.passed(
            "full-mana", potion=True, meditation=True, both=True, recoveries=recoveries
        )

    def thief_objects(self, store, x, y):
        self.reset(
            store,
            {1: (2, x, y), 2: (2, x + 1, y)},
            items={1: (15, 1), 2: (58, 3)},
            stats={"class_id": 5, "gold": 0},
        )
        self.command(2, "equip", slot=1)
        before = sum(self.count(store, i, 58) for i in (1, 2))
        for _ in range(35):
            self.attempt(store, 2, x + 1, y)
            if self.count(store, 1, 58) > 3:
                break
        if self.count(store, 1, 58) <= 3:
            raise RuntimeError("El ladrón no robó un objeto permitido")
        if sum(self.count(store, i, 58) for i in (1, 2)) != before:
            raise RuntimeError("Robo no conservó los objetos")
        if store.hget(f"player:{self.ids[2]}:inventory", "slot_1") != "15:1":
            raise RuntimeError("Se robó equipo protegido")
        self.both_screens("thief-item-theft")
        self.passed("full-thief", protected_equipment=True, objects_conserved=True)

    def pvp_both(self, store, x, y):
        self.reset(
            store,
            {1: (2, x, y), 2: (2, x + 1, y)},
            items={1: (15, 1)},
            stats={"class_id": 5},
        )
        for i in (1, 2):
            self.command(i, "equip", slot=1)
        for i, heading in [(1, 2), (2, 4)]:
            victim = 3 - i
            before = self.stats(store, victim)["min_hp"]
            self.command(i, "face", heading=heading)
            for _ in range(25):
                self.command(i, "attack")
                if self.stats(store, victim)["min_hp"] < before:
                    break
                time.sleep(0.55)
            if self.stats(store, victim)["min_hp"] >= before:
                raise RuntimeError("PvP no dañó a la víctima")
            self.view(victim, lambda v: v["hp"] < before, "HP PvP en la víctima")
        # Los casts concurrentes no pueden compartir un último emisor global.
        self.reset(store, {1: (2, x, y), 2: (2, x + 1, y)}, stats={"class_id": 1})
        for i in (1, 2):
            self.command(i, "capture_reset", label="simultaneous")
        self.command(1, "cast", slot=2, x=x + 1, y=y)
        self.command(2, "cast", slot=2, x=x, y=y)
        for i in (1, 2):
            self.view(
                i,
                lambda v: (
                    len(
                        {
                            int(p["source"])
                            for p in v.get("fx_packets", [])
                            if p.get("kind") == "projectile" and p.get("valid")
                        }
                    )
                    >= 2
                ),
                "proyectiles con dos emisores distintos",
            )
        self.both_screens("pvp-both")
        self.pvp_lifecycle(store, x, y)
        self.passed(
            "full-pvp", both=True, simultaneous_casts=True, death_and_revive=True
        )

    def pvp_lifecycle(self, store, x, y):
        positions = {1: (2, x, y), 2: (2, x + 1, y)}
        self.reset(store, positions, items={1: (659, 1)}, stats={"gold": 1000})

        def seed():
            store.hset(f"player:{self.ids[2]}:user_stats", "min_hp", "1")
            store.hset(f"player:{self.ids[1]}:spellbook", "4", "11")

        self.offline(store, positions, seed)
        appearance = self.command(2, "snapshot")["appearance"]
        self.command(1, "equip", slot=1)
        self.view(
            1,
            lambda v: v["items"].get("1", []) == [659, 1, True],
            "bastón para resucitar al compañero",
        )
        self.command(1, "cast", slot=2, x=x + 1, y=y)
        self.wait(lambda: self.stats(store, 2)["min_hp"] <= 0, "muerte causada por PvP")
        dead = self.view(
            2,
            lambda v: v["hp"] <= 0 and "Muerto" in v.get("status_text", ""),
            "muerte PvP en la víctima",
        )
        self.view(
            1,
            lambda v: (
                v["world_characters"].get(str(self.ids[2]), [0, 0, 0])[2]
                == dead["appearance"][0]
            ),
            "apariencia muerta en el atacante",
        )
        self.both_screens("pvp-death")
        self.command(1, "cast", slot=4, x=x + 1, y=y)
        self.wait(
            lambda: self.stats(store, 2)["min_hp"] > 0,
            "resurrección del compañero por hechizo",
        )
        self.view(
            2,
            lambda v: (
                v["hp"] > 0
                and v["appearance"] == appearance
                and "Muerto" not in v.get("status_text", "")
            ),
            "vida y apariencia restauradas en la víctima",
        )
        self.view(
            1,
            lambda v: (
                v["world_characters"].get(str(self.ids[2]), [0, 0, 0])[2]
                == appearance[0]
            ),
            "resurrección visible para el lanzador",
        )
        self.both_screens("pvp-revival")

    def follow(self, store, index, map_id, path):
        for start, end in zip(path, path[1:]):
            action = DIRECTIONS[(end[0] - start[0], end[1] - start[1])]
            self.command(index, "step", action=action)
            try:
                self.wait(
                    lambda: (
                        (p := store.hgetall(f"player:{self.ids[index]}:position"))
                        and (int(p["map"]), int(p["x"]), int(p["y"])) == (map_id, *end)
                    ),
                    "paso de navegación confirmado",
                    8,
                )
            except TimeoutError as error:
                actual = store.hgetall(f"player:{self.ids[index]}:position")
                view = self.command(index, "snapshot")
                raise RuntimeError(
                    f"Navegación {map_id}: {start}->{end}, Redis={actual}, UI={(view.get('map'), view.get('x'), view.get('y'))}, consola={view.get('console')}"
                ) from error

    def boats(self, store, locations):
        sea = locations["sea"]
        mid = sea["map"]
        paths = sea["paths"]
        coasts = sea["coast"]
        positions = {i: (mid, *coasts[i - 1]) for i in (1, 2)}
        self.reset(store, positions, items={1: (474, 1), 2: (563, 1)})
        before_navigation = self.skill_state(store)
        captures = {}
        for i in (1, 2):
            self.command(i, "use", slot=1)
            self.view(i, lambda v: v.get("sailing", False), "barco confirmado")
            self.follow(store, i, mid, [coasts[i - 1], *paths[i - 1]])
            self.command(i, "equip", slot=2)
            target = paths[i - 1][-1]
            before = sum(self.count(store, i, item) for item in (139, 544, 545, 546))
            before_golden = self.count(store, i, 544)
            for _ in range(60):
                console_count = self.command(i, "snapshot")["server_console_count"]
                self.command(i, "ability", skill=12)
                self.command(i, "work", skill=12, x=target[0], y=target[1])
                self.view(
                    i,
                    lambda v: v["server_console_count"] > console_count,
                    "resultado publicado del intento de pesca",
                )
                now = sum(self.count(store, i, item) for item in (139, 544, 545, 546))
                if now > before and self.count(store, i, 544) > before_golden:
                    break
            if now <= before:
                raise RuntimeError("Pesca de mar adentro sin captura")
            if self.count(store, i, 544) <= before_golden:
                raise RuntimeError(
                    "No se observó pescado dorado mar adentro en la muestra acotada"
                )
            captures[i] = self.items(store, i)
            self.command(i, "logout")
            self.wait(
                lambda i=i: not store.exists(f"session:{self.ids[i]}:owner"),
                "salir navegando",
            )
            self.command(i, "login")
            self.view(i, lambda v: v.get("sailing", False), "reconectar en barco")
            if captures[i] != self.items(store, i):
                raise RuntimeError("Captura perdida al reconectar")
        self.both_screens("boats-deep-sea")
        self.passed(
            "full-fishing-zones", captures=captures, coast_scenario="fish", deep_sea=mid
        )
        for i in (1, 2):
            self.follow(store, i, mid, list(reversed(paths[i - 1])))
            self.command(i, "use", slot=1)
            self.view(i, lambda v: not v.get("sailing", True), "desembarcar en costa")
            self.follow(store, i, mid, [paths[i - 1][0], coasts[i - 1]])
        self.both_screens("boats-disembark")
        self.passed(
            "full-navigation",
            both=True,
            steps=[len(p) for p in paths],
            reconnected=True,
        )
        self.proof(store, 20, before_navigation, both=True, reconnected=True)

    def sea_exit(self, store, locations):
        e = locations["sea_exit"]
        self.reset(
            store,
            {1: (e["from"], *e["start"]), 2: (e["to"], *e["observer"])},
            items={1: (474, 1)},
            stats={"sailing": 1, "boat_slot": 1, "boat_item": 474},
        )
        dx, dy = e["tile"][0] - e["start"][0], e["tile"][1] - e["start"][1]
        self.command(1, "step", action=DIRECTIONS[(dx, dy)])
        self.view(
            1,
            lambda v: v["map"] == e["to"] and v.get("sailing", False),
            "transición marítima real",
        )
        self.both_screens("boats-map-exit")
        self.passed("full-sea-exit", from_map=e["from"], to_map=e["to"])

    def ui_checks(self, store, x, y):
        self.reset(
            store, {1: (2, x, y), 2: (2, x + 1, y)}, items={1: (139, 2), 2: (37, 2)}
        )
        for i in (1, 2):
            self.command(i, "ui_phase", action="layout")
            self.command(i, "ui_phase", action="keyboard_flows")
            self.command(i, "ui_phase", action="resize", width=1920, height=1080)
            self.command(i, "ui_phase", action="ping")
            self.view(i, lambda v: " ms" in v.get("ping_status", ""), "latencia medida")
            self.command(i, "ui_phase", action="map")
            self.screen("world-map", i)
            self.command(i, "close_mechanics")
            self.command(i, "ui_phase", action="options")
            self.screen("options-1080p", i)
            self.command(i, "close_mechanics")
            view = self.command(i, "snapshot")
            if "Pescado" not in view.get("tooltip", ""):
                raise RuntimeError("Tooltip de captura ausente")
            self.command(i, "drag", source=1, destination=3)
            self.wait(
                lambda i=i: (
                    store.hget(f"player:{self.ids[i]}:inventory", "slot_3") == "139:2"
                ),
                "reordenar inventario en 1080p",
            )
            self.view(
                i,
                lambda v: v["items"].get("3", [])[:2] == [139, 2],
                "primer arrastre visible antes de mover de nuevo",
            )
            self.command(i, "drag", source=3, destination=1)
            self.wait(
                lambda i=i: (
                    store.hget(f"player:{self.ids[i]}:inventory", "slot_1") == "139:2"
                ),
                "restaurar orden en 1080p",
            )
            self.view(
                i,
                lambda v: v["items"].get("1", [])[:2] == [139, 2],
                "orden restaurado en la interfaz",
            )
            victim = 3 - i
            hp = self.stats(store, victim)["min_hp"]
            self.command(i, "cast", slot=2, x=x + 1 if victim == 2 else x, y=y)
            self.wait(
                lambda victim=victim: self.stats(store, victim)["min_hp"] < hp,
                "objetivo de hechizo tras redimensionar a 1080p",
            )
            self.command(i, "ui_phase", action="resize", width=800, height=1000)
            self.screen("hud-portrait", i)
            self.command(i, "ui_phase", action="resize", width=800, height=600)
            self.screen("hud-classic", i)
        self.passed(
            "full-ui",
            sizes=[[800, 600], [1920, 1080], [800, 1000]],
            tooltips=True,
            ping=True,
            world_map=True,
            scaled_spell_target=True,
            inventory_reorder=True,
        )

    def benchmark(self, store, *, slow_readers=1, report_name="benchmark.json"):
        for i in (1, 2):
            self.command(i, "logout")
            self.wait(
                lambda i=i: not store.exists(f"session:{self.ids[i]}:owner"),
                "sesión libre para carga",
            )
        slow = "Slow" + secrets.token_hex(4)
        self.command(1, "create", name=slow, job=1, race=1, gender=1, home=1)
        self.command(1, "logout")
        slow_id = int(store.hget(f"account:{slow}:data", "user_id"))
        self.wait(
            lambda: not store.exists(f"session:{slow_id}:owner"), "lector lento libre"
        )
        credentials = self.work / "benchmark-accounts.json"
        credentials.write_text(
            json.dumps(
                [
                    {"username": n, "password": self.benchmark_password}
                    for n in [*self.names, slow]
                ]
            )
        )
        credentials.chmod(0o600)
        command = [
            sys.executable,
            "-m",
            "tools.benchmark",
            "--accounts",
            str(credentials),
            "--connections",
            "2",
            "--slow-readers",
            str(slow_readers),
            "--seconds",
            "30",
            "--host",
            "127.0.0.1",
            "--port",
            str(self.server_port),
            "--pid",
            str(self.server.pid),
            "--ca",
            str(self.work / "test-ca.crt"),
            "--metrics",
            str(self.output / "server-ticks.json"),
            "--output",
            str(self.output / report_name),
            "--max-p95-ms",
            "1000",
            "--max-login-ms",
            "5000",
        ]
        try:
            subprocess.run(command, check=True, timeout=90)
        finally:
            credentials.unlink(missing_ok=True)
        report = json.loads((self.output / report_name).read_text())
        if not report["passed"] or not report["tick_after"]:
            raise RuntimeError("Carga o tick real sin evidencia válida")
        cpu = (
            Path("/proc/cpuinfo").read_text() if Path("/proc/cpuinfo").exists() else ""
        )
        memory = (
            Path("/proc/meminfo").read_text() if Path("/proc/meminfo").exists() else ""
        )
        report["hardware"] = {
            "cpu_model": next(
                (
                    line.split(":", 1)[1].strip()
                    for line in cpu.splitlines()
                    if line.startswith("model name")
                ),
                "no disponible",
            ),
            "ram_bytes": next(
                (
                    int(line.split()[1]) * 1024
                    for line in memory.splitlines()
                    if line.startswith("MemTotal:")
                ),
                None,
            ),
        }
        sources = [self.output / name for name in ("wheel-source.json", "server-source.json")]
        if not any(path.is_file() for path in sources):
            raise RuntimeError("Benchmark sin manifiesto de las fuentes del servidor")
        report["dataset"] = {
            path.name: hashlib.sha256(path.read_bytes()).hexdigest()
            for path in (
                self.output / "full-fixture.json",
                self.output / "wheel-source.json",
                self.output / "server-source.json",
                self.output / "client-source.json",
            )
            if path.is_file()
        }
        (self.output / report_name).write_text(json.dumps(report, indent=2) + "\n")
        for i in (1, 2):
            self.command(i, "login")
        self.both_screens("recovered-after-load")
        self.passed(
            "full-benchmark", connections=2, slow_readers=slow_readers, report=report_name
        )
