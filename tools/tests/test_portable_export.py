"""La exportación sólo reintenta el diagnóstico conocido y exige un log final limpio."""

import importlib.util
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
