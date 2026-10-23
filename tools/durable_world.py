"""Equipo individual real: dos observadores, conservación, combate, caducidad y oficios."""

import time

from equipment_world import EquipmentWorld, acceptance as equipment_acceptance, prepare_fixture

EXTRA = {"individual-ui", "individual-bank-ground", "individual-combat", "individual-expiry", "individual-gathering", "individual-trade"}


def acceptance(steps, seconds, **kwargs):
    result = equipment_acceptance(steps, seconds, **kwargs)
    result["missing"] += sorted(EXTRA - {row["id"] for row in steps if row.get("passed")})
    result["test_execution_passed"] = not result["missing"]
    return result


class DurableWorld(EquipmentWorld):
    def extra_checks(self, store, locations):
        from src.utils.inventory_slot import InventorySlot

        self.data["items"] = {"1": [2, 1], "2": [2, 1], "3": [1055, 1], "4": [561, 1], "5": [562, 1], "6": [563, 1]}
        x, y = locations["base"]
        self.relocate(store, {1: (1, x, y), 2: (1, x+1, y)}, reset=True)
        key = f"player:{self.ids[1]}:inventory"
        identities = {slot: InventorySlot.parse(value).instance_ids[0] for slot, value in store.hgetall(key).items() if slot.startswith("slot_") and value}
        assert identities["slot_1"] != identities["slot_2"]
        weapon = "item:instance:" + identities["slot_1"]
        boot = "item:instance:" + identities["slot_3"]
        self.command(1, "logout")
        self.wait(lambda: not store.exists(f"session:{self.ids[1]}:owner"), "preparación offline del desgaste")
        store.hset(weapon, mapping={"uses_spent": 5000})
        store.hset(boot, mapping={"created_at": int(time.time()) - 4, "expires_at": int(time.time()) + 6, "lifetime_seconds": 10})
        original = store.hgetall(weapon)
        self.command(1, "login")
        self.view(1, lambda v: v.get("item_conditions", {}).get("inventory", {}).get("1", {}).get("uses") == 5000, "desgaste recibido al reconectar")
        self.command(1, "equip", slot=3)
        self.view(1, lambda v: v.get("actor_equipment", {}).get(str(self.ids[1]), {}).get("boots", {}).get("id") == 1, "botas individuales equipadas")
        self.passed("individual-ui", "Dos espadas iguales con identidad y estado propios", identities_distinct=True)
        self.command(1, "click", x=x+2, y=y-2, double=True)
        self.view(1, lambda v: v["panel"] == "bank", "banco abierto")
        self.command(1, "bank_item", deposit=True, slot=1, amount=1)
        self.wait(lambda: bool((slot := InventorySlot.parse(store.hget(f"bank:{self.ids[1]}:vault", "slot_1"))) and slot.instance_ids == (identities["slot_1"],)), "identidad en bóveda")
        self.view(1, lambda v: v.get("item_conditions", {}).get("bank", {}).get("1", {}).get("uses") == 5000, "condición de la espada depositada")
        self.command(1, "bank_item", deposit=False, slot=1, amount=1)
        self.wait(lambda: self.count(store, 1, 2) == 2, "retiro del ejemplar")
        self.command(1, "close")
        self.command(1, "drop", slot=1, amount=1)
        self.wait(lambda: self.count(store, 1, 2) == 1, "caída individual al suelo")
        self.command(1, "pickup")
        self.wait(lambda: self.count(store, 1, 2) == 2, "recogida del ejemplar")
        preserved = store.hgetall(weapon)
        assert all(original[field] == preserved[field] for field in ("created_at", "expires_at", "uses_spent"))
        self.passed("individual-bank-ground", "Banco y suelo conservan identidad, usos y antigüedad", preserved=True)
        for source, target in ((1, 2), (2, 1)):
            self.command(source, "chat", text="/COMERCIAR " + self.names[target - 1])
            self.view(target, lambda v: v.get("panel") == "trade", "invitación al intercambio individual")
            self.command(target, "trade", action="accept")
            self.view(source, lambda v: v.get("trade", {}).get("state") == "active", "intercambio individual activo")
            source_slot = int(store.hget(weapon, "location").split("slot_")[-1])
            self.command(source, "trade", action="item", slot=source_slot, amount=1)
            self.view(target, lambda v: v.get("item_conditions", {}).get("trade_other", {}).get(str(source_slot), {}).get("id") == identities["slot_1"], "identidad y condición mostradas al destinatario")
            for viewer in (source, target):
                self.view(viewer, lambda v: v.get("trade_conditions_ready") and not v.get("trade_confirm_disabled", True), "datos individuales listos para confirmar")
            self.command(source, "capture", label=f"worn-trade-{source}")
            for viewer in (source, target): self.command(viewer, "trade", action="confirm")
            self.wait(lambda: store.hget(weapon, "location").startswith(f"player:{self.ids[target]}:inventory|"), "transferencia del ejemplar confirmado")
            destination_slot = store.hget(weapon, "location").split("slot_")[-1]
            self.view(target, lambda v: v.get("item_conditions", {}).get("inventory", {}).get(destination_slot, {}).get("uses") == 5000, "desgaste conservado en el inventario receptor")
            for viewer in (source, target): self.command(viewer, "close")
        self.passed("individual-trade", "Dos clientes muestran y transfieren el mismo ejemplar gastado en ambas direcciones", same_identity=True, preserved_uses=5000)
        self.view(1, lambda v: v.get("item_conditions", {}).get("inventory", {}).get("3", {}).get("broken"), "vencimiento de botas sin reconectar")
        self.console(1, "está roto")
        self.command(1, "capture", label="boots-expired")
        self.passed("individual-expiry", "Equipo vence conectado y avisa sin retirar su capa gráfica", passive_expiry=True)
        hostiles = [store.hgetall(k) for k in store.scan_iter("npc:instance:*") if store.hget(k, "npc_id") == "500"]
        self.targets = {"combat": hostiles[0]["instance_id"]}
        positions = self.encounter(store, locations, "combat", 1, 2)
        self.command(1, "equip", slot=1)
        self.view(1, lambda v: v["items"].get("1", [0, 0, False])[2], "espada gastada equipada")
        def attack_until(predicate):
            for _ in range(20):
                target = store.hgetall(f"npc:instance:{self.targets['combat']}")
                position = store.hgetall(f"player:{self.ids[1]}:position")
                dx, dy = int(target["x"]) - int(position["x"]), int(target["y"]) - int(position["y"])
                direction = ("ui_right" if dx > 0 else "ui_left") if abs(dx) >= abs(dy) else ("ui_down" if dy > 0 else "ui_up")
                self.command(1, "move", action=direction, seconds=0.12)
                self.command(1, "attack")
                if predicate(): return
                time.sleep(0.6)
            raise AssertionError("No se alcanzó al NPC móvil mediante los controles reales")
        attack_until(lambda: int(store.hget(weapon, "uses_spent")) > 5000)
        assert int(store.hget(weapon, "uses_spent")) > 5000
        self.command(1, "logout")
        self.wait(lambda: not store.exists(f"session:{self.ids[1]}:owner"), "agotar ejemplar con el jugador desconectado")
        store.hset(weapon, "uses_spent", store.hget(weapon, "max_uses"))
        self.command(1, "login")
        self.view(1, lambda v: v.get("gear_labels", {}).get("weapon") == "0/0", "arma rota sin estadísticas en HUD")
        spent = store.hget(weapon, "uses_spent")
        # El golpe anterior puede matar al objetivo. Usar otro NPC vivo real;
        # no asumir que una identidad eliminada todavía conserva coordenadas.
        survivors = [row for key in store.scan_iter("npc:instance:*")
                     if (row := store.hgetall(key)) and row.get("npc_id") == "500" and int(row.get("hp", 0)) > 0]
        assert survivors, "No queda un NPC vivo para comprobar el rechazo del arma rota"
        self.targets["combat"] = survivors[0]["instance_id"]
        self.encounter(store, locations, "combat", 1, 2)
        attack_until(lambda: "arma está rota" in self.command(1, "snapshot")["console"].lower())
        self.console(1, "arma está rota")
        assert store.hget(weapon, "uses_spent") == spent
        self.passed("individual-combat", "Golpe válido consume uso; arma rota no ataca ni gasta de nuevo", accepted_spends=True, broken_rejected=True)
        self.jobs(store, locations)
        for slot in (4, 5, 6):
            assert int(store.hget("item:instance:" + identities[f"slot_{slot}"], "uses_spent")) > 0
        self.passed("individual-gathering", "Talar, minar y pescar gastan usos en herramientas individuales", tools=[561, 562, 563])
        x, y = locations["base"]
        self.relocate(store, {1: (1, x, y), 2: (1, x+1, y)})
