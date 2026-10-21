"""La exportación sólo reintenta el diagnóstico conocido y exige un log final limpio."""

import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("portable_export", Path(__file__).parents[1] / "export-portable.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
KNOWN = "[ DONE ] savepack\n" + ("ERROR: The Image width specified (0 pixels) must be greater than 0 pixels.\nERROR: Invalid image: image is empty\n") * 3


class PortableExportTest(unittest.TestCase):
    def check_export(self, messages, expected_attempts, fail=False):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            script = output / "fake_engine.py"
            script.write_text("from pathlib import Path\np=Path(__file__).with_suffix('.count')\nn=int(p.read_text()) if p.exists() else 0\np.write_text(str(n+1))\nprint(" + repr(messages) + "[min(n," + str(len(messages) - 1) + ")])\n")
            command = [sys.executable, str(script)]
            if fail:
                with self.assertRaises(subprocess.CalledProcessError): module.run_export(command, output)
            else:
                module.run_export(command, output)
                self.assertNotIn("ERROR:", (output / "export.log").read_text())
            self.assertEqual(int(script.with_suffix(".count").read_text()), expected_attempts)

    def test_cold_cache_is_retried_once_then_requires_a_clean_log(self):
        self.check_export([KNOWN, "[ DONE ] savepack"], 2)

    def test_persistent_cold_cache_error_is_a_failure(self):
        self.check_export([KNOWN], 2, fail=True)

    def test_unexpected_resource_or_script_error_is_never_retried(self):
        for message in ("ERROR: Resource missing", "SCRIPT ERROR: Invalid script"):
            self.check_export([message], 1, fail=True)

    def candidate(self, output, target):
        output.mkdir()
        record = {"version": "1.0.0rc4", "commit": "verified-commit", "dirty": False, "platform": target, "files": {}}
        manifest = output / "candidate-manifest.json"
        manifest.write_text(json.dumps(record))
        proof = {"passed": True, "client_commit": record["commit"], "platform": target, "candidate_manifest_sha256": module.digest(manifest), "native_machine": "x86_64"}
        proof.update(dict.fromkeys(("rendering", "audio", "input", "login", "preferences", "outside_checkout"), True))
        evidence = output.parent / (target + "-proof.json")
        evidence.write_text(json.dumps(proof))
        return evidence

    def test_web_can_be_sealed_after_browser_checks_without_a_desktop_tray(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "web"
            evidence = self.candidate(output, "web")
            self.assertTrue(module.seal(output, evidence).is_file())

    def test_native_packages_require_desktop_acceptance(self):
        with tempfile.TemporaryDirectory() as temporary:
            for target in ("linux", "linux-arm64", "windows", "macos"):
                with self.subTest(platform=target):
                    output = Path(temporary) / target
                    evidence = self.candidate(output, target)
                    with self.assertRaisesRegex(ValueError, "desktop"):
                        module.seal(output, evidence)
