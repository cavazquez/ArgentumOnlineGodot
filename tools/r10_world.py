"""Escenarios R10: acciones por Godot y aserciones independientes en Redis propio.

Este módulo no acepta endpoints externos. Lo crea integration-world.py dentro
de su sandbox y sólo prepara fixtures mientras las cuentas están desconectadas.
No llama a servicios de juego para ejecutar las acciones que debe acreditar.
"""

import hashlib
import json
import shutil
import time
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REQUIRED_SCENARIOS = {
    "inventory",
    "bank",
    "merchant",
    "trade_complete",
    "trade_cancel",
    "party",
    "clan",
    "magic",
    "combat",
    "scroll",
    "pets",
    "wood",
    "mine",
    "fish",
    "cities",
    "map_exit",
    "skills",
    "meditation",
    "life_cycle",
    "spell_order",
    "chat",
    "party_rewards",
}


def acceptance(steps, seconds, *, graphical, exported=False):
    """La duración y un smoke exitoso nunca sustituyen escenarios ausentes."""
    completed = {step["id"] for step in steps if step.get("passed") is True}
    missing = sorted(REQUIRED_SCENARIOS - completed)
    return {
        "required": sorted(REQUIRED_SCENARIOS),
        "completed": sorted(completed),
        "missing": missing,
        "functional_passed": not missing,
        "r10_gameplay_passed": not missing
        and seconds >= 1800
        and graphical
        and exported,
    }


class R10World:
    """Coordinación acotada de dos procesos Godot y un Redis propiedad del ensayo."""

    def __init__(self, fixture, work, output, names, clients, server):
        self.fixture, self.work, self.output = fixture, work, output
        self.names, self.clients, self.server = names, clients, server
        self.sequences = {1: 0, 2: 0}
        self.steps = []
        self.receipts = []
        self.data = tomllib.loads((ROOT / "tests/r10_fixture.toml").read_text())
        self.ids = {}
        self.deadline = time.monotonic() + 600

    def check_processes(self):
        if time.monotonic() > self.deadline:
            raise TimeoutError("R10: plazo global de escenarios agotado")
        if self.server.poll() is not None or any(
            c.poll() is not None for c in self.clients
        ):
            raise RuntimeError("R10 perdió un proceso real; revisar los logs")
        if (
            "Traceback (most recent call last)"
            in (self.output / "server.log").read_text()
        ):
            raise RuntimeError(
                "R10: excepción inesperada del servidor; revisar server.log"
            )
        for i in (1, 2):
            log = (self.output / f"godot-{i}.log").read_text()
            if "SCRIPT ERROR:" in log or "ERROR:" in log:
                raise RuntimeError(f"R10: error Godot {i}")

    def wait(self, predicate, label, timeout=20):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            self.check_processes()
            value = predicate()
            if value:
                return value
            time.sleep(0.05)
        self.save()
        raise TimeoutError(f"R10: {label}")

    def command(self, index, op, **values):
        self.sequences[index] += 1
        sequence = self.sequences[index]
        root = self.work / f"control-{index}"
        path = root / f"{sequence:04d}.request.json"
        pending = path.with_suffix(".pending")
        pending.write_text(json.dumps({"op": op, **values}))
        pending.replace(path)
        response = root / f"{sequence:04d}.response.json"
        self.wait(response.exists, f"Godot {index}, {op}", 40)
        value = json.loads(response.read_text())
        (self.output / f"r10-last-view-{index}.json").write_text(
            json.dumps(value, indent=2) + "\n"
        )
        if not value.get("ok"):
            raise RuntimeError(f"R10: Godot {index} rechazó {op}")
        if op != "snapshot":
            self.receipts.append({"client": index, **value})
            self.save()
        return value["view"]

    def view(self, index, predicate, label):
        value = self.wait(
            lambda: (
                (v if predicate(v) else None)
                if (v := self.command(index, "snapshot"))
                else None
            ),
            label,
        )
        self.receipts.append({"client": index, "assertion": label, "view": value})
        self.save()
        return value

    def save(self):
        (self.output / "r10-actions.json").write_text(
            json.dumps(self.receipts, indent=2) + "\n"
        )
        (self.output / "r10-scenarios.json").write_text(
            json.dumps(self.steps, indent=2) + "\n"
        )

    def passed(self, key, requirement, **observations):
        self.steps.append(
            {
                "id": key,
                "requirement": requirement,
                "passed": True,
                "observations": observations,
                "godot_receipts": len(self.receipts),
            }
        )
        self.save()
        print(f"R10: PASS {key}", flush=True)

    def stats(self, store, index):
        return {
            k: int(v)
            for k, v in store.hgetall(f"player:{self.ids[index]}:user_stats").items()
            if k in self.data["player"] or k == "life_id"
        }

    def items(self, store, index):
        return {
            int(k.removeprefix("slot_")): tuple(map(int, v.split(":")[:2]))
            for k, v in store.hgetall(f"player:{self.ids[index]}:inventory").items()
            if k.startswith("slot_") and v
        }

    def count(self, store, index, item):
        return sum(q for i, q in self.items(store, index).values() if i == item)

    def slot(self, store, index, item):
        return next(
            s for s, (i, q) in self.items(store, index).items() if i == item and q
        )

    def console(self, index, text):
        return self.view(index, lambda v: text.lower() in v["console"].lower(), text)

    def relocate(
        self, store, positions, *, reset=False, stats=None, allow_adjustment=False
    ):
        actual = {}
        for index in positions:
            self.command(index, "logout")
            self.wait(
                lambda: not store.exists(f"session:{self.ids[index]}:owner"),
                "liberar sesión",
            )
        for index, (map_id, x, y) in positions.items():
            uid = self.ids[index]
            store.hset(
                f"player:{uid}:position",
                mapping={"map": map_id, "x": x, "y": y, "heading": 1},
            )
            if reset:
                store.hset(f"player:{uid}:user_stats", mapping=self.data["player"])
                store.hset(
                    f"player:{uid}:stats",
                    mapping={"strength": 80, "agility": 80, "intelligence": 30},
                )
                store.delete(
                    f"player:{uid}:inventory",
                    f"player:{uid}:equipment",
                    f"player:{uid}:spellbook",
                )
                store.hset(
                    f"player:{uid}:inventory",
                    mapping={
                        f"slot_{s}": f"{i}:{q}"
                        for s, (i, q) in self.data["items"].items()
                    },
                )
                store.hset(f"player:{uid}:spellbook", mapping=self.data["spells"])
                store.hset(
                    f"player:{uid}:skills",
                    mapping={f"level:{k}": v for k, v in self.data["skills"].items()},
                )
                store.hset(
                    f"player:{uid}:skills",
                    mapping={"points": 3, "progress_version": 1, "xp_per_level": 100},
                )
            if stats and index in stats:
                store.hset(f"player:{uid}:user_stats", mapping=stats[index])
            self.command(index, "login")
            view = self.view(
                index,
                lambda v: (
                    v["map"] == map_id
                    and v["name"] == self.names[index - 1]
                    and (
                        abs(v["x"] - x) + abs(v["y"] - y) <= 3
                        if allow_adjustment
                        else v["x"] == x and v["y"] == y
                    )
                ),
                "posición de fixture",
            )
            actual[index] = (map_id, view["x"], view["y"])
        self.receipts.append({"fixture_requested": positions, "fixture_actual": actual})
        self.save()
        return actual

    def encounter(self, store, locations, name, primary, companion, *, stats=None):
        """Ubica el fixture junto al NPC real, que conserva su movimiento habitual."""
        npc = store.hgetall(f"npc:instance:{self.targets[name]}")
        nx, ny = int(npc["x"]), int(npc["y"])
        occupied = {
            (int(row["x"]), int(row["y"]))
            for key in store.scan_iter("npc:instance:*")
            if (row := store.hgetall(key))
        }

        def available(x, y):
            return (
                1 < x < 100
                and 1 < y < 100
                and (x, y) not in locations["_forbidden"]
                and (x, y) not in occupied
            )

        for dx, dy in [(0, 1), (1, 0), (0, -1), (-1, 0)]:
            px, py = nx + dx, ny + dy
            if not available(px, py):
                continue
            far = next(
                (
                    (x, y)
                    for x in range(nx - 6, nx + 7)
                    for y in range(ny - 6, ny + 7)
                    if 5 <= abs(x - nx) + abs(y - ny) <= 6 and available(x, y)
                ),
                None,
            )
            if far:
                return self.relocate(
                    store,
                    {primary: (1, px, py), companion: (1, *far)},
                    stats=stats,
                    allow_adjustment=True,
                )
        raise RuntimeError(
            "El NPC no tiene una posición adyacente válida en el mapa propio"
        )

    def run(self, locations, *, soak=True):
        self.wait(
            lambda: all(
                "INTEGRATION_WORLD: READY"
                in (self.output / f"godot-{i}.log").read_text()
                for i in (1, 2)
            ),
            "alta de los dos clientes",
            60,
        )
        with self.fixture.client() as store:
            self.ids = {
                i: int(store.hget(f"account:{self.names[i - 1]}:data", "user_id"))
                for i in (1, 2)
            }
            hostiles = sorted(
                (
                    store.hgetall(k)
                    for k in store.scan_iter("npc:instance:*")
                    if store.hget(k, "npc_id") == "500"
                ),
                key=lambda n: int(n["char_index"]),
            )
            assert len(hostiles) == 2
            self.targets = {
                "combat": hostiles[0]["instance_id"],
                "death": hostiles[1]["instance_id"],
            }
            self.cities(store)
            x, y = locations["base"]
            self.relocate(store, {1: (1, x, y), 2: (1, x + 1, y)}, reset=True)
            self.inventory(store)
            self.bank(store, x, y)
            self.merchant(store, x, y)
            self.trades(store)
            self.social(store)
            self.magic_combat(store, locations)
            self.life_cycle(store, locations)
            self.jobs(store, locations)
            map_id, x, y, action, destination = locations["exit"]
            self.relocate(store, {1: (map_id, x, y)})
            self.command(1, "move", action=action)
            self.view(1, lambda v: v["map"] == destination, "salida del mapa propio")
            self.passed("map_exit", "R04", from_map=map_id, to_map=destination)
            x, y = locations["base"]
            self.relocate(store, {1: (1, x, y), 2: (1, x + 1, y)})
            if soak:
                for i in (1, 2):
                    self.command(i, "soak")
        return self.steps

    def cities(self, store):
        for index in (1, 2):
            self.command(index, "logout")
            self.wait(
                lambda: not store.exists(f"session:{self.ids[index]}:owner"),
                "liberar cuenta base",
            )
        evidence = []
        for job in range(1, 13):
            index = 1 + (job % 2)
            city = self.data["city"][(job - 1) % 6]
            name = f"City{self.ids[index]}x{job}"
            view = self.command(
                index,
                "create",
                name=name,
                job=job,
                race=1 + (job - 1) % 5,
                gender=(job - 1) % 2,
                home=city["home"],
            )
            assert view["map"] == city["map"], (name, view["map"], city)
            uid = int(store.hget(f"account:{name}:data", "user_id"))
            character = store.hgetall(f"player:{uid}:character")
            account = store.hgetall(f"account:{name}:data")
            character = {
                k: account[k]
                for k in [
                    "char_job",
                    "char_race",
                    "char_home",
                    "char_head",
                    "char_gender",
                ]
            }
            assert int(character["char_job"]) == job
            assert int(character["char_race"]) == 1 + (job - 1) % 5
            evidence.append(
                {
                    "job": job,
                    "race": 1 + (job - 1) % 5,
                    "home": city["home"],
                    "map": view["map"],
                    "character": character,
                }
            )
            self.command(index, "logout")
            self.wait(
                lambda: not store.exists(f"session:{uid}:owner"),
                "liberar personaje de ciudad",
            )
        self.passed("cities", "R04/R08", characters=evidence)

    def inventory(self, store):
        before = self.stats(store, 1)
        quantity = self.count(store, 1, 38)
        self.command(1, "use", slot=1)
        self.wait(
            lambda: (
                self.count(store, 1, 38) < quantity
                and self.stats(store, 1)["min_hp"] > before["min_hp"]
            ),
            "poción y HP",
        )
        self.view(1, lambda v: v["hp"] > before["min_hp"], "HP recibido")
        self.command(1, "use", slot=25)
        self.wait(lambda: self.count(store, 1, 37) < 10, "slot 25")
        self.command(1, "equip", slot=26)
        self.wait(
            lambda: bool(store.hgetall(f"player:{self.ids[1]}:equipment")),
            "equipamiento",
        )
        self.command(1, "equip", slot=26)
        self.command(1, "use", slot=30)
        self.wait(lambda: self.count(store, 1, 1) < 10, "slot 30")
        self.command(1, "drag", source=26, destination=30)
        self.wait(
            lambda: (
                self.items(store, 1).get(30, (0, 0))[0] == 15
                and self.items(store, 1).get(26, (0, 0))[0] == 1
            ),
            "intercambio de slots ocupados",
        )
        self.command(1, "drop", slot=30, amount=1)
        self.wait(lambda: self.count(store, 1, 15) == 0, "drop de objeto")
        self.command(1, "pickup")
        self.wait(lambda: self.count(store, 1, 15) == 1, "pickup del mismo objeto")
        self.passed(
            "inventory",
            "R05",
            slots=[1, 25, 26, 30],
            observed_hp=self.stats(store, 1)["min_hp"],
            drop_pickup=True,
            swap=True,
        )

    def bank(self, store, x, y):
        self.command(1, "click", x=x + 2, y=y - 2, double=True)
        self.view(1, lambda v: v["panel"] == "bank", "ventana de banco")
        gold = self.stats(store, 1)["gold"]
        self.command(1, "bank_gold", deposit=True, amount=120)
        self.wait(lambda: self.stats(store, 1)["gold"] == gold - 120, "depósito de oro")
        self.command(1, "bank_gold", deposit=False, amount=120)
        self.wait(lambda: self.stats(store, 1)["gold"] == gold, "retiro de oro")
        self.command(
            1, "bank_item", deposit=True, slot=self.slot(store, 1, 15), amount=1
        )
        self.wait(lambda: self.count(store, 1, 15) == 0, "depósito de daga")
        self.view(1, lambda v: v.get("bank_items", {}).get("1") == [15, 1], "daga recibida en la bóveda del cliente")
        self.command(1, "bank_select", vault=True, slot=1, capture=True)
        self.view(
            1,
            lambda v: v.get("bank_info") == {
                "name": "Daga", "range": "1/2", "icon": "res://Assets/UI/damage.svg",
                "description": "Daño: 1/2",
            },
            "detalle de daño con espada incluida",
        )
        self.command(1, "bank_item", deposit=False, slot=1, amount=1)
        self.wait(lambda: self.count(store, 1, 15) == 1, "retiro de daga")
        self.view(1, lambda v: "1" not in v.get("bank_items", {}), "retiro reflejado en la bóveda del cliente")
        self.command(1, "bank_select", vault=True, slot=1)
        self.view(
            1,
            lambda v: v.get("bank_info") == {
                "name": "Seleccioná un objeto", "range": "", "icon": "", "description": "",
            },
            "detalle vacío tras retirar el objeto seleccionado",
        )
        self.command(1, "close")
        self.view(1, lambda v: v["panel"] == "", "cerrar banco")
        self.passed("bank", "R05", gold_conserved=gold, items_conserved=True, included_icons=True)

    def merchant(self, store, x, y):
        self.command(1, "click", x=x, y=y - 2, double=True)
        self.view(1, lambda v: v["panel"] == "merchant", "ventana de mercader")
        gold = self.stats(store, 1)["gold"]
        count = self.count(store, 1, 15)
        self.command(1, "merchant", buy=True, slot=1, amount=1)
        self.wait(lambda: self.count(store, 1, 15) == count + 1, "compra al NPC")
        price = gold - self.stats(store, 1)["gold"]
        self.command(1, "merchant", buy=False, slot=self.slot(store, 1, 15), amount=1)
        self.wait(lambda: self.count(store, 1, 15) == count, "venta al NPC")
        assert self.stats(store, 1)["gold"] == gold - price + (price // 2)
        self.view(
            1,
            lambda v: v["gold"] == gold - price + (price // 2),
            "saldo de comercio recibido",
        )
        self.command(1, "close")
        self.view(1, lambda v: v["panel"] == "", "cerrar mercader")
        self.passed("merchant", "R05", purchase_price=price, sale_price=price // 2)

    def ready_trade(self):
        def ready():
            a, b = (self.command(i, "snapshot") for i in (1, 2))
            return (
                a["panel"] == b["panel"] == "trade"
                and a["trade"]["state"] == b["trade"]["state"] == "active"
                and a["trade"]["revision"] == b["trade"]["revision"]
            )

        self.wait(ready, "revisión de intercambio sincronizada en ambos clientes")

    def trades(self, store):
        for complete in (True, False):
            gold = [self.stats(store, i)["gold"] for i in (1, 2)]
            items = [self.count(store, i, 15) for i in (1, 2)]
            self.command(1, "chat", text=f"/COMERCIAR {self.names[1]}")
            self.command(1, "snapshot")
            self.view(2, lambda v: v["panel"] == "trade", "invitación de trade")
            self.command(2, "trade", action="accept")
            self.ready_trade()
            self.command(1, "trade", action="gold", amount=50)
            self.view(
                1, lambda v: v["trade"]["players"][0][2] == 50, "oferta de oro ACK"
            )
            self.ready_trade()
            self.command(
                2,
                "trade",
                action="item",
                slot=self.slot(store, 2, 15 if complete else 38),
                amount=1,
            )
            self.view(
                2, lambda v: len(v["trade"]["players"][1][4]) == 1, "oferta de ítem ACK"
            )
            self.ready_trade()
            if complete:
                self.command(1, "trade", action="confirm")
                self.view(
                    2, lambda v: v["trade"]["players"][0][3], "confirmación del par"
                )
                self.command(2, "trade", action="confirm")
            else:
                self.command(2, "trade", action="cancel")
            self.view(1, lambda v: v["panel"] == "", "resultado final A")
            self.view(2, lambda v: v["panel"] == "", "resultado final B")
            assert [self.stats(store, i)["gold"] for i in (1, 2)] == (
                [gold[0] - 50, gold[1] + 50] if complete else gold
            )
            assert [self.count(store, i, 15) for i in (1, 2)] == (
                [items[0] + 1, items[1] - 1] if complete else items
            )
            self.passed(
                "trade_complete" if complete else "trade_cancel",
                "R05",
                gold_conserved=sum(gold),
                items_conserved=sum(items),
            )

    def social(self, store):
        for message in (
            "r10-público pingüino y caña",
            "-r10-grito ¡hola!",
            f"\\{self.names[1]} r10-privado aceptación",
        ):
            self.command(1, "chat", text=message)
            self.console(
                2,
                message.split(" ", 1)[-1]
                if message.startswith("\\")
                else message.lstrip("-"),
            )
        self.passed(
            "chat", "R03/R07", public=True, yell=True, private=True, latin1_accents=True
        )
        self.command(1, "chat", text="/crearparty")
        self.console(1, "party")
        self.command(1, "chat", text=f"/party {self.names[1]}")
        self.console(2, self.names[0])
        self.command(2, "chat", text=f"/acceptparty {self.names[0]}")
        self.wait(
            lambda: (
                store.get(f"user:{self.ids[1]}:party") is not None
                and store.get(f"user:{self.ids[1]}:party")
                == store.get(f"user:{self.ids[2]}:party")
            ),
            "membresía de party persistida",
        )
        self.console(2, f"Te has unido a la party de {self.names[0]}")
        party_id = store.get(f"user:{self.ids[1]}:party")
        for index in (1, 2):
            member = json.loads(store.hget(f"party:{party_id}:members", str(self.ids[index])))
            assert member["username"] == self.names[index - 1], "La party perdió el nombre real del personaje"
        self.command(1, "chat", text="/pmsg r10-party")
        self.console(2, "r10-party")
        self.command(2, "chat", text="/salirparty")
        self.wait(
            lambda: not store.get(f"user:{self.ids[2]}:party"),
            "salida de party persistida",
        )
        self.passed("party", "R07", create_join_accept_chat_leave=True, real_names_in_redis_and_ui=True)
        clan = "R10" + str(self.ids[1])
        self.command(1, "chat", text=f"/CREARCLAN {clan} aceptación")
        self.console(1, clan)
        self.command(1, "chat", text=f"/INVITARCLAN {self.names[1]}")
        self.console(2, "invit")
        self.command(2, "chat", text="/ACEPTARCLAN")
        self.wait(
            lambda: (
                store.get(f"user:{self.ids[1]}:clan") is not None
                and store.get(f"user:{self.ids[1]}:clan")
                == store.get(f"user:{self.ids[2]}:clan")
            ),
            "membresía de clan persistida",
        )
        self.console(2, clan)
        self.command(1, "chat", text="/CLAN r10-clan")
        self.console(2, "r10-clan")
        self.command(2, "chat", text="/detallesclan")
        self.view(
            2, lambda v: clan in v.get("clan_details", ""), "detalles reales de clan"
        )
        self.command(2, "close")
        self.command(2, "chat", text="/salirclan")
        self.wait(
            lambda: not store.get(f"user:{self.ids[2]}:clan"),
            "salida de clan persistida",
        )
        self.passed("clan", "R07", create_invite_accept_chat_details_leave=True)

    def magic_combat(self, store, locations):
        x, y = locations["base"]
        self.relocate(store, {1: (1, x, y), 2: (1, x + 1, y)}, reset=True)
        self.command(1, "chat", text=f"/party {self.names[1]}")
        self.console(2, self.names[0])
        self.command(2, "chat", text=f"/acceptparty {self.names[0]}")
        party = self.wait(
            lambda: store.get(f"user:{self.ids[2]}:party"), "party de combate"
        )
        hp = self.stats(store, 1)["min_hp"]
        self.command(1, "cancel_cast", slot=1)
        self.view(1, lambda v: v["target"] == 0, "cancelación de magia")
        self.command(1, "cast", slot=1, x=x, y=y)
        self.wait(lambda: self.stats(store, 1)["min_hp"] > hp, "curación confirmada")
        self.view(1, lambda v: v["hp"] > hp, "HP de curación en UI")
        mana = self.stats(store, 1)["min_mana"]
        self.command(1, "cast", slot=2, x=x - 2, y=y)
        self.console(1, "objetivo válido")
        assert self.stats(store, 1)["min_mana"] == mana, (
            "Objetivo inválido no cobra maná"
        )
        self.command(1, "chat", text="/meditar")
        self.wait(
            lambda: self.stats(store, 1)["min_mana"] > mana,
            "recuperación de maná meditando",
            timeout=180,
        )
        self.view(1, lambda v: v["mana"] > mana, "maná de meditación en UI")
        self.command(1, "chat", text="/meditar")
        self.console(1, "Dejas de meditar")
        self.passed(
            "meditation",
            "R06",
            mana_before=mana,
            mana_after=self.stats(store, 1)["min_mana"],
        )
        self.command(1, "use", slot=23)
        self.wait(
            lambda: "6" in store.hgetall(f"player:{self.ids[1]}:spellbook").values(),
            "aprender pergamino",
        )
        quantity = self.count(store, 1, 197)
        self.command(1, "use", slot=23)
        self.console(1, "Ya conoces ese hechizo")
        assert self.count(store, 1, 197) == quantity
        self.passed("scroll", "R06", duplicate_does_not_consume=True)
        self.command(1, "skills_open")
        self.view(
            1,
            lambda v: v.get("skills", {}).get("ready", False),
            "estado inicial de habilidades",
        )
        self.command(1, "skills_allocate", skill=9, amount=1)
        self.wait(
            lambda: store.hget(f"player:{self.ids[1]}:skills", "points") == "2",
            "asignación autoritativa",
        )
        self.view(
            1,
            lambda v: v.get("skills", {}).get("points") == 2,
            "confirmación visual de puntos",
        )
        self.command(1, "close")
        self.passed("skills", "R06", points_before=3, points_after=2, skill="talar")
        actual = self.encounter(store, locations, "combat", 1, 2)
        _, x, y = actual[1]
        npcs = lambda: [store.hgetall(k) for k in store.scan_iter("npc:instance:*")]

        def adjacent_target():
            return next(
                (
                    n
                    for n in npcs()
                    if n["instance_id"] == self.targets["combat"]
                    and abs(int(n["x"]) - x) + abs(int(n["y"]) - y) == 1
                ),
                None,
            )

        target = self.wait(adjacent_target, "NPC hostil alcanza al jugador")
        assert (target["name"], int(target["body_id"]), int(target["max_hp"])) == (
            "Murciélago",
            9,
            15,
        )
        self.view(
            1,
            lambda v: v["world_characters"].get(target["char_index"], [])[2:] == [9, 0],
            "apariencia original del NPC en Godot",
        )
        old_hp = int(target["hp"])
        self.command(1, "cast", slot=2, x=int(target["x"]), y=int(target["y"]))
        self.wait(
            lambda: any(
                int(n["char_index"]) == int(target["char_index"])
                and int(n["hp"]) < old_hp
                for n in npcs()
            ),
            "daño mágico al NPC",
        )
        self.passed(
            "magic",
            "R06",
            targeted_damage=True,
            healing=True,
            cancellation=True,
            invalid_target_no_charge=True,
        )
        action = {
            (0, -1): "ui_up",
            (1, 0): "ui_right",
            (0, 1): "ui_down",
            (-1, 0): "ui_left",
        }[(int(target["x"]) - x, int(target["y"]) - y)]
        self.command(1, "move", action=action)
        before = self.stats(store, 1)["experience"]
        peer_before = self.stats(store, 2)["experience"]
        for _ in range(15):
            self.command(1, "attack")
            if self.stats(store, 1)["experience"] > before:
                break
            time.sleep(0.6)
        self.wait(
            lambda: self.stats(store, 1)["experience"] > before,
            "muerte de NPC y experiencia",
        )
        self.wait(
            lambda: self.stats(store, 2)["experience"] > peer_before,
            "experiencia compartida al compañero",
        )
        members = {
            i: json.loads(store.hget(f"party:{party}:members", str(self.ids[i])))
            for i in (1, 2)
        }
        for index, old in [(1, before), (2, peer_before)]:
            actual = self.stats(store, index)["experience"] - old
            expected = int(members[index]["accumulated_exp"])
            assert actual == expected, (index, "recompensa duplicada", actual, expected)
            self.view(
                index,
                lambda v: v["experience"] == old + expected,
                "experiencia de party confirmada en UI",
            )
        self.passed(
            "party_rewards",
            "R07",
            awarded={i: self.stats(store, i)["experience"] for i in (1, 2)},
            not_duplicated=True,
        )
        self.command(2, "chat", text="/salirparty")
        self.wait(
            lambda: not store.get(f"user:{self.ids[2]}:party"),
            "salida después del combate",
        )
        self.passed(
            "combat",
            "R06",
            experience_before=before,
            experience_after=self.stats(store, 1)["experience"],
        )
        x, y = locations["combat"]
        self.relocate(store, {1: (1, x, y), 2: (1, x + 2, y + 2)})
        self.command(1, "equip", slot=27)
        self.command(1, "cast", slot=3, x=x, y=y + 1)
        pets = lambda: [
            n for n in npcs() if int(n.get("summoned_by_user_id", 0)) == self.ids[1]
        ]
        self.wait(pets, "invocación de mascota")
        pet = pets()[0]
        self.view(
            1,
            lambda v: v["world_characters"].get(pet["char_index"], [])[2:] == [393, 0],
            "apariencia original de mascota en Godot",
        )
        original = [(n["x"], n["y"]) for n in pets()]
        # La regla propia inicia seguimiento a más de cinco tiles.
        self.command(1, "move", action="ui_left", seconds=2.0)
        self.wait(
            lambda: [(n["x"], n["y"]) for n in pets()] != original,
            "seguimiento de mascota",
        )
        moved = pets()[0]
        self.view(
            1,
            lambda v: (
                v["world_characters"].get(pet["char_index"], [])[:2]
                == [int(moved["x"]), int(moved["y"])]
            ),
            "seguimiento observado en Godot",
        )
        self.command(1, "chat", text="/PET LIBERAR")
        self.wait(lambda: not pets(), "liberación de mascota")
        self.view(
            1,
            lambda v: pet["char_index"] not in v["world_characters"],
            "desaparición de mascota en Godot",
        )
        self.passed("pets", "R08", summoned=True, followed=True, released=True)
        self.command(1, "move_spell", slot=2)
        self.wait(
            lambda: (
                store.hget(f"player:{self.ids[1]}:spellbook", "2") == "33"
                and store.hget(f"player:{self.ids[1]}:spellbook", "3") == "2"
            ),
            "orden persistido del libro",
        )
        self.view(
            1,
            lambda v: v["spells"][:4] == [3, 33, 2, 11],
            "orden confirmado por servidor en UI",
        )
        self.passed(
            "spell_order",
            "R06",
            first_slots=[3, 33, 2, 11],
            reconnect_checked_after_soak=True,
        )

    def life_cycle(self, store, locations):
        evidence = []
        appearance = self.command(2, "snapshot")["appearance"]
        for method in ("spell", "priest"):
            actual = self.encounter(
                store, locations, "death", 2, 1, stats={2: {"min_hp": 1}}
            )
            _, x, y = actual[2]
            life = self.stats(store, 2).get("life_id", 0)
            self.wait(
                lambda: (
                    store.hget(f"player:{self.ids[2]}:user_stats", "death_state")
                    == "complete"
                ),
                "muerte real por NPC",
            )
            self.view(
                2,
                lambda v: v["hp"] == 0 and v["appearance"] != appearance,
                "fantasma visible",
            )
            if method == "spell":
                self.command(1, "cast", slot=4, x=x, y=y)
            else:
                priest = next(
                    store.hgetall(k)
                    for k in store.scan_iter("npc:instance:*")
                    if store.hget(k, "npc_id") == "81"
                )
                px, py = int(priest["x"]), int(priest["y"])
                self.relocate(store, {2: (1, px, py - 1)}, allow_adjustment=True)
                self.command(2, "click", x=px, y=py, double=True)
            self.wait(
                lambda: (
                    self.stats(store, 2).get("life_id", 0) == life + 1
                    and self.stats(store, 2)["min_hp"] > 0
                ),
                "resurrección " + method,
            )
            self.view(
                2,
                lambda v: v["hp"] > 0 and v["appearance"] == appearance,
                "apariencia restaurada " + method,
            )
            evidence.append(
                {
                    "method": method,
                    "life_before": life,
                    "life_after": life + 1,
                    "appearance": appearance,
                }
            )
        self.passed("life_cycle", "R06", resurrections=evidence)

    def jobs(self, store, locations):
        for name, skill, item in [
            ("wood", 9, 58),
            ("mine", 13, 192),
            ("fish", 12, 139),
        ]:
            map_id, x, y, tx, ty = locations[name]
            self.relocate(store, {1: (map_id, x, y)})
            before = self.count(store, 1, item)
            tool = {"wood": 561, "mine": 562, "fish": 563}[name]
            tool_slot = self.slot(store, 1, tool)
            self.command(1, "equip", slot=tool_slot)
            self.view(
                1,
                lambda v: v["items"][str(tool_slot)][2],
                "herramienta equipada " + name,
            )
            for _ in range(40):
                self.command(1, "use", slot=tool_slot)
                self.view(
                    1, lambda v: v["using_skill"] == skill, "herramienta activa " + name
                )
                self.command(1, "work", skill=skill, x=tx, y=ty)
                time.sleep(1)
                if self.count(store, 1, item) > before:
                    break
            self.wait(lambda: self.count(store, 1, item) > before, name)
            self.view(
                1,
                lambda v: (
                    sum(stack[1] for stack in v["items"].values() if stack[0] == item)
                    > before
                ),
                "recurso visible",
            )
            self.passed(
                name,
                "R08",
                item_id=item,
                gained=self.count(store, 1, item) - before,
                map=map_id,
            )


def prepare_fixture(work, output):
    """Copia los catálogos propios y modifica sólo spawns en el sandbox del ensayo."""
    from src.runtime_paths import data_dir
    from src.runtime_paths import maps_dir
    from src.services.map.map_resources_service import MapResourcesService

    original = data_dir()
    target = work / "scenario-data"
    shutil.copytree(original, target)
    resources = MapResourcesService()
    one = resources.resources["map_1"]
    forbidden = one["blocked"] | one["water"]

    def clear(x, y, radius=2):
        return all(
            1 < a < 100 and 1 < b < 100 and (a, b) not in forbidden
            for a in range(x - radius, x + radius + 1)
            for b in range(y - radius, y + radius + 1)
        )

    choices = [(x, y) for x in range(15, 86) for y in range(15, 86) if clear(x, y)]
    base = min(choices, key=lambda p: abs(p[0] - 58) + abs(p[1] - 45))
    combat = max(
        [
            p
            for p in choices
            if all((p[0] - d, p[1]) not in forbidden for d in range(9))
        ],
        key=lambda p: abs(p[0] - base[0]) + abs(p[1] - base[1]),
    )
    death = next(
        (x, y)
        for x, y in choices
        if clear(x, y, 4)
        and all(abs(x - a) + abs(y - b) > 15 for a, b in (base, combat))
    )
    text = "# Fixture R10: catálogos y mapas originales; spawns acotados.\n"
    for npc, (x, y) in [
        (7, (base[0], base[1] - 2)),
        (5, (base[0] + 2, base[1] - 2)),
        (500, (combat[0], combat[1] - 1)),
        (500, (death[0], death[1] - 1)),
        (81, (death[0], death[1] + 2)),
    ]:
        text += f"\n[[map_npcs.1.spawn_points]]\nnpc_id = {npc}\nx = {x}\ny = {y}\ndirection = 3\n"
    (target / "world/map_npcs.toml").write_text(text)
    result = {"base": base, "combat": combat, "death": death}
    transitions = next(
        json.loads(line)
        for line in (maps_dir() / "transitions_001-050.json").open()
        if json.loads(line)["from_map"] == 1
    )
    for exit in transitions["exits"]:
        for dx, dy, action in [
            (0, 1, "ui_up"),
            (1, 0, "ui_left"),
            (-1, 0, "ui_right"),
            (0, -1, "ui_down"),
        ]:
            pos = (exit["x"] + dx, exit["y"] + dy)
            if pos not in forbidden and pos not in {
                (e["x"], e["y"]) for e in transitions["exits"]
            }:
                result["exit"] = (1, *pos, action, exit["to_map"])
                break
        if "exit" in result:
            break
    if "exit" not in result:
        raise RuntimeError("No hay una salida válida en el dataset propio")
    for name, layer in [("wood", "trees"), ("mine", "mines"), ("fish", "water")]:
        found = None
        for key, values in sorted(
            resources.resources.items(), key=lambda p: int(p[0].split("_")[-1])
        ):
            for tx, ty in sorted(values.get(layer, set())):
                for dx, dy in [(0, 1), (1, 0), (-1, 0), (0, -1)]:
                    x, y = tx + dx, ty + dy
                    if (
                        2 < x < 99
                        and 2 < y < 99
                        and (x, y) not in values["blocked"]
                        and (x, y) not in values["water"]
                    ):
                        found = (int(key.split("_")[-1]), x, y, tx, ty)
                        break
                if found:
                    break
            if found:
                break
        if not found:
            raise RuntimeError(f"El dataset propio no ofrece un recurso {name}")
        result[name] = found
    (output / "r10-fixture.json").write_text(
        json.dumps(
            {
                "locations": result,
                "fixture_sha256": hashlib.sha256(
                    (ROOT / "tests/r10_fixture.toml").read_bytes()
                ).hexdigest(),
                "spawns": text,
                "catalogs": "copiados del wheel instalado, sin cambios",
                "gold_decay_enabled": False,
                "authentication_fixture_budget": {"per_ip": 120, "per_account": 40},
            },
            indent=2,
        )
        + "\n"
    )
    # Geometría original para preparar encuentros; no se modifica ni se publica
    # como estado de jugadores en el recibo del fixture.
    result["_forbidden"] = forbidden
    return target, result
