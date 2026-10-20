"""Contadores y condenas: dos interfaces Godot, acciones reales y Redis propio."""

import json
import os
import subprocess
import sys
import time

from full_world import FullWorld
from skills_world import prepare_fixture as base_fixture

FIELDS = ("deaths", "player_kills", "citizen_kills", "criminal_kills", "npc_kills")
LABELS = dict(
    zip(
        FIELDS,
        (
            "Muertes propias",
            "Usuarios Matados",
            "Ciudadanos Matados",
            "Criminales Matados",
            "NPCs Matados",
        ),
    )
)


def prepare_fixture(work, output):
    data, locations = base_fixture(work, output)
    add_stats_npc(data, locations)
    return data, locations


def add_stats_npc(data, locations):
    _, x, y = locations["skills_base"]
    with (data / "npcs/friendly.toml").open("a") as file:
        file.write("""
[[npc]]
id=7779
nombre="Criatura de contadores"
descripcion="Objetivo exclusivo del ensayo de estadísticas"
body_id=9
head_id=0
hp_max=1
nivel=1
es_hostil=false
es_atacable=true
rango_agresion=1
cooldown_ataque=0.8
flags={attackable=1}
""")
    with (data / "world/map_npcs.toml").open("a") as file:
        file.write(
            f"\n[[map_npcs.2.spawn_points]]\nnpc_id=7779\nx={x + 2}\ny={y + 3}\ndirection=3\n"
        )


def acceptance(steps, seconds, **_):
    passed = any(
        s.get("passed") is True and s.get("id") == "lifetime-statistics" for s in steps
    )
    return {
        "kind": "Dos clientes: muertes, bajas y días restantes de condena",
        "test_execution_passed": passed,
        "r10_gameplay_passed": False,
    }


def counters(world, store):
    return {
        i: {
            k: int(store.hget(f"player:{world.ids[i]}:user_stats", k) or 0)
            for k in FIELDS
        }
        for i in (1, 2)
    }


def show(world, store, label):
    result = {}
    expected = counters(world, store)
    for i in (1, 2):
        world.command(i, "close_mechanics")
        world.command(i, "stats_open")
        result[i] = world.view(
            i,
            lambda v, i=i: all(
                v.get("ministats", {}).get(name) == str(expected[i][key])
                for key, name in LABELS.items()
            ),
            "contadores del servidor en estadísticas",
        )
        world.screen(label, i)
    return {i: result[i]["ministats"] for i in (1, 2)}


def administer(world, days, reason):
    environment = dict(
        os.environ,
        PYAO_REDIS__HOST="127.0.0.1",
        PYAO_REDIS__PORT=str(world.fixture.port),
        PYAO_REDIS__PASSWORD_FILE=str(world.fixture.password_file),
    )
    result = subprocess.run(
        [
            sys.executable,
            "-m",
            "src.operations.player_jail",
            world.names[1],
            "--days",
            str(days),
            "--reason",
            reason,
        ],
        env=environment,
        capture_output=True,
        text=True,
        timeout=30,
        check=True,
    )
    return json.loads(result.stdout)


def exercise(world, store, locations):
    """Nunca escribe resultados de combate: sólo prepara HP y clasificación del fixture."""
    _, x, y = locations["skills_base"]
    x += 4
    world.base = {1: (2, x, y), 2: (2, x + 1, y)}
    baseline = counters(world, store)
    for criminal in (0, 1):
        store.hset(f"player:{world.ids[2]}:user_stats", "criminal", criminal)
        world.pvp_lifecycle(store, x, y)
    after = counters(world, store)
    assert after[1]["player_kills"] == baseline[1]["player_kills"] + 2
    assert after[1]["citizen_kills"] == baseline[1]["citizen_kills"] + 1
    assert after[1]["criminal_kills"] == baseline[1]["criminal_kills"] + 1
    assert after[2]["deaths"] == baseline[2]["deaths"] + 2
    assert after[1]["deaths"] == baseline[1]["deaths"]
    assert after[2]["player_kills"] == baseline[2]["player_kills"]
    show(world, store, "counters-after-pvp")
    # La criatura de la fixture no se confunde con un jugador.
    key = next(
        (
            k
            for k in store.scan_iter("npc:instance:*")
            if store.hget(k, "npc_id") == "7779"
        ),
        None,
    )
    if key:
        tx, ty = int(store.hget(key, "x")), int(store.hget(key, "y"))
        before_npc = counters(world, store)
        world.command(1, "close_mechanics")
        world.command(1, "cast", slot=2, x=tx, y=ty)
        world.wait(lambda: not store.exists(key), "muerte real del NPC")
        after_npc = counters(world, store)
        assert after_npc[1]["npc_kills"] == before_npc[1]["npc_kills"] + 1
        assert after_npc[1]["player_kills"] == before_npc[1]["player_kills"]
    else:
        raise RuntimeError("Falta la criatura necesaria para comprobar bajas NPC")
    sentenced = administer(world, 2, "Condena sintética del ensayo de dos clientes")
    show(world, store, "counters-sentence")
    world.view(
        2,
        lambda v: v.get("ministats", {}).get("Cárcel: días restantes") == "2",
        "condena real en días",
    )
    # Control temporal exclusivo del fixture: desplazar el vencimiento simula un día.
    stats_key = f"player:{world.ids[2]}:user_stats"
    store.hset(stats_key, "jail_until", int(sentenced["jail_until"]) - 86400)
    active = {
        "counters": counters(world, store),
        "until": store.hget(stats_key, "jail_until"),
    }
    for i in (1, 2):
        world.command(i, "logout")
        world.wait(
            lambda i=i: not store.exists(f"session:{world.ids[i]}:owner"),
            "liberar sesión antes de reiniciar",
        )
    world.server = world.restart_server()
    for i in (1, 2):
        world.command(i, "login")
        world.view(i, lambda v: v.get("in_game", False), "reconexión tras reinicio")
    assert counters(world, store) == active["counters"]
    assert store.hget(stats_key, "jail_until") == active["until"]
    reopened = show(world, store, "counters-restarted")
    assert reopened[2]["Cárcel: días restantes"] == "1"
    store.hset(stats_key, "jail_until", int(time.time()) - 1)
    expired = show(world, store, "counters-expired")
    assert expired[2]["Cárcel: días restantes"] == "0"
    administer(world, 0, "Liberación explícita del ensayo")
    result = {
        "before": baseline,
        "after": counters(world, store),
        "reopened_ui": reopened,
        "expired_ui": expired,
        "sentence_offline_and_restart": True,
        "clock_control": "Deadline shifted only in disposable Redis; production clock unchanged",
        "screenshots": [
            f"counters-{stage}-{i}.png"
            for stage in ("after-pvp", "sentence", "restarted", "expired")
            for i in (1, 2)
        ],
    }
    (world.output / "lifetime-statistics.json").write_text(
        json.dumps(result, indent=2, ensure_ascii=False) + "\n"
    )
    world.passed("lifetime-statistics", **result)


class LifetimeStatsWorld(FullWorld):
    def run(self, locations):
        self.deadline = time.monotonic() + 900
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
            exercise(self, store, locations)
            for i in (1, 2):
                self.command(i, "close_mechanics")
                self.command(i, "soak")
        return self.steps
