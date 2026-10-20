"""La campaña no puede aprobar si falta el escenario de estadísticas."""

import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).parents[1]))
from full_evidence import FULL_REQUIRED, acceptance
from r10_world import REQUIRED_SCENARIOS


class LifetimeStatsEvidenceTests(unittest.TestCase):
    def test_missing_or_failed_statistics_rejects_campaign(self):
        for include_failed in (False, True):
            steps = [
                {"id": key, "passed": True}
                for key in (REQUIRED_SCENARIOS | FULL_REQUIRED)
                - {"lifetime-statistics"}
            ]
            steps += [
                {"id": f"skill-{i}", "passed": True, "observations": {"skill": i}}
                for i in range(1, 23)
            ]
            if include_failed:
                steps.append({"id": "lifetime-statistics", "passed": False})
            result = acceptance(steps, 1800, graphical=True, exported=True)
            self.assertFalse(result["test_execution_passed"])
            self.assertIn("lifetime-statistics", result["full_missing"])
