"""Los doce accesorios reales se equipan por UI y sobreviven a una reconexión."""

import time

from full_world import FullWorld, prepare_fixture


def acceptance(steps, _seconds, **_kwargs):
    complete = {row["id"] for row in steps if row.get("passed")}
    required = {"accessory-all-items", "accessory-replace", "accessory-restrictions"}
    return {"test_execution_passed": required <= complete, "missing": sorted(required - complete), "r10_gameplay_passed": False}


class AccessoryWorld(FullWorld):
    def equipped(self, index, slot, expected):
        self.view(index, lambda v: v["items"].get(str(slot), [0, 0, False])[2] == expected, "marca de equipado del accesorio")

    def run(self, locations):
        from src.models.item_catalog import ItemCatalog
        from src.models.character_class import ClassCatalog

        self.deadline = time.monotonic() + 1200
        self.wait(lambda: all("INTEGRATION_WORLD: READY" in (self.output / f"godot-{i}.log").read_text() for i in (1, 2)), "dos clientes reales", 60)
        catalog, classes = ItemCatalog(), ClassCatalog().get_all_classes()
        accessories = {key: catalog.get_item_data(key) for key in catalog.get_all_item_ids() if catalog.get_item_data(key).get("ObjType") == 18}
        with self.fixture.client() as store:
            self.ids = {i: int(store.hget(f"account:{self.names[i-1]}:data", "user_id")) for i in (1, 2)}
            _, x, y = locations["skills_base"]
            self.base = {1: (2, x, y), 2: (2, x+1, y)}
            for item_id, item in sorted(accessories.items()):
                forbidden = item.get("ClasesProhibidas", [])
                job = next(c.class_id for c in classes if c.name.upper() not in forbidden)
                self.reset(store, items={1: (item_id, 1), 2: (697, 1)}, stats={"class_id": job})
                for index in (1, 2):
                    self.command(index, "equip", slot=1)
                    self.wait(lambda: store.hget(f"player:{self.ids[index]}:equipment", "accessory") == "1", "accesorio confirmado en Redis")
                    self.equipped(index, 1, True)
                    detail = self.command(index, "snapshot")["item_details"]["1"]
                    if detail["min_def"] != item.get("DefensaMagicaMin", 0) or detail["max_def"] != item.get("DefensaMagicaMax", 0):
                        raise RuntimeError("Rango de resistencia mágica incorrecto en la UI")
                    self.command(index, "logout")
                    self.wait(lambda: not store.exists(f"session:{self.ids[index]}:owner"), "liberar sesión")
                    self.command(index, "login")
                    self.equipped(index, 1, True)
                    self.command(index, "equip", slot=1)
                    self.equipped(index, 1, False)
                self.passed(f"accessory-{item_id}", item_id=item_id, class_id=job, both_clients=True, reconnected=True)
            self.passed("accessory-all-items", item_ids=sorted(accessories), count=len(accessories))
            self.reset(store, items={1: (697, 1), 2: (698, 1)}, stats={"class_id": 2})
            for index in (1, 2):
                self.command(index, "equip", slot=1)
                self.equipped(index, 1, True)
                self.command(index, "equip", slot=2)
                self.equipped(index, 1, False)
                self.equipped(index, 2, True)
            self.passed("accessory-replace", both_clients=True, one_slot=True)
            # Mage is explicitly forbidden for this thief-only glove.
            self.reset(store, items={1: (873, 1)}, stats={"class_id": 1})
            for index in (1, 2):
                self.command(index, "equip", slot=1)
                self.console(index, "Tu clase no puede")
                self.equipped(index, 1, False)
                if store.hget(f"player:{self.ids[index]}:equipment", "accessory") not in (None, "0"):
                    raise RuntimeError("La restricción de clase no se respetó")
            self.passed("accessory-restrictions", both_clients=True)
        for index in (1, 2): self.command(index, "soak")
        return self.steps
