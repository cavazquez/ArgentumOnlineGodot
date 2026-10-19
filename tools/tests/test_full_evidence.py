"""Las actividades adicionales y las 22 habilidades son obligatorias para la fase."""

from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).parents[1]))
from full_evidence import FULL_REQUIRED, acceptance
from r10_world import REQUIRED_SCENARIOS


class FullAcceptanceTests(unittest.TestCase):
    def steps(self):
        return [
            {"id": key, "passed": True} for key in REQUIRED_SCENARIOS | FULL_REQUIRED
        ] + [
            {"id": f"skill-{i}", "passed": True, "observations": {"skill": i}}
            for i in range(1, 23)
        ]

    def test_complete_native_campaign_qualifies(self):
        self.assertTrue(
            acceptance(self.steps(), 1800, graphical=True, exported=True)[
                "r10_gameplay_passed"
            ]
        )

    def test_failed_navigation_cannot_be_replaced_by_duration(self):
        steps = self.steps()
        next(s for s in steps if s["id"] == "full-navigation")["passed"] = False
        result = acceptance(steps, 3600, graphical=True, exported=True)
        self.assertFalse(result["test_execution_passed"])
        self.assertIn("full-navigation", result["full_missing"])

    def test_failed_skill_observation_does_not_count(self):
        steps = self.steps()
        next(s for s in steps if s["id"] == "skill-22")["passed"] = False
        result = acceptance(steps, 1800, graphical=True, exported=True)
        self.assertFalse(result["r10_gameplay_passed"])
        self.assertNotIn(22, result["skills"])

    def test_short_editor_run_is_only_a_functional_regression(self):
        result = acceptance(self.steps(), 10, graphical=True, exported=False)
        self.assertTrue(result["test_execution_passed"])
        self.assertFalse(result["r10_gameplay_passed"])

    def test_legacy_skill_names_do_not_break_the_phase_summary(self):
        steps = self.steps()
        next(step for step in steps if step["id"] == "wood")["observations"] = {
            "skill": "talar"
        }
        self.assertTrue(
            acceptance(steps, 1800, graphical=True, exported=True)[
                "r10_gameplay_passed"
            ]
        )

    def test_malformed_phase_skill_is_missing_instead_of_raising(self):
        steps = self.steps()
        next(step for step in steps if step["id"] == "skill-22")["observations"][
            "skill"
        ] = "agilidad"
        result = acceptance(steps, 1800, graphical=True, exported=True)
        self.assertFalse(result["r10_gameplay_passed"])
        self.assertNotIn(22, result["skills"])
