"""La compilación muestra su fuente real, incluso en un Snap sin Git."""

import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "build_info", Path(__file__).parents[1] / "write-build-info.py"
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class BuildInfoTests(unittest.TestCase):
    def test_checkout_wins_over_synthetic_merge_sha(self):
        with (
            patch.dict("os.environ", {"GITHUB_SHA": "b" * 40}),
            patch.object(
                module.subprocess, "check_output", return_value="a" * 40 + "\n"
            ),
        ):
            self.assertEqual({"commit": "a" * 40}, module.metadata(Path("/tmp")))

    def test_snap_provenance_without_git(self):
        with (
            tempfile.TemporaryDirectory() as work,
            patch.object(
                module.subprocess,
                "check_output",
                side_effect=subprocess.CalledProcessError(128, "git"),
            ),
        ):
            root = Path(work)
            (root / "snap").mkdir()
            (root / "snap/pyao-source.json").write_text(
                json.dumps({"commit": "c" * 40})
            )
            self.assertEqual({"commit": "c" * 40}, module.metadata(root))

    def test_unavailable_metadata_is_explicit_and_has_no_private_paths(self):
        with (
            tempfile.TemporaryDirectory() as work,
            patch.object(
                module.subprocess, "check_output", side_effect=FileNotFoundError
            ),
        ):
            self.assertEqual({"commit": "no disponible"}, module.metadata(Path(work)))
