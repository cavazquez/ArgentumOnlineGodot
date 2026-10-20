"""Ejecuta el lanzador real para comprobar su entorno en las dos arquitecturas."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


LAUNCHER = Path(__file__).parents[2] / "snap/local/pyao-client-launch"


class SnapLauncherTests(unittest.TestCase):
    def launch(self, arch, inherited_library=None):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            snap = root / "snap"
            executable = snap / "bin/pyao-client"
            executable.parent.mkdir(parents=True)
            executable.write_text(
                "#!/usr/bin/env python3\n"
                "import json, os, sys\n"
                "print(json.dumps({'libraries': os.environ['LD_LIBRARY_PATH'], "
                "'args': sys.argv[1:], 'cwd': os.getcwd()}))\n"
            )
            executable.chmod(0o755)
            environment = dict(os.environ, SNAP=str(snap), SNAP_USER_COMMON=str(root / "common"))
            for key in ("SNAP_ARCH", "LD_LIBRARY_PATH"):
                environment.pop(key, None)
            if arch is not None:
                environment["SNAP_ARCH"] = arch
            if inherited_library is not None:
                environment["LD_LIBRARY_PATH"] = inherited_library
            result = subprocess.run(
                ["sh", str(LAUNCHER), "--audio-driver", "PulseAudio", "argument with spaces"],
                env=environment, capture_output=True, text=True, check=False,
            )
            return result, str(snap)

    def test_both_architectures_find_their_pulse_libraries_and_preserve_arguments(self):
        for arch, triplet in (("amd64", "x86_64-linux-gnu"), ("arm64", "aarch64-linux-gnu")):
            with self.subTest(arch=arch):
                result, snap = self.launch(arch, "/existing/gpu-libraries")
                self.assertEqual(result.returncode, 0, result.stderr)
                value = json.loads(result.stdout)
                self.assertEqual(value["libraries"], f"{snap}/usr/lib/{triplet}/pulseaudio:/existing/gpu-libraries")
                self.assertEqual(value["args"], ["--rendering-method", "gl_compatibility", "--display-driver", "x11", "--audio-driver", "PulseAudio", "argument with spaces"])
                self.assertEqual(value["cwd"], snap)

    def test_empty_library_path_has_no_empty_search_entry(self):
        result, snap = self.launch("arm64")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["libraries"], f"{snap}/usr/lib/aarch64-linux-gnu/pulseaudio")

    def test_unsupported_architecture_fails_before_starting_game(self):
        result, _ = self.launch("riscv64")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no soportada", result.stderr)
        self.assertEqual(result.stdout, "")

    def test_missing_architecture_fails_before_starting_game(self):
        result, _ = self.launch(None)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Falta la arquitectura", result.stderr)
        self.assertEqual(result.stdout, "")
