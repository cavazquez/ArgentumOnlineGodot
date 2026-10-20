"""Voces y defensa con catálogos originales en una fixture de encuentro explícita."""

import json
import time

from r10_world import R10World
from skills_world import prepare_fixture as skills_fixture
from mechanics_world import MechanicsWorld as SpellWorld


def prepare_fixture(work, output):
    target, locations = skills_fixture(work, output)
    _, x, y = locations["skills_base"]
    with (target / "world/map_npcs.toml").open("a") as file:
        for template, tx, ty in ((577, x+2, y), (49, x+9, y+3)):
            file.write(f"\n[[map_npcs.2.spawn_points]]\nnpc_id={template}\nx={tx}\ny={ty}\ndirection=3\n")
    return target, locations


def acceptance(steps, seconds, *, graphical, **_):
    required = {"npc-voices", "npc-guard"}
    completed = {row["id"] for row in steps if row.get("passed")}
    return {"test_execution_passed": graphical and required <= completed, "npc_sounds_in_live_catalog_proven": required <= completed}


class NPCPolicyWorld(R10World):
    offline = SpellWorld.offline

    def waves(self, index):
        return [row["bytes"][1] for row in self.command(index, "snapshot").get("fx_packets", []) if row["kind"] == "sound"]

    def run(self, locations):
        self.deadline = time.monotonic() + 900
        self.wait(lambda: all("INTEGRATION_WORLD: READY" in (self.output / f"godot-{i}.log").read_text() for i in (1,2)), "dos clientes de NPC", 90)
        with self.fixture.client() as store:
            self.ids = {i: int(store.hget(f"account:{self.names[i-1]}:data", "user_id")) for i in (1,2)}
            _, x, y = locations["skills_base"]
            poses = {1: (2,x,y), 2: (2,x,y+1)}
            self.relocate(store, poses, reset=True)
            def equipment():
                for i in (1,2):
                    store.hset(f"player:{self.ids[i]}:user_stats", mapping={"min_hp":30000,"max_hp":30000,"min_mana":10000,"max_mana":10000,"criminal":0,"faction_id":"neutral"})
                store.hset(f"player:{self.ids[1]}:spellbook", "2", 23)
                store.hset(f"player:{self.ids[1]}:spellbook", "1", 9)
            self.offline(store, poses, equipment)
            for i in (1,2): self.command(i, "capture_reset", label="npc-voices")
            target_key = next(key for key in store.scan_iter("npc:instance:*") if store.hget(key,"npc_id") == "577")
            (self.output / "npc-encounter-observations.json").write_text(json.dumps({
                "target": store.hgetall(target_key),
                "positions": {i: store.hgetall(f"player:{self.ids[i]}:position") for i in (1,2)},
            }, indent=2) + "\n")
            self.wait(lambda: 30 in self.waves(1) and 30 in self.waves(2), "voz de ataque Snd1", 45)
            # Inmovilizar mediante el hechizo real evita disparar a una casilla
            # que la criatura ya dejó mientras transcurre la cadencia del cliente.
            for _ in range(8):
                target = store.hgetall(target_key)
                if float(target.get("paralyzed_until", 0)) > time.time(): break
                self.command(1,"cast",slot=1,actor=int(target["char_index"]),x=int(target["x"]),y=int(target["y"]))
                time.sleep(1.1)
            self.wait(lambda: float(store.hget(target_key,"paralyzed_until") or 0) > time.time(), "parálisis por cliente", 10)
            target = store.hgetall(target_key)
            self.command(1,"cast",slot=2,actor=int(target["char_index"]),x=int(target["x"]),y=int(target["y"]))
            self.wait(lambda: 31 in self.waves(1) and 31 in self.waves(2), "voz al daño mágico Snd2", 15)
            # Ataque físico real cuando la criatura llega junto al jugador.
            for _ in range(15):
                if not store.exists(target_key): break
                target = store.hgetall(target_key)
                position = store.hgetall(f"player:{self.ids[1]}:position")
                dx,dy=int(target["x"])-int(position["x"]),int(target["y"])-int(position["y"])
                if abs(dx)+abs(dy)==1:
                    self.command(1,"face",heading={(0,-1):1,(1,0):2,(0,1):3,(-1,0):4}[(dx,dy)])
                    self.command(1,"attack")
                    break
                time.sleep(.5)
            for _ in range(40):
                if not store.exists(target_key): break
                target=store.hgetall(target_key)
                self.command(1,"cast",slot=2,actor=int(target["char_index"]),x=int(target["x"]),y=int(target["y"]))
                time.sleep(1.1)
            self.wait(lambda: not store.exists(target_key), "muerte confirmada del NPC", 15)
            self.wait(lambda: 32 in self.waves(1) and 32 in self.waves(2), "voz de muerte Snd3 en ambos clientes", 15)
            self.passed("npc-voices", "Ataque, daño mágico/físico y muerte del catálogo con dos observadores", voices=[30,31,32], template=577, encounter_fixture=True)
            guard_poses={1:(2,x+9,y+2),2:(2,x+8,y+3)}
            self.relocate(store, guard_poses, stats={i:{"min_hp":30000,"max_hp":30000} for i in (1,2)})
            before=int(store.hget(f"player:{self.ids[2]}:user_stats","min_hp"))
            def criminal(): store.hset(f"player:{self.ids[1]}:user_stats","criminal",1)
            self.offline(store,guard_poses,criminal)
            self.wait(lambda: int(store.hget(f"player:{self.ids[1]}:user_stats","min_hp"))<30000,"guardia defiende su puesto",45)
            assert int(store.hget(f"player:{self.ids[2]}:user_stats","min_hp"))==before
            self.passed("npc-guard","El guardia ataca al criminal y conserva al neutral",guard_template=49,criminal=self.ids[1],neutral=self.ids[2])
            for i in (1,2):
                self.command(i,"capture",label="npc-policy")
                self.command(i,"soak")
        return self.steps
