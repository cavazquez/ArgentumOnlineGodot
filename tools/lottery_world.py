"""Lotería física: dos Godot gráficos, reloj productivo de 300s y Redis aislado."""

import json
import shutil
import time

from r10_world import R10World

REQUIRED = {"lottery-npc", "lottery-bets", "lottery-offline", "lottery-restart"}


def acceptance(steps, seconds, *, graphical, **_):
    done = {row["id"] for row in steps if row.get("passed") is True}
    return {"test_execution_passed": graphical and REQUIRED <= done, "missing": sorted(REQUIRED - done)}


def prepare_fixture(work, output):
    from src.runtime_paths import data_dir
    from src.services.map.map_resources_service import MapResourcesService
    target = work / "scenario-data"
    shutil.copytree(data_dir(), target)
    resources = MapResourcesService().resources["map_1"]
    for tile in [(53, 52), (52, 52), (54, 52)]:
        if tile in resources["blocked"] or tile in resources["water"]:
            raise RuntimeError("El puesto o sus accesos no son tierra transitable: " + str(tile))
    # Se conserva el mapa y TODOS los spawns de producción, incluido el puesto.
    return target, {"base": (52, 52)}


class LotteryWorld(R10World):
    def state(self, index, predicate=lambda _v: True):
        return self.view(index, lambda v: bool(v.get("world_states", {}).get("lottery")) and predicate(v["world_states"]["lottery"]), "estado de lotería")["world_states"]["lottery"]

    def run(self, locations):
        self.deadline = time.monotonic() + 1000
        self.wait(lambda: all("INTEGRATION_WORLD: READY" in (self.output / f"godot-{i}.log").read_text() for i in (1, 2)), "login de ambos Godot", 60)
        with self.fixture.client() as store:
            self.ids = {i: int(store.hget(f"account:{self.names[i-1]}:data", "user_id")) for i in (1, 2)}
            npc_key = "npc:instance:lottery-ullathorpe"
            npc = store.hgetall(npc_key)
            assert npc["npc_id"] == "950" and npc["is_attackable"] == "False"
            assert len([k for k in store.scan_iter("npc:instance:*") if store.hget(k, "npc_id") == "950"]) == 1
            self.relocate(store, {1: (1, 58, 52), 2: (1, 54, 52)}, reset=True)
            self.command(1, "world_open", topic="lottery")
            remote = self.view(1, lambda v: v.get("world_window") == "lottery" and bool(v.get("world_window_state")), "consulta pública a distancia")
            assert remote["lottery_bet_disabled"]
            assert not remote["world_window_state"]["can_bet"]
            self.command(1, "close")
            self.relocate(store, {1: (1, 52, 52)})
            for i in (1, 2):
                seen = self.view(i, lambda v: v.get("character_names", {}).get(npc["char_index"], {}).get("visible"), "nombre del NPC amistoso visible")
                assert seen["character_names"][npc["char_index"]]["text"] == "Lotero de Ullathorpe"
                self.command(i, "click", x=53, y=52, double=True)
                self.view(i, lambda v: v.get("world_window") == "lottery" and v.get("world_window_state", {}).get("can_bet"), "diálogo físico automático")
                self.command(i, "capture", label="lottery-npc")
            self.passed("lottery-npc", "Puesto y nombre en ambos; consulta remota sin apostar; selección física")
            before = {i: int(store.hget(f"player:{self.ids[i]}:user_stats", "gold")) for i in (1, 2)}
            for i, amount in [(1, 100), (2, 300)]:
                self.command(i, "world_action", topic="lottery", action="bet", gross=amount)
                self.view(i, lambda v: not v.get("world_pending", True) and v.get("world_window_state", {}).get("gross") == amount, "confirmación económica de la apuesta")
            state = self.state(1, lambda s: s["pool"] == 396 and s["participants"] == 2)
            self.state(2, lambda s: s["pool"] == 396 and s["net"] == 297)
            rid, closes = state["round"], state["closes_at"]
            assert closes - int(store.hget(f"lottery:round:{rid}", "opened_at")) == 300
            for i, amount in [(1, 100), (2, 300)]:
                assert int(store.hget(f"player:{self.ids[i]}:user_stats", "gold")) == before[i] - amount
                self.command(i, "capture", label="lottery-bets")
            self.passed("lottery-bets", "100+300 brutos = 4 comisión + 396 netos; probabilidades 25/75", round=rid, commitment=state["commitment"], closes_at=closes)
            for i in (1, 2):
                self.command(i, "close")
                self.command(i, "logout")
                self.wait(lambda i=i: not store.exists(f"session:{self.ids[i]}:owner"), "desconexión antes del sorteo")
            print("LOTTERY: esperando cierre productivo de cinco minutos con ambos jugadores desconectados", flush=True)
            self.wait(lambda: store.hget(f"lottery:round:{rid}", "status") == "paid", "pago offline al cierre real", timeout=max(30, closes - time.time() + 35))
            winner = json.loads(store.get("lottery:last_winner"))
            assert winner["prize"] == 396 and winner["round"] == rid
            assert sum(int(store.hget(f"player:{uid}:user_stats", "gold")) for uid in self.ids.values()) == sum(before.values()) - 4
            paid_gold = {uid: store.hget(f"player:{uid}:user_stats", "gold") for uid in self.ids.values()}
            self.passed("lottery-offline", "Reloj real de 300 segundos y premio completo con ambos offline", winner=winner)
            for i in (1, 2):
                self.command(i, "login")
                self.state(i, lambda s: s.get("last_winner") == winner)
                self.console(i, winner["name"] + " ganó 396 oro")
                self.command(i, "world_open", topic="lottery")
                self.view(i, lambda v: winner["name"] in v.get("lottery_winner", ""), "ganador visible en el puesto")
                self.command(i, "capture", label="lottery-winner")
                self.command(i, "close")
                self.command(i, "logout")
            self.wait(lambda: all(not store.exists(f"session:{uid}:owner") for uid in self.ids.values()), "sesiones liberadas para reinicio")
            self.server = self.restart_server()
            assert len([k for k in store.scan_iter("npc:instance:*") if store.hget(k, "npc_id") == "950"]) == 1
            for i in (1, 2):
                self.command(i, "login")
                self.state(i, lambda s: s.get("last_winner") == winner)
                assert store.hget(f"player:{self.ids[i]}:user_stats", "gold") == paid_gold[self.ids[i]]
            self.passed("lottery-restart", "Reinicio conserva ganador, pago único y un solo NPC", source_godot=True, native_export=False)
        return self.steps
