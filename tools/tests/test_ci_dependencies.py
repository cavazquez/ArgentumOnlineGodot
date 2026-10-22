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
        self.write("dpkg-query", f"#!{sys.executable}\n" + '''
import json, os, sys
status = json.loads(os.environ["PYAO_TEST_INSTALLED"]).get(sys.argv[-1])
if status is None: sys.exit(1)
print(status, end="")
''')
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

    def run_helper(self, mode, *, actions="true", installed=None, build=False):
        environment = dict(os.environ, GITHUB_ACTIONS=actions,
                           PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                           PYAO_TEST_CALLS=str(self.calls), PYAO_TEST_BOUNDS=str(self.bounds),
                           PYAO_TEST_APT_MODE=mode,
                           PYAO_TEST_INSTALLED=json.dumps(installed or {}))
        arguments = ["sh", str(SCRIPT)] + (["--build"] if build else [])
        return subprocess.run([*arguments, "xvfb", "pulseaudio"],
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
        self.assertIn("600s", bounds[-1])

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

    def test_satisfied_runtime_dependencies_do_not_run_apt_or_touch_its_indexes(self):
        result = self.run_helper("ok", installed={
            "xvfb": "installed 2:21.1.12-1", "pulseaudio": "installed 1:16.1",
        })
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertFalse(self.calls.exists())
        self.assertFalse(self.bounds.exists())
        self.assertIn("xvfb", result.stdout)
        self.assertIn("2:21.1.12-1", result.stdout)

    def test_only_missing_packages_are_passed_to_the_signed_installer(self):
        result = self.run_helper("ok", installed={"xvfb": "installed 2:21.1.12-1"})
        self.assertEqual(0, result.returncode, result.stderr)
        calls = json.loads(self.calls.read_text())
        self.assertEqual(["update", "install"], [call["kind"] for call in calls])
        installation = calls[-1]["args"]
        self.assertNotIn("xvfb", installation)
        self.assertEqual("pulseaudio", installation[-1])
        self.assertIn("Dir::Etc::sourceparts=-", installation)

    def test_unconfigured_or_removed_packages_are_not_mistaken_for_installed(self):
        result = self.run_helper("ok", installed={
            "xvfb": "config-files 2:21.1.12-1", "pulseaudio": "half-configured 1:16.1",
        })
        self.assertEqual(0, result.returncode, result.stderr)
        installation = json.loads(self.calls.read_text())[-1]["args"]
        self.assertEqual(["xvfb", "pulseaudio"], installation[-2:])

    def test_builds_keep_complete_dependency_resolution_for_headers_and_graphics(self):
        result = self.run_helper("ok", build=True, installed={
            "xvfb": "installed 2:21.1.12-1", "pulseaudio": "installed 1:16.1",
        })
        self.assertEqual(0, result.returncode, result.stderr)
        calls = json.loads(self.calls.read_text())
        self.assertEqual(["update", "install"], [call["kind"] for call in calls])
        self.assertEqual(["xvfb", "pulseaudio"], calls[-1]["args"][-2:])
        self.assertNotIn("--build", calls[-1]["args"])


if __name__ == "__main__":
    unittest.main()
