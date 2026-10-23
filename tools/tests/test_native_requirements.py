"""La copia RDB auxiliar no reemplaza ni invalida los requisitos de cada UI."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("native_smoke", Path(__file__).parents[1] / "smoke-portable.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
CHECKS = ("rendering", "audio", "input", "preferences")


def probe(index):
    return {"id": "platform-" + str(index), "passed": True,
            "observations": dict.fromkeys(CHECKS, True)}


class NativeRequirementsTests(unittest.TestCase):
    def test_both_clients_accredit_their_own_requirements(self):
        self.assertEqual(module.platform_requirements([probe(1), probe(2)]), dict.fromkeys(CHECKS, True))

    def test_successful_full_catalog_snapshot_is_an_independent_requirement(self):
        snapshot = {"id": "windows-live-snapshot", "passed": True,
                    "observations": {"passed": True, "keys": 427916, "latest_fork_usec": 4457}}
        self.assertTrue(all(module.platform_requirements([snapshot, probe(1), probe(2)]).values()))

    def test_auxiliary_probe_cannot_replace_a_missing_client(self):
        with self.assertRaises(ValueError):
            module.platform_requirements([probe(1), {"id": "windows-live-snapshot", "passed": True}])

    def test_duplicate_client_cannot_accredit_two_clients(self):
        with self.assertRaises(ValueError): module.platform_requirements([probe(1), probe(1)])

    def test_failed_client_is_rejected_even_if_observations_claim_success(self):
        failed = probe(2);failed["passed"] = False
        with self.assertRaises(ValueError): module.platform_requirements([probe(1), failed])

    def test_failed_auxiliary_probe_still_blocks_the_complete_acceptance(self):
        with self.assertRaises(ValueError):
            module.platform_requirements([probe(1), probe(2), {"id": "windows-live-snapshot", "passed": False}])

    def test_a_requirement_must_pass_on_both_clients(self):
        for check in CHECKS:
            with self.subTest(check=check):
                missing = probe(2);missing["observations"].pop(check)
                self.assertFalse(module.platform_requirements([probe(1), missing])[check])

    def test_missing_client_observations_cannot_pass(self):
        missing = probe(2);missing.pop("observations")
        self.assertFalse(any(module.platform_requirements([probe(1), missing]).values()))
