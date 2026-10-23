"""Regresión gráfica de protocolo, combate, bóveda y ficha pública del clan."""

import json
import time

from r10_world import REQUIRED_SCENARIOS, R10World, prepare_fixture

EXTRA = {"bank_reorder", "clan_profile", "storage_restart"}


def acceptance(steps, seconds, *, graphical, exported=False):
    completed = {step["id"] for step in steps if step.get("passed")}
    missing = sorted((REQUIRED_SCENARIOS | EXTRA) - completed)
    return {
        "required": sorted(REQUIRED_SCENARIOS | EXTRA),
        "completed": sorted(completed),
        "missing": missing,
        "functional_passed": not missing,
        "graphical_passed": graphical and not missing,
        "test_execution_passed": graphical and not missing,
    }


class StorageProtocolWorld(R10World):
    def base_scenario(self, locations):
        # The full source-client campaign includes twelve account creations and
        # repeated reconnects. Keep each action's deadline, but budget this larger
        # campaign separately from the original exported-client smoke run.
        self.deadline = time.monotonic() + 1200
        super().run(locations, soak=False)

    def run(self, locations):
        self.base_scenario(locations)
        self.deadline = time.monotonic() + 900
        with self.fixture.client() as store:
            x, y = locations["base"]
            self.relocate(store, {1: (1, x, y), 2: (1, x + 1, y)}, reset=True)
            self.bank_reorder(store, x, y)
            self.clan_profile(store)
            for i in (1, 2):
                self.command(i, "close")
                self.command(i, "logout")
                self.wait(
                    lambda i=i: not store.exists(f"session:{self.ids[i]}:owner"),
                    "liberar sesión antes de reiniciar",
                )
            self.server = self.restart_server()
            for i in (1, 2):
                self.command(i, "login")
                self.command(i, "world_open", topic="clan")
                self.view(
                    i,
                    lambda v: (
                        v.get("world_window_state", {}).get("profile", {}).get("version") == 4
                    ),
                    "ficha conservada al reiniciar y reconectar",
                )
                self.command(i, "capture", label="clan-profile")
                self.command(i, "close")
            self.command(1, "click", x=x + 2, y=y - 2, double=True)
            self.view(
                1,
                lambda v: v.get("bank_items", {}).get("1") == [15, 1],
                "orden bancario conservado al reiniciar",
            )
            self.command(1, "capture", label="bank-reordered")
            self.command(1, "close")
            self.passed(
                "storage_restart",
                "#592/#593",
                bank_and_profile_persisted=True,
                real_server_restart=True,
            )
            for i in (1, 2):
                self.command(i, "soak")
        return self.steps

    def bank_reorder(self, store, x, y):
        self.command(1, "click", x=x + 2, y=y - 2, double=True)
        self.view(1, lambda v: v.get("panel") == "bank", "bóveda abierta para arrastrar")
        self.command(1, "bank_item", deposit=True, slot=self.slot(store, 1, 15), amount=1)
        self.view(
            1,
            lambda v: v.get("world_states", {}).get("bank", {}).get("slots") == [[1, 15, 1]],
            "revisión del depósito confirmada",
        )
        self.command(1, "bank_move", source=1, destination=40)
        self.view(
            1,
            lambda v: (
                not v.get("bank_pending", True)
                and v.get("bank_items", {}).get("40") == [15, 1]
                and "1" not in v.get("bank_items", {})
            ),
            "arrastrar al último slot confirmado",
        )
        other = next(item for item, qty in self.data["items"].values() if item != 15)
        self.command(1, "bank_item", deposit=True, slot=self.slot(store, 1, other), amount=1)
        self.view(
            1,
            lambda v: (
                v.get("world_states", {}).get("bank", {}).get("slots")
                == [[1, other, 1], [40, 15, 1]]
            ),
            "revisión posterior al segundo depósito",
        )
        self.command(1, "bank_move", source=40, destination=1)
        self.view(
            1,
            lambda v: (
                not v.get("bank_pending", True)
                and v.get("bank_items", {}).get("1") == [15, 1]
                and v.get("bank_items", {}).get("40") == [other, 1]
            ),
            "intercambio de dos slots ocupados",
        )
        before = store.hgetall(f"bank:{self.ids[1]}:vault")
        self.command(1, "capture", label="bank-swap")
        self.command(1, "close")
        self.relocate(store, {1: (1, x, y)})
        self.command(1, "click", x=x + 2, y=y - 2, double=True)
        self.view(
            1,
            lambda v: v.get("bank_items", {}).get("40") == [other, 1],
            "orden bancario tras reconectar",
        )
        assert store.hgetall(f"bank:{self.ids[1]}:vault") == before
        self.command(1, "close")
        self.passed(
            "bank_reorder",
            "#592/#234",
            empty_and_occupied=True,
            last_slot=40,
            reconnect=True,
            conserved=True,
        )

    def clan_profile(self, store):
        self.command(1, "chat", text=f"/INVITARCLAN {self.names[1]}")
        self.console(2, "invit")
        self.command(2, "chat", text="/ACEPTARCLAN")
        clan = int(store.get(f"user:{self.ids[1]}:clan"))
        self.wait(
            lambda: store.get(f"user:{self.ids[2]}:clan") == str(clan),
            "miembro reincorporado al clan",
        )
        for i in (1, 2):
            self.command(i, "world_open", topic="clan")
            self.view(
                i,
                lambda v: v.get("world_window_state", {}).get("clan_id") == clan,
                "consulta propia del clan",
            )
        self.view(
            2, lambda v: v.get("clan_draft", {}).get("disabled"), "miembro sin permiso de edición"
        )
        self.command(
            1,
            "clan_draft",
            description="Códice de prueba",
            news="Noticias confirmadas",
            website="https://example.invalid/clan",
        )
        self.command(1, "clan_save")
        for i in (1, 2):
            self.view(
                i,
                lambda v: (
                    v.get("world_window_state", {}).get("profile", {}).get("version") == 1
                    and v["world_window_state"]["profile"]["news"] == "Noticias confirmadas"
                ),
                "ficha publicada visible al otro miembro",
            )
        self.command(1, "clan_draft", description="Borrador conservado")
        # Fault fixture: emulate an already committed concurrent edit while the form is dirty.
        store.hset(
            f"clan:{clan}:profile", mapping={"description": "Edición concurrente", "revision": "2"}
        )
        self.view(
            1,
            lambda v: (
                v.get("clan_draft", {}).get("description") == "Borrador conservado"
                and v["clan_draft"]["disabled"]
            ),
            "borrador conservado ante cambio concurrente",
        )
        self.command(1, "clan_rebase")
        self.command(1, "clan_save")
        self.view(
            2,
            lambda v: v.get("world_window_state", {}).get("profile", {}).get("version") == 3,
            "edición revisada y confirmada",
        )
        self.command(1, "clan_draft", description="Borrador del exlíder")
        self.command(1, "world_action", topic="clan", action="transfer", user=self.ids[2])
        self.view(
            1,
            lambda v: (
                v.get("clan_draft", {}).get("disabled")
                and v["clan_draft"]["description"] == "Borrador del exlíder"
            ),
            "revocación sin perder borrador",
        )
        self.command(
            1,
            "world_raw",
            action="clan.profile",
            params={
                "clan": clan,
                "version": 3,
                "description": "No autorizado",
                "news": "",
                "website": "",
            },
        )
        self.view(
            1,
            lambda v: (
                v.get("world_states", {}).get("result", {}).get("applied") is False
                and "líder" in v["world_states"]["result"].get("message", "")
            ),
            "servidor rechaza escritura del exlíder",
        )
        assert store.hget(f"clan:{clan}:profile", "description") == "Borrador conservado"
        self.view(
            2, lambda v: not v.get("clan_draft", {}).get("disabled", True), "nuevo líder habilitado"
        )
        self.command(2, "clan_draft", news="Noticias del nuevo líder")
        self.command(2, "clan_save")
        self.view(
            1,
            lambda v: v.get("world_window_state", {}).get("profile", {}).get("version") == 4,
            "ficha del nuevo líder visible al exlíder",
        )
        self.passed(
            "clan_profile",
            "#593/#235",
            leader_and_member=True,
            concurrent_draft=True,
            leader_transfer=True,
            server_rejects_ex_leader=True,
        )


def fast_acceptance(steps, seconds, *, graphical, exported=False):
    completed = {step["id"] for step in steps if step.get("passed")}
    missing = sorted(EXTRA - completed)
    return {
        "required": sorted(EXTRA),
        "completed": sorted(completed),
        "missing": missing,
        "functional_passed": not missing,
        "graphical_passed": graphical and not missing,
        "test_execution_passed": graphical and not missing,
        "full_r10": False,
    }


class FastStorageProtocolWorld(StorageProtocolWorld):
    def base_scenario(self, locations):
        self.wait(
            lambda: all(
                "INTEGRATION_WORLD: READY" in (self.output / f"godot-{i}.log").read_text()
                for i in (1, 2)
            ),
            "alta de ambos clientes",
            60,
        )
        with self.fixture.client() as store:
            self.ids = {
                i: int(store.hget(f"account:{self.names[i - 1]}:data", "user_id")) for i in (1, 2)
            }
            x, y = locations["base"]
            self.relocate(store, {1: (1, x, y), 2: (1, x + 1, y)}, reset=True)
            self.social(store)
