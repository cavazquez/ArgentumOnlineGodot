"""A reviewed engine diagnostic must not turn into a generic error allowlist."""

import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from runtime_log import classify_runtime_log


ENGINE = "Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org\n"


def pair(window="42"):
    return "\n".join(
        f"ERROR: Attempt to disconnect a nonexistent connection from 'root:<Window#{window}>'. "
        f"Signal: '{signal}', callable: ''."
        for signal in ("focus_entered", "tree_exited")
    ) + "\n"


class RuntimeLogTest(unittest.TestCase):
    def test_clean(self):
        self.assertTrue(classify_runtime_log(ENGINE)["passed"])

    def test_known_pair_is_preserved(self):
        result = classify_runtime_log(ENGINE + pair() + pair("73"))
        self.assertTrue(result["passed"])
        self.assertEqual(len(result["known_engine_diagnostics"]), 4)
        self.assertIn("focus_entered", result["known_engine_diagnostics"][0]["message"])

    def test_wrong_engine_is_rejected(self):
        self.assertFalse(classify_runtime_log(pair())["passed"])
        self.assertFalse(classify_runtime_log(ENGINE.replace("4.7.2", "4.7.3") + pair())["passed"])

    def test_incomplete_or_mismatched_pair_is_rejected(self):
        self.assertFalse(classify_runtime_log(ENGINE + pair().splitlines()[0])["passed"])
        self.assertFalse(classify_runtime_log(ENGINE + pair().replace("tree_exited", "focus_entered"))["passed"])
        self.assertFalse(classify_runtime_log(ENGINE + pair().replace("Window#42>'. Signal: 'tree", "Window#43>'. Signal: 'tree"))["passed"])

    def test_other_callbacks_and_errors_are_rejected(self):
        for changed in (pair().replace("callable: ''", "callable: 'Game::handler'"),
                        pair().replace("root:<Window", "Dialog:<Window"),
                        pair() + "ERROR: Parameter t->get_data() is null.\n",
                        pair() + "SCRIPT ERROR: Invalid call.\n"):
            with self.subTest(log=changed):
                self.assertFalse(classify_runtime_log(ENGINE + changed)["passed"])
