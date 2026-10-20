"""La fixture WSL guarda AOF en Linux y sólo borra el directorio que creó."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("integration_world", Path(__file__).parents[1] / "integration-world.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class NativeRedisStorageTests(unittest.TestCase):
    def fixture(self, root):
        with patch.object(module, "port", return_value=12345):
            return module.NativeRedis(Path("unused-runtime"), root)

    def test_wsl_uses_linux_storage_and_removes_only_its_own_directory(self):
        with tempfile.TemporaryDirectory() as name:
            fixture = self.fixture(Path(name))
            owned = "/tmp/pyao-redis-fixture-aB01234567"
            with patch.object(module.subprocess, "check_output", return_value=owned + "\n") as create:
                self.assertEqual(fixture.data_directory(True), owned)
            create.assert_called_once_with(
                ["wsl", "--exec", "mktemp", "-d", "/tmp/pyao-redis-fixture-XXXXXXXXXX"],
                text=True, timeout=15,
            )
            self.assertEqual(fixture.storage_kind, "wsl-linux")
            with patch.object(module.subprocess, "run") as cleanup:
                fixture.__exit__()
                fixture.__exit__()
            cleanup.assert_called_once_with(
                ["wsl", "--exec", "rm", "-rf", "--", owned], check=True, timeout=15,
            )

    def test_invalid_wsl_response_never_becomes_a_cleanup_target(self):
        for invalid in ("/tmp", "/", "/mnt/c/other", "/tmp/pyao-redis-fixture-abcdefghij/../other"):
            with self.subTest(path=invalid), tempfile.TemporaryDirectory() as name:
                fixture = self.fixture(Path(name))
                with patch.object(module.subprocess, "check_output", return_value=invalid):
                    with self.assertRaises(RuntimeError):
                        fixture.data_directory(True)
                with patch.object(module.subprocess, "run") as cleanup:
                    fixture.__exit__()
                cleanup.assert_not_called()

    def test_native_runtime_keeps_the_owned_local_directory(self):
        with tempfile.TemporaryDirectory() as name:
            fixture = self.fixture(Path(name))
            with patch.object(module.subprocess, "check_output") as wsl:
                self.assertEqual(fixture.data_directory(False), str(fixture.root))
            wsl.assert_not_called()
            self.assertEqual(fixture.storage_kind, "native")
