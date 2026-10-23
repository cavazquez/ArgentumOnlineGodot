"""The campaign's acceptance shape must match integration-world's final gate."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from storage_protocol_world import EXTRA, REQUIRED_SCENARIOS, acceptance, fast_acceptance


class StorageProtocolEvidenceTests(unittest.TestCase):
    def test_complete_graphical_campaign_passes_the_runner_gate(self):
        steps = [{"id": case, "passed": True} for case in REQUIRED_SCENARIOS | EXTRA]
        result = acceptance(steps, 60, graphical=True)
        self.assertTrue(result["test_execution_passed"])
        self.assertFalse(result["missing"])

    def test_partial_campaign_cannot_pass(self):
        steps = [{"id": case, "passed": True} for case in REQUIRED_SCENARIOS]
        result = acceptance(steps, 60, graphical=True)
        self.assertFalse(result["test_execution_passed"])
        self.assertEqual(set(result["missing"]), EXTRA)

    def test_headless_run_is_not_graphical_acceptance(self):
        steps = [{"id": case, "passed": True} for case in REQUIRED_SCENARIOS | EXTRA]
        self.assertFalse(acceptance(steps, 60, graphical=False)["test_execution_passed"])

    def test_short_campaign_does_not_claim_full_r10(self):
        steps = [{"id": case, "passed": True} for case in EXTRA]
        result = fast_acceptance(steps, 60, graphical=True)
        self.assertTrue(result["test_execution_passed"])
        self.assertFalse(result["full_r10"])
        self.assertFalse(fast_acceptance(steps[:-1], 60, graphical=True)["test_execution_passed"])


if __name__ == "__main__":
    unittest.main()
