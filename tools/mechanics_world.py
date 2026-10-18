"""Regresión gráfica de hechizos sobre un wheel instalado y Redis descartable."""

import json
import os
import time
import tomllib
from pathlib import Path

from r10_world import R10World, prepare_fixture
from src.runtime_paths import data_dir

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
SKILLS = json.loads((ROOT / "protocol/skills.json").read_text())["skills"]
SPELLS = tomllib.loads((data_dir() / "spells.toml").read_text())["spell"]
SELECTED = {
    int(v) for v in os.environ.get("AO_MECHANICS_SPELL_IDS", "").split(",") if v
}
CASES = {"selected_spells"} if SELECTED else {"all_spells", "fx_resources"}


def acceptance(steps, seconds, **_):
    executed = {s["id"] for s in steps if s.get("test_executed")}
    return {
        "kind": "mechanics and spell animation audit; not a new R10 acceptance",
        "test_execution_passed": CASES <= executed,
        "executed": sorted(executed),
        "r10_gameplay_passed": False,
    }


class MechanicsWorld(R10World):
    def check_processes(self):
        super().check_processes()

    def save(self):
        (self.output / "probe-actions.json").write_text(
            json.dumps(self.receipts, indent=2) + "\n"
        )
        (self.output / "probe-cases.json").write_text(
            json.dumps(self.steps, indent=2) + "\n"
        )

    def passed(self, key, requirement="", **observations):
        self.steps.append(
            {"id": key, "test_executed": True, "observations": observations}
        )
        self.save()
        print("MECHANICS_PROBE: EXECUTED", key, flush=True)

    def skill_state(self, store, index=1):
        return store.hgetall(f"player:{self.ids[index]}:skills")

    def pets(self, store):
        return [
            store.hgetall(k)
            for k in store.scan_iter("npc:instance:*")
            if store.hget(k, "summoned_by_user_id") == str(self.ids[1])
        ]

    def offline(self, store, positions, change=None):
        for i in positions:
            self.command(i, "logout")
            self.wait(
                lambda i=i: not store.exists(f"session:{self.ids[i]}:owner"),
                "liberación para fixture",
            )
        for i, (map_id, x, y) in positions.items():
            store.hset(
                f"player:{self.ids[i]}:position",
                mapping={"map": map_id, "x": x, "y": y, "heading": 1},
            )
        if change:
            change()
        for i in positions:
            self.command(i, "login")
            self.view(i, lambda v, i=i: v["map"] == positions[i][0], "mapa del fixture")

    def screen(self, label, index=1):
        self.command(
            index, "screenshot", path=str(self.output / f"{label}-{index}.png")
        )

    def run(self, locations):
        self.deadline = time.monotonic() + 900
        self.wait(
            lambda: all(
                "INTEGRATION_WORLD: READY"
                in (self.output / f"godot-{i}.log").read_text()
                for i in (1, 2)
            ),
            "dos clientes reales",
            60,
        )
        with self.fixture.client() as store:
            self.ids = {
                i: int(store.hget(f"account:{self.names[i - 1]}:data", "user_id"))
                for i in (1, 2)
            }
            initial = {i: self.skill_state(store, i) for i in (1, 2)}
            self.initial_points = int(initial[1].get("points", 0))
            x, y = locations["base"]
            self.base = {1: (1, x, y), 2: (1, x + 1, y)}
            self.relocate(store, self.base, reset=True)

            def normalize():
                for i in (1, 2):
                    store.hset(
                        f"player:{self.ids[i]}:skills",
                        mapping={
                            "progress_version": 2,
                            "assigned_points": 10,
                            "natural_xp_base": 200,
                            "points_granted_through": 40,
                        },
                    )

            self.offline(store, self.base, normalize)
            # Regresión nueva; los artefactos de la auditoría anterior quedan intactos.
            self.spells(store)
            if not SELECTED:
                fx_ids = sorted(
                    {int(s["fx_grh"]) for s in SPELLS if s.get("fx_grh", 0) > 0}
                )
                self.command(1, "resources", ids=fx_ids, folder=str(self.output))
                self.passed("fx_resources", ids=fx_ids)
            self.relocate(store, self.base, reset=True)
            for i in (1, 2):
                self.command(i, "soak")
        return self.steps

    def spells(self, store):
        from src.services.map.map_resources_service import MapResourcesService

        resource = MapResourcesService().resources["map_2"]
        blocked = resource["blocked"] | resource["water"]
        x, y = next(
            (x, y)
            for x in range(20, 80)
            for y in range(20, 80)
            if all(
                (a, b) not in blocked
                for a in range(x - 3, x + 4)
                for b in range(y - 3, y + 4)
            )
        )
        positions = {1: (2, x, y), 2: (2, x + 1, y)}
        records = []
        for spell in SPELLS:
            sid = spell["id"]
            if SELECTED and sid not in SELECTED:
                continue
            # Quitar mascotas con el comando público antes de preparar el caso siguiente.
            for _ in range(4):
                count = len(self.pets(store))
                if not count:
                    break
                self.command(1, "chat", text="/PET LIBERAR")
                self.wait(
                    lambda: len(self.pets(store)) < count, "liberar mascota previa"
                )

            def seed():
                for i in (1, 2):
                    key = f"player:{self.ids[i]}:user_stats"
                    values = store.hgetall(key)
                    store.hset(
                        key,
                        mapping={
                            **{k: 0 for k in values if k.endswith("_until")},
                            "max_hp": 30000,
                            "min_hp": 25000,
                            "max_mana": 30000,
                            "min_mana": 30000,
                            "max_sta": 30000,
                            "min_sta": 30000,
                            "level": 40,
                            "elu": 9999999,
                            "safe_mode": 0,
                            "death_state": "complete",
                        },
                    )
                    store.hset(
                        f"player:{self.ids[i]}:hunger_thirst",
                        mapping={
                            "max_water": 100,
                            "min_water": 100,
                            "max_hunger": 100,
                            "min_hunger": 100,
                            "hunger_flag": 0,
                            "thirst_flag": 0,
                        },
                    )
                store.hset(
                    f"player:{self.ids[1]}:skills",
                    mapping={"level:magia": 100, "xp:magia": 0},
                )
                book = f"player:{self.ids[1]}:spellbook"
                store.delete(book)
                store.hset(book, mapping={"1": sid, "2": 16})
                store.hset(f"player:{self.ids[1]}:equipment", mapping={"weapon": 27})
                if sid == 1:
                    store.hset(
                        f"player:{self.ids[2]}:user_stats",
                        mapping={"poisoned_until": time.time() + 300},
                    )
                if sid == 11:
                    store.hset(
                        f"player:{self.ids[2]}:user_stats",
                        mapping={"min_hp": 0, "death_state": "complete"},
                    )
                if sid in (10, 41):
                    store.hset(
                        f"player:{self.ids[2]}:user_stats",
                        mapping={
                            "immobilized_until": time.time() + 300,
                            "dumb_until": time.time() + 300,
                        },
                    )

            self.offline(store, positions, seed)
            if sid == 46:
                for i in (1, 2):
                    self.command(i, "capture_reset", label="helper-for-46")
                self.command(
                    1,
                    "cast_probe",
                    slot=2,
                    x=x,
                    y=y + 1,
                    path=str(self.output / "helper-for-46.png"),
                )
                self.wait(lambda: self.pets(store), "mascota para invocar al dueño")
            for i in (1, 2):
                self.command(i, "capture_reset", label=f"spell-{sid}")
            before = {
                i: store.hgetall(f"player:{self.ids[i]}:user_stats") for i in (1, 2)
            }
            before_views = {i: self.command(i, "snapshot") for i in (1, 2)}
            errors_before = len((self.output / "server.log").read_bytes())
            target_x, target_y = (
                (x, y + 1)
                if spell.get("invokes") or spell.get("warps_pet")
                else (x + 1, y)
            )
            self.command(
                1,
                "cast_probe",
                slot=1,
                x=target_x,
                y=target_y,
                path=str(self.output / f"spell-{sid}.png"),
            )
            one = self.command(1, "snapshot")
            two = self.command(2, "snapshot")
            after = {
                i: store.hgetall(f"player:{self.ids[i]}:user_stats") for i in (1, 2)
            }
            mana_before = int(before[1]["min_mana"])
            mana_after = int(after[1]["min_mana"])
            messages = [
                p["message"] for p in one["fx_packets"] if p["kind"] == "console"
            ]
            accepted = any(
                "Has lanzado " + spell["name"] in message for message in messages
            )
            expected_fx = int(spell.get("fx_grh", 0))
            row = {
                "id": sid,
                "name": spell["name"],
                "min_skill": spell["min_skill"],
                "expected_restricted": spell["min_skill"] > 100,
                "cast_confirmed": accepted,
                "mana_before": mana_before,
                "mana_after": mana_after,
                "expected_fx": expected_fx,
                "loops": spell["loops"],
                "caster_fx_packets": [
                    p for p in one["fx_packets"] if p["kind"] == "fx"
                ],
                "peer_fx_packets": [p for p in two["fx_packets"] if p["kind"] == "fx"],
                "caster_sounds": [p for p in one["fx_packets"] if p["kind"] == "sound"],
                "peer_sounds": [p for p in two["fx_packets"] if p["kind"] == "sound"],
                "caster_frames": one["fx_frames"],
                "peer_frames": two["fx_frames"],
                "visual_shown": any(f["fx"] == expected_fx for f in one["fx_frames"])
                if expected_fx
                else None,
                "server_messages": messages,
                "console_visible": one["console"],
                "state_before": before,
                "state_after": after,
                "pets": self.pets(store),
                "caster_appearance": one["appearance"],
                "target_appearance": two["appearance"],
                "server_log_delta": (self.output / "server.log")
                .read_bytes()[errors_before:]
                .decode(errors="replace"),
            }
            row["before_views"] = before_views
            row["after_views"] = {1: one, 2: two}
            row["caster_audio_playback"] = one.get("audio_playback", [])
            row["peer_audio_playback"] = two.get("audio_playback", [])
            records.append(row)
            (self.output / "spells.json").write_text(
                json.dumps(records, ensure_ascii=False, indent=2) + "\n"
            )
            print(
                "SPELL_PROBE",
                sid,
                spell["name"],
                "cast",
                accepted,
                "fx",
                expected_fx,
                "shown",
                row["visual_shown"],
                flush=True,
            )
        failures = []
        for row in records:
            sid = row["id"]
            spell = next(s for s in SPELLS if s["id"] == sid)
            if row["cast_confirmed"] == row["expected_restricted"]:
                failures.append(f"{sid}: confirmación/reserva incorrecta")
            if (
                "Traceback" in row["server_log_delta"]
                or "ERROR" in row["server_log_delta"]
            ):
                failures.append(f"{sid}: error de servidor")
            if row["cast_confirmed"] and row["expected_fx"]:
                for label in ("caster", "peer"):
                    packets = row[label + "_fx_packets"]
                    frames = row[label + "_frames"]
                    if not any(
                        p["fx"] == row["expected_fx"] and p["char_index"] > 0
                        for p in packets
                    ):
                        failures.append(f"{sid}: FX/actor ausente en {label}")
                    if not any(
                        f["fx"] == row["expected_fx"] and f["visible"] and f["playing"]
                        for f in frames
                    ):
                        failures.append(f"{sid}: animación ausente en {label}")
            wave = int(spell.get("wav", 0))
            if row["cast_confirmed"] and wave:
                for label in ("caster", "peer"):
                    if not row[label + "_sounds"] or not any(
                        f["resource"].endswith(f"/{wave}.wav")
                        for f in row[label + "_audio_playback"]
                    ):
                        failures.append(
                            f"{sid}: reproducción de sonido ausente en {label}"
                        )
            if sid in (11, 42) and row["cast_confirmed"]:
                for i in (1, 2):
                    actor = str(self.ids[2] if sid == 11 else self.ids[1])
                    if not row["after_views"][i]["actor_visibility"][actor][
                        "renderer_visible"
                    ]:
                        failures.append(f"{sid}: personaje vivo oculto en cliente {i}")
            if sid == 14 and row["cast_confirmed"]:
                for i in (1, 2):
                    if row["after_views"][i]["actor_visibility"][str(self.ids[2])][
                        "renderer_visible"
                    ]:
                        failures.append(
                            f"{sid}: invisibilidad no oculta en cliente {i}"
                        )
            if sid == 46 and row["cast_confirmed"]:
                if not row["pets"] or any(
                    (int(p["x"]), int(p["y"])) in {(x, y), (x + 1, y)}
                    for p in row["pets"]
                ):
                    failures.append("46: mascota solapada con jugador")
        (self.output / "spell-assertions.json").write_text(
            json.dumps(
                {"cases": len(records), "failures": failures, "passed": not failures},
                ensure_ascii=False,
                indent=2,
            )
            + "\n"
        )
        if failures:
            raise RuntimeError("Regresión de hechizos: " + "; ".join(failures))
        self.passed(
            "selected_spells" if SELECTED else "all_spells",
            count=len(records),
            confirmed=sum(r["cast_confirmed"] for r in records),
            fx_shown=sum(r["visual_shown"] is True for r in records),
        )
