"""El arranque frío del renderer software tiene un plazo propio y deja evidencia."""

import importlib.util
import json
from pathlib import Path
import platform
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, patch

TOOLS = Path(__file__).parents[1]
spec = importlib.util.spec_from_file_location("platform_readiness_subject", TOOLS / "platform_world.py")
module = importlib.util.module_from_spec(spec)
with patch.object(sys, "path", [str(TOOLS), *sys.path]):
    spec.loader.exec_module(module)


class RunningProcess:
    def poll(self):
        return None


class PlatformReadinessTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        for name in ("server.log", "godot-1.log", "godot-2.log"):
            (self.root / name).write_text("")
        self.world = module.PlatformWorld(
            None, self.root, self.root, ["one", "two"],
            [RunningProcess(), RunningProcess()], RunningProcess(),
        )
        self.world.deadline = 600
        self.world.command = Mock(return_value={"platform_probe": {
            "rendering": True, "audio": True, "input": True, "preferences": True,
        }})
        self.world.passed = Mock()
        self.elapsed = 0

    def advance(self, _seconds):
        self.elapsed += 1
        for index, ready_at in ((1, 95), (2, 110)):
            if self.elapsed == ready_at:
                (self.root / f"godot-{index}.log").write_text("INTEGRATION_WORLD: READY\n")

    def exercise(self, system, machine):
        with patch.object(module.sys, "platform", system), \
             patch.object(platform, "machine", return_value=machine), \
             patch.object(time, "monotonic", side_effect=lambda: self.elapsed), \
             patch.object(time, "sleep", side_effect=self.advance):
            self.world.run({})

    def test_intel_macos_accepts_cold_clients_without_changing_the_command_budget(self):
        self.exercise("darwin", "x86_64")
        proof = json.loads((self.root / "platform-readiness.json").read_text())
        self.assertTrue(proof["passed"])
        self.assertEqual({"1": 95, "2": 110}, proof["ready_seconds"])
        self.assertEqual(110, proof["elapsed_seconds"])
        self.assertFalse(proof["login_budget_changed"])
        self.world.command.assert_any_call(1, "platform_probe", response_timeout=90)

    def test_other_native_targets_still_reject_the_same_slow_start_and_record_the_failure(self):
        for system, machine in (("linux", "x86_64"), ("win32", "AMD64"), ("darwin", "arm64")):
            with self.subTest(system=system, machine=machine):
                self.elapsed = 0
                for index in (1, 2):
                    (self.root / f"godot-{index}.log").write_text("")
                with self.assertRaisesRegex(TimeoutError, "dos clientes nativos"):
                    self.exercise(system, machine)
                proof = json.loads((self.root / "platform-readiness.json").read_text())
                self.assertFalse(proof["passed"])
                self.assertEqual(90, proof["elapsed_seconds"])
                self.assertEqual({}, proof["ready_seconds"])

    def test_process_failure_is_immediate_and_its_arguments_are_not_copied_to_the_receipt(self):
        secret = "synthetic-secret-never-in-receipt"
        self.world.check_processes = Mock(side_effect=RuntimeError(secret))
        with self.assertRaisesRegex(RuntimeError, secret):
            self.exercise("darwin", "x86_64")
        receipt = (self.root / "platform-readiness.json").read_text()
        self.assertNotIn(secret, receipt)
        self.assertFalse(json.loads(receipt)["passed"])
        self.assertEqual(0, self.elapsed)


if __name__ == "__main__":
    unittest.main()
