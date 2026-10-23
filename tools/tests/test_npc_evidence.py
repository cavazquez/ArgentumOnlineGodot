"""Una muestra breve de NPC no acredita voces ausentes ni la campaña R10."""

import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).parents[1]))
import npc_world


class NPCEvidenceTests(unittest.TestCase):
    def test_friendly_lottery_name_and_hostile_pet_names(self):
        self.assertTrue(npc_world.name_visible({"role": "lottery"}))
        self.assertFalse(npc_world.name_visible({"role": "animal"}))
        for field, value in (("is_hostile", "True"), ("is_tamed", "True"), ("summoned_by_user_id", "1")):
            self.assertFalse(npc_world.name_visible({"role": "lottery", field: value}))

    def test_far_positions_use_the_last_update_but_visible_drift_is_rejected(self):
        expected = {"10001": [10, 10, 13, 0], "10002": [51, 50, 13, 0]}
        actual = {"10001": [11, 10, 13, 0], "10002": [51, 50, 13, 0]}
        self.assertEqual(npc_world.representation_differences(expected, actual, (55, 53), 15), [])
        actual["10002"][1] = 51
        self.assertEqual(len(npc_world.representation_differences(expected, actual, (55, 53), 15)), 1)

    def test_far_identity_or_appearance_is_still_checked(self):
        expected = {"10001": [10, 10, 13, 0]}
        for actual in ({}, {"10001": [10, 10, 71, 0]}):
            self.assertEqual(len(npc_world.representation_differences(expected, actual, (55, 53), 15)), 1)

    def test_ghost_in_visible_range_is_checked_even_if_server_position_is_far(self):
        expected = {"10001": [10, 10, 13, 0]}
        actual = {"10001": [51, 50, 13, 0]}
        self.assertEqual(len(npc_world.representation_differences(expected, actual, (55, 53), 15)), 1)

    def test_missing_scenario_or_failed_step_is_not_accepted(self):
        steps = [{"id": key, "passed": key != "npc-map-transition"} for key in npc_world.REQUIRED]
        self.assertFalse(npc_world.acceptance(steps, 1800, graphical=True)["test_execution_passed"])

    def test_short_graphical_sample_has_its_own_scope(self):
        steps = [{"id": key, "passed": True} for key in npc_world.REQUIRED]
        value = npc_world.acceptance(steps, 15, graphical=True)
        self.assertTrue(value["test_execution_passed"])
        self.assertFalse(value["r10_gameplay_passed"])
        self.assertFalse(value["npc_sounds_in_live_catalog_proven"])
        self.assertFalse(npc_world.acceptance(steps, 1800, graphical=False)["test_execution_passed"])
