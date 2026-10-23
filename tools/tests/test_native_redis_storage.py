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

    def test_wsl2_config_preserves_all_persistence_settings(self):
        template = 'dir /data\nappendonly yes\nappendfsync always\nstop-writes-on-bgsave-error yes\nrdb-save-incremental-fsync yes\naof-rewrite-incremental-fsync yes\n'
        configured = module.redis_fixture_configuration(template, "/tmp/owned", wsl_runtime=True)
        self.assertEqual(configured, template.replace('dir /data', 'dir "/tmp/owned"'))
        self.assertEqual(configured, module.redis_fixture_configuration(template, "/tmp/owned", wsl_runtime=False))
        with self.assertRaises(ValueError): module.redis_fixture_configuration("dir /other", "/tmp/owned", wsl_runtime=True)

    def test_wsl2_requires_a_real_kernel_and_rejects_wsl1(self):
        with patch.object(module.subprocess, "check_output", return_value="6.6.87.2-microsoft-standard-WSL2\n") as call:
            self.assertEqual(module.require_wsl2(), "6.6.87.2-microsoft-standard-WSL2")
        call.assert_called_once_with(["wsl", "--exec", "uname", "-r"], text=True, timeout=15)
        for kernel in ("4.4.0-26100-Microsoft", "6.8.0-generic", ""):
            with self.subTest(kernel=kernel), patch.object(module.subprocess, "check_output", return_value=kernel):
                with self.assertRaisesRegex(RuntimeError, "WSL2"):
                    module.require_wsl2()

    def live_probe(self, root, *, keys=427933, fork=2000, status="ok", fsync="always"):
        fixture = self.fixture(root)
        fixture.evidence = root
        fixture.kernel = "6.6.87.2-microsoft-standard-WSL2"
        state = {"rdb_bgsave_in_progress": 0, "rdb_last_bgsave_status": status}
        client = SimpleNamespace(dbsize=Mock(return_value=keys), bgsave=Mock(), ping=Mock(),
            info=Mock(side_effect=lambda section: state if section == "persistence" else {"latest_fork_usec": fork}),
            config_get=Mock(return_value={"appendonly": "yes", "appendfsync": fsync, "stop-writes-on-bgsave-error": "yes"}))
        fixture.client = Mock(side_effect=lambda **kwargs: nullcontext(client))
        return fixture, client

    def test_live_snapshot_checks_full_catalog_and_fork_latency(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name);fixture, client = self.live_probe(root)
            proof = fixture.verify_live_snapshot()
            self.assertTrue(proof["passed"])
            self.assertEqual(proof["keys"], 427933)
            self.assertEqual(proof["latest_fork_usec"], 2000)
            self.assertLess(proof["maximum_roundtrip_seconds"], 5)
            client.bgsave.assert_called_once_with()
            client.ping.assert_called_once_with()
            self.assertEqual(json.loads((root / "native-redis-live-snapshot.json").read_text()), proof)

    def test_live_snapshot_rejects_stall_loss_of_durability_and_small_fixture(self):
        for options in ({"keys": 1}, {"fork": 5000000}, {"status": "err"}, {"fsync": "no"}):
            with self.subTest(options=options), tempfile.TemporaryDirectory() as name:
                root = Path(name);fixture, _ = self.live_probe(root, **options)
                with self.assertRaises(RuntimeError): fixture.verify_live_snapshot()
                self.assertFalse(json.loads((root / "native-redis-live-snapshot.json").read_text())["passed"])

    def test_live_snapshot_never_retries_failed_bgsave(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name);fixture, client = self.live_probe(root)
            client.bgsave.side_effect = TimeoutError("synthetic stall")
            with self.assertRaises(TimeoutError): fixture.verify_live_snapshot()
            client.bgsave.assert_called_once_with()
            self.assertFalse(json.loads((root / "native-redis-live-snapshot.json").read_text())["passed"])

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
    def test_all_portables_have_the_same_cold_bootstrap_and_other_budgets_do_not_change(self):
        for system, machine in (
            ("darwin", "x86_64"), ("darwin", "arm64"), ("win32", "AMD64"),
            ("linux", "x86_64"), ("linux", "aarch64"),
        ):
            with self.subTest(system=system, machine=machine), patch.object(module.sys, "platform", system), patch.object(module.platform, "machine", return_value=machine):
                self.assertEqual(module.server_startup_budget("platform"), 360)
                for scenario in ("r10", "full", "npcs", "skills", "spells"):
                    self.assertEqual(module.server_startup_budget(scenario), 240)
