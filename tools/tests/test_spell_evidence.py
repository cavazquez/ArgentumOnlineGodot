"""Rechaza el falso positivo de confirmar un cast sin aplicar su efecto."""

import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "spell_evidence", Path(__file__).parents[1] / "spell_evidence.py"
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class SpellEffectEvidenceTests(unittest.TestCase):
    def row(self):
        return {
            "cast_confirmed": True,
            "captured_at": 100,
            "state_before": {
                1: {"min_mana": "100", "min_hp": "100"},
                2: {"min_hp": "50"},
            },
            "state_after": {
                1: {"min_mana": "90", "min_hp": "100"},
                2: {"min_hp": "50"},
            },
        }

    def test_ack_without_damage_is_not_accepted(self):
        row = self.row()
        spell = {"id": 2, "min_damage": 2}
        self.assertTrue(module.check_effects(row, spell))
        row["state_after"][2]["min_hp"] = "40"
        self.assertFalse(module.check_effects(row, spell))

    def test_buff_requires_real_modifier_and_preserves_base(self):
        row = self.row()
        spell = {"id": 20, "increases_strength": True}
        row["attributes_before"] = {2: {"strength": "20"}}
        row["attributes_after"] = {2: {"strength": "20"}}
        self.assertTrue(module.check_effects(row, spell))
        row["attributes_after"][2].update(
            strength_modifier_value="3", strength_modifier_until="500"
        )
        self.assertFalse(module.check_effects(row, spell))
        row["attributes_after"][2]["strength"] = "23"
        self.assertTrue(module.check_effects(row, spell))

    def test_hunger_requires_resource_change(self):
        row = self.row()
        spell = {"id": 12}
        row["needs_before"] = {2: {"min_hunger": "100"}}
        row["needs_after"] = {2: {"min_hunger": "100"}}
        self.assertTrue(module.check_effects(row, spell))
        row["needs_after"][2]["min_hunger"] = "50"
        self.assertFalse(module.check_effects(row, spell))

    def test_reserved_cast_cannot_charge_mana(self):
        row = self.row()
        row["cast_confirmed"] = False
        self.assertTrue(module.check_effects(row, {"id": 22}))
        row["state_after"][1]["min_mana"] = "100"
        self.assertFalse(module.check_effects(row, {"id": 22}))

    def test_revive_and_drain_need_actual_hp_change(self):
        row = self.row()
        row["state_after"][2]["min_hp"] = "0"
        self.assertTrue(module.check_effects(row, {"id": 11, "revives": True}))
        row["state_after"][2]["min_hp"] = "10"
        self.assertFalse(module.check_effects(row, {"id": 11, "revives": True}))
        self.assertTrue(module.check_effects(row, {"id": 45, "min_damage": 5}))
        row["state_after"][1]["min_hp"] = "110"
        self.assertFalse(module.check_effects(row, {"id": 45, "min_damage": 5}))
