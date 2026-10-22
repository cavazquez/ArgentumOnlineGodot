"""Los fallos de APT se recuperan o terminan acotados, sin tocar paquetes del host."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).parents[1] / "install-ci-deps.sh"
SOURCES = Path("/etc/apt/sources.list.d/ubuntu.sources")


@unittest.skipUnless(os.name == "posix" and SOURCES.is_file(), "Helper exclusivo de runners Ubuntu")
class CIDependenciesTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.calls = self.root / "calls.json"
        self.bounds = self.root / "bounds.log"
        self.write("sudo", '#!/bin/sh\nexec "$@"\n')
        self.write("sleep", "#!/bin/sh\nexit 0\n")
        self.write("timeout", '#!/bin/sh\nprintf \'%s\\n\' "$*" >> "$PYAO_TEST_BOUNDS"\nshift 3\nexec "$@"\n')
        self.write("apt-get", f"#!{sys.executable}\n" + '''
import json, os, sys
from pathlib import Path
path = Path(os.environ["PYAO_TEST_CALLS"])
calls = json.loads(path.read_text()) if path.exists() else []
args = sys.argv[1:]
kind = "install" if "install" in args else "update"
calls.append({"kind": kind, "args": args})
path.write_text(json.dumps(calls))
count = sum(call["kind"] == kind for call in calls)
mode = os.environ["PYAO_TEST_APT_MODE"]
if mode == "transient-update" and kind == "update" and count == 1: sys.exit(42)
if mode == "timeout-update" and kind == "update": sys.exit(124)
if mode == "failed-install" and kind == "install": sys.exit(100)
''')

    def write(self, name, source):
        path = self.bin / name
        path.write_text(source)
        path.chmod(0o755)

    def run_helper(self, mode, *, actions="true"):
        environment = dict(os.environ, GITHUB_ACTIONS=actions,
                           PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                           PYAO_TEST_CALLS=str(self.calls), PYAO_TEST_BOUNDS=str(self.bounds),
                           PYAO_TEST_APT_MODE=mode)
        return subprocess.run(["sh", str(SCRIPT), "xvfb", "pulseaudio"],
                              env=environment, capture_output=True, text=True, timeout=5)

    def test_recovers_transient_update_and_keeps_signed_sources_and_explicit_packages(self):
        result = self.run_helper("transient-update")
        self.assertEqual(0, result.returncode, result.stderr)
        calls = json.loads(self.calls.read_text())
        self.assertEqual(["update", "update", "install"], [call["kind"] for call in calls])
        installation = calls[-1]["args"]
        self.assertIn("--no-install-recommends", installation)
        self.assertEqual(["xvfb", "pulseaudio"], installation[-2:])
        for call in calls:
            self.assertIn("Dir::Etc::sourcelist=" + str(SOURCES), call["args"])
            self.assertIn("Dir::Etc::sourceparts=-", call["args"])
            self.assertNotIn("--allow-unauthenticated", call["args"])
        bounds = self.bounds.read_text().splitlines()
        self.assertEqual(3, len(bounds))
        self.assertIn("120s", bounds[0])
        self.assertIn("300s", bounds[-1])

    def test_repeated_timeout_stops_before_installing_and_preserves_exit_status(self):
        result = self.run_helper("timeout-update")
        self.assertEqual(124, result.returncode)
        calls = json.loads(self.calls.read_text())
        self.assertEqual(["update", "update"], [call["kind"] for call in calls])
        self.assertIn("APT update attempt=2 failed status=124", result.stderr)

    def test_install_failure_is_retried_twice_and_is_never_reported_as_success(self):
        result = self.run_helper("failed-install")
        self.assertEqual(100, result.returncode)
        calls = json.loads(self.calls.read_text())
        self.assertEqual(["update", "install", "install"], [call["kind"] for call in calls])
        self.assertNotIn("APT install complete", result.stdout)

    def test_refuses_to_install_outside_github_actions(self):
        result = self.run_helper("ok", actions="false")
        self.assertNotEqual(0, result.returncode)
        self.assertFalse(self.calls.exists())


if __name__ == "__main__":
    unittest.main()
