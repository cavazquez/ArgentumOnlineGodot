"""El bloqueo transitorio se espera; los fallos persistentes y funcionales no se ocultan."""
import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import Mock, patch

import portable_temp as module


def locked(code):
    error = PermissionError(13, "synthetic owned-file lock")
    error.winerror = code
    return error


class PortableCleanupTests(unittest.TestCase):
    def test_created_runtime_is_removed_and_cleanup_is_recorded(self):
        with tempfile.TemporaryDirectory() as name:
            output = Path(name)
            with module.portable_runtime(output) as runtime:
                self.assertTrue(runtime.is_dir())
                (runtime / "fixture.txt").write_text("owned")
            self.assertFalse(runtime.exists())
            self.assertTrue(json.loads((output / "portable-cleanup.json").read_text())["passed"])

    def test_transient_windows_share_locks_retry_cleanup_only(self):
        for code in (32, 33):
            with self.subTest(code=code), tempfile.TemporaryDirectory() as name:
                temporary = SimpleNamespace(cleanup=Mock(side_effect=[locked(code), None]))
                with patch.object(module.time, "monotonic", side_effect=[0, 0.1, 0.2]), patch.object(module.time, "sleep") as sleep:
                    module.cleanup_owned(temporary, Path(name), platform_name="win32")
                self.assertEqual(temporary.cleanup.call_count, 2)
                sleep.assert_called_once_with(0.1)
                self.assertTrue(json.loads((Path(name) / "portable-cleanup.json").read_text())["passed"])

    def test_persistent_lock_has_a_deadline_and_remains_a_failure(self):
        with tempfile.TemporaryDirectory() as name:
            temporary = SimpleNamespace(cleanup=Mock(side_effect=locked(32)))
            with patch.object(module.time, "monotonic", side_effect=[0, 0, 1, 2]), patch.object(module.time, "sleep"), self.assertRaises(PermissionError):
                module.cleanup_owned(temporary, Path(name), platform_name="win32", timeout=2)
            self.assertEqual(temporary.cleanup.call_count, 3)
            proof = json.loads((Path(name) / "portable-cleanup.json").read_text())
            self.assertFalse(proof["passed"])
            self.assertEqual(proof["elapsed_seconds"], 2)

    def test_other_permission_errors_are_never_retried(self):
        with tempfile.TemporaryDirectory() as name:
            temporary = SimpleNamespace(cleanup=Mock(side_effect=locked(5)))
            with patch.object(module.time, "sleep") as sleep, self.assertRaises(PermissionError):
                module.cleanup_owned(temporary, Path(name), platform_name="win32")
            temporary.cleanup.assert_called_once()
            sleep.assert_not_called()

    def test_non_windows_permission_errors_are_never_retried(self):
        with tempfile.TemporaryDirectory() as name:
            temporary = SimpleNamespace(cleanup=Mock(side_effect=locked(32)))
            with patch.object(module.time, "sleep") as sleep, self.assertRaises(PermissionError):
                module.cleanup_owned(temporary, Path(name), platform_name="linux")
            temporary.cleanup.assert_called_once()
            sleep.assert_not_called()

    def test_functional_failure_propagates_after_owned_cleanup(self):
        with tempfile.TemporaryDirectory() as name:
            with self.assertRaisesRegex(RuntimeError, "functional failure"):
                with module.portable_runtime(Path(name)) as runtime:
                    raise RuntimeError("functional failure")
            self.assertFalse(runtime.exists())
