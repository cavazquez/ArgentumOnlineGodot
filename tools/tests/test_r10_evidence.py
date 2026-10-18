"""Regresión del falso positivo: 30 minutos de smoke no aprueban la R10."""

import importlib.util
import hashlib
import json
from pathlib import Path
import unittest
import tempfile
import zipfile
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "r10_world", Path(__file__).parents[1] / "r10_world.py"
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class AcceptanceTests(unittest.TestCase):
    def test_duration_does_not_cover_missing_gameplay(self):
        value = module.acceptance([], 2000, graphical=True)
        self.assertFalse(value["r10_gameplay_passed"])
        self.assertIn("combat", value["missing"])

    def test_failed_scenario_is_not_accepted(self):
        steps = [
            {"id": key, "passed": key != "trade_complete"}
            for key in module.REQUIRED_SCENARIOS
        ]
        self.assertFalse(
            module.acceptance(steps, 1800, graphical=True, exported=True)[
                "r10_gameplay_passed"
            ]
        )

    def test_short_or_headless_is_development_only(self):
        steps = [{"id": key, "passed": True} for key in module.REQUIRED_SCENARIOS]
        self.assertFalse(
            module.acceptance(steps, 120, graphical=True)["r10_gameplay_passed"]
        )
        self.assertFalse(
            module.acceptance(steps, 1800, graphical=False)["r10_gameplay_passed"]
        )
        self.assertTrue(
            module.acceptance(steps, 1800, graphical=True, exported=True)[
                "r10_gameplay_passed"
            ]
        )

    def test_editor_is_not_a_native_export(self):
        steps = [{"id": key, "passed": True} for key in module.REQUIRED_SCENARIOS]
        self.assertFalse(
            module.acceptance(steps, 1800, graphical=True)["r10_gameplay_passed"]
        )


class SourceProofTests(unittest.TestCase):
    def test_native_export_must_match_commit_bytes_and_clean_source(self):
        path = Path(__file__).parents[1] / "integration-world.py"
        spec = importlib.util.spec_from_file_location("native_runner", path)
        runner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(runner)
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            binary = root / "pyao-client-r10.x86_64"
            binary.write_bytes(b"candidate executable")
            (root / "override.cfg").write_bytes(b"candidate entrypoint")
            provenance = {
                "commit": "candidate",
                "clean_before_export": True,
                "files": {
                    p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                    for p in [binary, root / "override.cfg"]
                },
            }
            manifest = root / "provenance.json"
            manifest.write_text(json.dumps(provenance))
            self.assertEqual(
                runner.verify_native_export(binary, "candidate", long_run=True),
                provenance,
            )
            with self.assertRaises(RuntimeError):
                runner.verify_native_export(binary, "other", long_run=True)
            provenance["clean_before_export"] = False
            manifest.write_text(json.dumps(provenance))
            with self.assertRaises(RuntimeError):
                runner.verify_native_export(binary, "candidate", long_run=True)
            provenance["clean_before_export"] = True
            manifest.write_text(json.dumps(provenance))
            binary.write_bytes(b"changed executable")
            with self.assertRaises(RuntimeError):
                runner.verify_native_export(binary, "candidate", long_run=True)

    def test_wrong_or_incomplete_wheel_cannot_claim_the_source_commit(self):
        path = Path(__file__).parents[1] / "integration-world.py"
        spec = importlib.util.spec_from_file_location("integration_world", path)
        runner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(runner)
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            (root / "src").mkdir()
            (root / "src/game.py").write_text("candidate")
            for missing in [True, False]:
                wheel = root / ("missing.whl" if missing else "wrong.whl")
                with zipfile.ZipFile(wheel, "w") as archive:
                    if not missing:
                        archive.writestr("src/game.py", "older source")
                with patch.object(
                    runner.subprocess, "check_output", return_value="src/game.py\n"
                ):
                    with self.assertRaises(RuntimeError):
                        runner.verify_wheel_source(root, wheel)


if __name__ == "__main__":
    unittest.main()
