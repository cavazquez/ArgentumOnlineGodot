"""El plazo de una prueba lenta no cambia el protocolo ni oculta otros timeouts."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "r10_deadline_subject", Path(__file__).parents[1] / "r10_world.py"
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class RunningProcess:
    def poll(self):
        return None


class CommandDeadlineTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        (self.root / "control-1").mkdir()
        for name in ("server.log", "godot-1.log", "godot-2.log"):
            (self.root / name).write_text("")
        self.world = module.R10World(
            None, self.root, self.root, ["one", "two"],
            [RunningProcess(), RunningProcess()], RunningProcess(),
        )
        self.world.deadline = 600
        self.elapsed = 0

    def advance(self, _seconds):
        self.elapsed += 1
        if self.elapsed == 45:
            (self.root / "control-1/0001.response.json").write_text(
                json.dumps({"ok": True, "view": {"probe_complete": True}})
            )

    def test_explicit_budget_accepts_a_valid_slow_probe_without_changing_payload(self):
        with patch.object(module.time, "monotonic", side_effect=lambda: self.elapsed), \
             patch.object(module.time, "sleep", side_effect=self.advance):
            view = self.world.command(1, "platform_probe", response_timeout=90)
        self.assertTrue(view["probe_complete"])
        request = json.loads((self.root / "control-1/0001.request.json").read_text())
        self.assertEqual({"op": "platform_probe"}, request)
        self.assertEqual(45, self.elapsed)
        self.assertFalse((self.root / "r10-command-timeout-1.json").exists())

    def test_default_deadline_still_rejects_slow_commands_and_redacts_arguments(self):
        secret = "synthetic-secret-not-for-diagnostics"
        with patch.object(module.time, "monotonic", side_effect=lambda: self.elapsed), \
             patch.object(module.time, "sleep", side_effect=self.advance):
            with self.assertRaisesRegex(TimeoutError, "Godot 1, chat"):
                self.world.command(1, "chat", text="/CONTRASEÑA " + secret)
        diagnostic = (self.root / "r10-command-timeout-1.json").read_text()
        self.assertNotIn(secret, diagnostic)
        self.assertNotIn("CONTRASEÑA", diagnostic)
        record = json.loads(diagnostic)
        self.assertEqual(40, record["response_timeout_seconds"])
        self.assertEqual(40, record["elapsed_seconds"])
        self.assertEqual("chat", record["operation"])
        self.assertFalse(record["response_received"])


if __name__ == "__main__":
    unittest.main()
