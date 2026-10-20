"""La evidencia identifica el binario ejecutado aunque se reemplace el original."""

from contextlib import redirect_stdout
import hashlib
import importlib.util
from io import StringIO
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "map_stress", Path(__file__).parents[1] / "smoke-map-cache.py"
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class MapStressEvidenceTests(unittest.TestCase):
    def test_rebuilding_source_during_run_does_not_change_executed_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "client.x86_64"
            source.write_bytes(b"native snapshot before rebuild")
            expected = hashlib.sha256(source.read_bytes()).hexdigest()
            output = root / "evidence"

            def launch(*_, **kwargs):
                source.write_bytes(b"new build while old snapshot runs")
                kwargs["stdout"].write("MAP_CACHE_STRESS: PASS cycles=10 switches=70\n")
                return SimpleNamespace(returncode=0, wait=lambda **_: 0)

            arguments = [
                "smoke-map-cache",
                "--client-executable",
                str(source),
                "--output",
                str(output),
                "--cycles",
                "10",
            ]
            with (
                patch("sys.argv", arguments),
                patch.object(module.subprocess, "Popen", side_effect=launch),
                redirect_stdout(StringIO()),
            ):
                self.assertEqual(0, module.main())
            result = json.loads((output / "result.json").read_text())
            self.assertTrue(result["passed"])
            self.assertEqual(70, result["map_switches"])
            self.assertEqual(expected, result["export_sha256"])
            self.assertNotEqual(
                hashlib.sha256(source.read_bytes()).hexdigest(), result["export_sha256"]
            )
