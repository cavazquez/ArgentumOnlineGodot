"""La fixture WSL guarda AOF en Linux y sólo borra el directorio que creó."""
import importlib.util
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch
from contextlib import nullcontext

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

    def test_wsl_config_keeps_aof_fsync_and_stops_only_incremental_sync(self):
        template = 'dir /data\nappendonly yes\nappendfsync always\nstop-writes-on-bgsave-error yes\n'
        configured = module.redis_fixture_configuration(template, "/tmp/owned", wsl_runtime=True)
        for rule in ('dir "/tmp/owned"', "appendonly yes", "appendfsync always", "stop-writes-on-bgsave-error yes", "rdb-save-incremental-fsync no", "aof-rewrite-incremental-fsync no"):
            self.assertIn(rule + "\n", configured)
        self.assertNotIn("incremental-fsync", module.redis_fixture_configuration(template, "/tmp/owned", wsl_runtime=False))
        with self.assertRaises(ValueError): module.redis_fixture_configuration("dir /other", "/tmp/owned", wsl_runtime=True)

    def persistence_probe(self, root, *, restored="synthetic-payload", fsync="always"):
        fixture = self.fixture(root)
        fixture.evidence = root
        fixture.wsl_data_dir = "/tmp/pyao-redis-fixture-abcdefghij"
        fixture.log = object()
        fixture.process = object()
        fixture.stop_for_restart = Mock()
        client = SimpleNamespace(dbsize=Mock(return_value=0), config_get=Mock(return_value={"appendonly": "yes", "appendfsync": fsync, "stop-writes-on-bgsave-error": "yes"}), set=Mock(), save=Mock(), shutdown=Mock(), get=Mock(return_value=restored), info=Mock(return_value={"aof_enabled": 1}), delete=Mock())
        fixture.client = Mock(side_effect=lambda **kwargs: nullcontext(client))
        return fixture, client

    def test_large_snapshot_is_checked_and_payload_survives_aof_restart(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name);fixture, client = self.persistence_probe(root)
            with patch.object(module.secrets, "token_urlsafe", return_value="synthetic-payload") as payload, patch.object(module.subprocess, "run", return_value=SimpleNamespace(stdout="Checksum OK\nRDB looks OK!")) as checker, patch.object(module.subprocess, "Popen") as start:
                fixture.verify_wsl_persistence(["owned-launcher"], "/owned/redis-check-rdb")
            payload.assert_called_once_with(32 * 1024 * 1024)
            fixture.stop_for_restart.assert_called_once_with()
            self.assertEqual(start.call_args.args[0], ["owned-launcher"])
            self.assertEqual(checker.call_args.args[0], ["wsl", "--exec", "/owned/redis-check-rdb", fixture.wsl_data_dir + "/dump.rdb"])
            proof = json.loads((root / "native-redis-persistence.json").read_text())
            self.assertTrue(proof["passed"] and proof["rdb_checksum_verified"] and proof["payload_preserved"])
            client.delete.assert_called_once_with("__pyao_private_persistence_probe__")

    def test_lost_payload_or_weakened_fsync_cannot_pass(self):
        for options in ({"restored": "changed"}, {"fsync": "no"}):
            with self.subTest(options=options), tempfile.TemporaryDirectory() as name:
                root = Path(name);fixture, client = self.persistence_probe(root, **options)
                with patch.object(module.secrets, "token_urlsafe", return_value="synthetic-payload"), patch.object(module.subprocess, "run", return_value=SimpleNamespace(stdout="Checksum OK\nRDB looks OK!")), patch.object(module.subprocess, "Popen"), patch.object(module, "stop"), self.assertRaises(RuntimeError):
                    fixture.verify_wsl_persistence(["owned-launcher"], "/owned/checker")
                self.assertFalse((root / "native-redis-persistence.json").exists())


class ServerStartupBudgetTests(unittest.TestCase):
    def test_only_intel_macos_portable_gets_a_longer_cold_bootstrap(self):
        self.assertEqual(module.server_startup_budget("platform", system="darwin", machine="x86_64"), 360)
        for scenario, system, machine in (
            ("r10", "darwin", "x86_64"), ("npcs", "darwin", "x86_64"),
            ("platform", "darwin", "arm64"), ("platform", "win32", "AMD64"),
            ("platform", "linux", "x86_64"), ("platform", "linux", "aarch64"),
        ):
            with self.subTest(scenario=scenario, system=system, machine=machine):
                self.assertEqual(module.server_startup_budget(scenario, system=system, machine=machine), 240)
