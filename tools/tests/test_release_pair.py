"""No se promueve un Snap huérfano; un fallo incierto recupera todo el par."""

import copy
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1]))
spec = importlib.util.spec_from_file_location(
    "release_pair", Path(__file__).parents[1] / "release-pair.py"
)
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class StoreModel:
    """Modelo con revisiones independientes; puede fallar después de cambiar canal."""

    def __init__(self):
        self.current = {
            key: {
                "name": key.split("/")[0],
                "revision": i,
                "version": "1.0.0rc1",
                "sha3_384": str(i),
            }
            for i, key in enumerate(sorted(release.PACKAGES), 1)
        }
        self.versions = {
            (p["name"], p["revision"]): (key, p) for key, p in self.current.items()
        }
        self.events = []
        self.upload_failure = None
        self.release_failure = None
        self.moved_main = False

    def main(self, repository):
        return (
            "c" * 40
            if self.moved_main
            else ("a" if repository.endswith("pyao-server") else "b") * 40
        )

    def ci(self, repository, run):
        return {
            "headSha": self.main(repository),
            "status": "completed",
            "conclusion": "success",
            "workflowName": {1: "CI", 2: "Server Snap", 3: "Cliente Linux"}[run],
        }

    def inspect(self, path, _name):
        value = release.read(path)
        return value["metadata"], value["provenance"]

    def channels(self, _channel):
        return {key: copy.deepcopy(self.current.get(key)) for key in release.PACKAGES}

    def close(self, name, _channel):
        self.events.append("close")
        self.current = {key: value for key, value in self.current.items() if value["name"] != name}

    def upload(self, path, name, _log):
        self.events.append("upload")
        if self.events.count("upload") == self.upload_failure:
            raise RuntimeError("La revisión fue rechazada")
        revision = 100 + self.events.count("upload")
        metadata, _ = self.inspect(path, name)
        key = f"{name}/{metadata['architectures'][0]}"
        value = {
            "name": name,
            "revision": revision,
            "version": metadata["version"],
            "sha3_384": release.digest(path, "sha3_384"),
        }
        self.versions[name, revision] = key, value
        return revision

    def release(self, name, revision, _channel):
        self.events.append("release")
        key, value = self.versions[name, revision]
        self.current[key] = copy.deepcopy(value)
        if self.events.count("release") == self.release_failure:
            raise TimeoutError("Se perdió la respuesta después de cambiar el canal")

    def wait(self, expected, _channel):
        if self.channels(_channel) != expected:
            raise TimeoutError("El par no coincide")
        return self.channels(_channel)


class PairReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.store = StoreModel()
        self.manifest = {
            "version": "1.0.0rc1",
            "channel": "latest/edge",
            "sources": {
                name: {
                    "repository": repo,
                    "commit": ("a" if name == "pyao" else "b") * 40,
                    "ci_runs": [1, 2] if name == "pyao" else [3],
                }
                for name, (repo, _) in release.REPOSITORIES.items()
            },
            "packages": [],
            "evidence": {},
        }
        for key in sorted(release.PACKAGES):
            name, architecture = key.split("/")
            file = self.root / f"{name}-{architecture}.snap"
            file.write_text(
                json.dumps(
                    {
                        "metadata": {
                            "name": name,
                            "version": "1.0.0rc1",
                            "confinement": "strict",
                            "architectures": [architecture],
                        },
                        "provenance": {
                            "commit": self.manifest["sources"][name]["commit"],
                            "version": "1.0.0rc1",
                            "dirty": False,
                        },
                    }
                )
            )
            self.manifest["packages"].append(
                {
                    "name": name,
                    "architecture": architecture,
                    "file": str(file),
                    "sha256": release.digest(file),
                }
            )
        commits = {"server_commit": "a" * 40, "client_commit": "b" * 40}
        r10 = {
            **commits,
            "release_version": "1.0.0rc1",
            "clients": 2,
            "live_tls_sessions_drained": 2,
            "godot_measured_seconds": [1801, 1802],
            "export_provenance": {"commit": "b" * 40, "clean_before_export": True},
            "acceptance": {
                "r10_gameplay_passed": True,
                "missing": [],
                "completed": sorted(release.REQUIRED_SCENARIOS),
            },
        }
        for flag in (
            "passed",
            "long_acceptance",
            "native_export",
            "installed_wheel",
            "tls",
            "graceful_sigterm",
        ):
            r10[flag] = True
        upgrade = {**commits, "production_data_used": False}
        for flag in (
            "legacy_migrated",
            "progress_preserved",
            "idempotent",
            "restart_preserved",
            "rollback_verified",
            "legacy_config_checked",
        ):
            upgrade[flag] = True
        reference = self.evidence("unit-test-only", {"synthetic": True})
        requirements = {
            **commits,
            "requirements": {
                f"R{i:02d}": {"passed": True, "evidence": [reference]}
                for i in range(1, 10)
            },
        }
        requirements["requirements"]["R09"]["candidate_passed"] = True
        for key, value in (
            ("r10", r10),
            ("upgrade", upgrade),
            ("requirements", requirements),
        ):
            self.manifest["evidence"][key] = self.evidence(key, value)
        records = []
        for scenario in sorted(release.CAMPAIGN_SCENARIOS):
            evidence = self.manifest["evidence"]["r10"] if scenario == "full" else self.evidence(scenario, {**commits, "release_version": "1.0.0rc1", "regression_passed": True, "native_export": True, "installed_wheel": True, "tls": True})
            records.append({"scenario": scenario, "proof": evidence["file"], "sha256": evidence["sha256"]})
        self.manifest["evidence"]["campaign"] = self.evidence("campaign", {"passed": True, "sources": {"server": "a" * 40, "client": "b" * 40}, "records": records})
        self.path = self.root / "pair.json"
        self.stage = self.root / "staged"

    def evidence(self, name, value):
        path = self.root / f"{name}.json"
        path.write_text(json.dumps(value))
        return {"file": str(path), "sha256": release.digest(path)}

    def prepare(self):
        self.path.write_text(json.dumps(self.manifest))
        return release.prepare(self.path, self.stage, self.store)

    def test_uploads_do_not_change_channels_and_all_precede_promotion(self):
        baseline = self.store.channels("latest/edge")
        self.assertEqual(self.prepare()["status"], "ready")
        self.assertEqual(self.store.current, baseline)
        result = release.promote(self.stage / "state.json", self.store)
        self.assertEqual(result["status"], "published")
        self.assertEqual(self.store.events, ["upload"] * len(release.PACKAGES) + ["release"] * len(release.PACKAGES))
        self.assertEqual(self.store.current, result["candidates"])
        self.assertIn("promotion_completed_at", result)

    def test_missing_package_or_different_version_never_uploads(self):
        self.manifest["packages"].pop()
        with self.assertRaisesRegex(RuntimeError, "incompleto"):
            self.prepare()
        self.assertFalse(self.store.events)

    def test_first_arm64_release_has_an_explicit_empty_baseline(self):
        self.store.current.pop("pyao-client/arm64")
        self.assertIsNone(self.prepare()["baseline"]["pyao-client/arm64"])
        result = release.promote(self.stage / "state.json", self.store)
        self.assertEqual(result["status"], "published")
        self.assertIsNotNone(self.store.channels("latest/edge")["pyao-client/arm64"])

    def test_uncertain_first_arm64_release_restores_its_absence_and_previous_amd64(self):
        self.store.current.pop("pyao-client/arm64")
        baseline = self.store.channels("latest/edge")
        self.prepare()
        self.store.release_failure = len(release.PACKAGES)
        with self.assertRaises(TimeoutError):
            release.promote(self.stage / "state.json", self.store)
        self.assertEqual(self.store.channels("latest/edge"), baseline)
        self.assertEqual(self.store.events.count("close"), 1)
        self.assertEqual(release.read(self.stage / "state.json")["status"], "rolled-back")

    def test_missing_current_campaign_never_uploads(self):
        self.manifest["evidence"].pop("campaign")
        with self.assertRaisesRegex(RuntimeError, "campaña completa"):
            self.prepare()
        self.assertFalse(self.store.events)

    def test_missing_campaign_scenario_never_uploads(self):
        value = release.read(Path(self.manifest["evidence"]["campaign"]["file"]))
        value["records"].pop()
        self.manifest["evidence"]["campaign"] = self.evidence("campaign", value)
        with self.assertRaisesRegex(RuntimeError, "Campaña incompleta"):
            self.prepare()
        self.assertFalse(self.store.events)

    def test_old_or_dirty_provenance_never_uploads(self):
        package = self.manifest["packages"][0]
        file = Path(package["file"])
        value = release.read(file)
        value["provenance"]["dirty"] = True
        file.write_text(json.dumps(value))
        package["sha256"] = release.digest(file)
        with self.assertRaisesRegex(RuntimeError, "Procedencia"):
            self.prepare()
        self.assertFalse(self.store.events)

    def test_mismatched_version_never_uploads(self):
        self.manifest["version"] = "1.0.0rc2"
        with self.assertRaisesRegex(RuntimeError, "1.0.0rc1"):
            self.prepare()
        self.assertFalse(self.store.events)

    def test_short_r10_and_missing_gameplay_never_upload(self):
        evidence = self.manifest["evidence"]["r10"]
        value = release.read(Path(evidence["file"]))
        value["godot_measured_seconds"][1] = 30
        self.manifest["evidence"]["r10"] = self.evidence("r10", value)
        with self.assertRaisesRegex(RuntimeError, "30 minutos"):
            self.prepare()
        value["godot_measured_seconds"][1] = 1800
        value["acceptance"]["completed"].remove("combat")
        self.manifest["evidence"]["r10"] = self.evidence("r10", value)
        with self.assertRaisesRegex(RuntimeError, "escenarios"):
            self.prepare()
        self.assertFalse(self.store.events)

    def test_pending_or_changed_main_cannot_release(self):
        self.prepare()
        self.store.moved_main = True
        with self.assertRaisesRegex(RuntimeError, "main cambió"):
            release.promote(self.stage / "state.json", self.store)
        self.assertNotIn("release", self.store.events)

    def test_failed_ci_cannot_upload(self):
        with patch.object(
            self.store,
            "ci",
            return_value={
                "headSha": "a" * 40,
                "status": "in_progress",
                "conclusion": "",
                "workflowName": "CI",
            },
        ):
            with self.assertRaises(RuntimeError):
                self.prepare()
        self.assertFalse(self.store.events)

    def test_failed_review_leaves_entire_previous_pair(self):
        baseline = self.store.channels("latest/edge")
        self.store.upload_failure = 2
        with self.assertRaisesRegex(RuntimeError, "rechazada"):
            self.prepare()
        self.assertEqual(self.store.current, baseline)
        self.assertNotIn("release", self.store.events)
        with self.assertRaisesRegex(RuntimeError, "completamente revisada"):
            release.promote(self.stage / "state.json", self.store)

    def test_changed_package_or_channel_cannot_release(self):
        receipt = self.prepare()
        self.store.current["pyao/arm64"]["revision"] = 88
        with self.assertRaisesRegex(RuntimeError, "canal cambió"):
            release.promote(self.stage / "state.json", self.store)
        self.store.current = receipt["baseline"]
        Path(receipt["manifest"]["packages"][0]["file"]).write_text("alterado")
        with self.assertRaisesRegex(RuntimeError, "SHA256"):
            release.promote(self.stage / "state.json", self.store)
        self.assertNotIn("release", self.store.events)

    def test_lost_ack_after_partial_promotion_restores_every_previous_revision(self):
        baseline = self.store.channels("latest/edge")
        self.prepare()
        self.store.release_failure = 2
        with self.assertRaises(TimeoutError):
            release.promote(self.stage / "state.json", self.store)
        self.assertEqual(self.store.current, baseline)
        receipt = release.read(self.stage / "state.json")
        self.assertEqual(receipt["status"], "rolled-back")
        self.assertEqual(self.store.events.count("release"), 2 + len(release.PACKAGES))

    def test_snap_metadata_supports_real_snapcraft_block_architectures(self):
        with patch.object(
            release,
            "command",
            side_effect=[
                "name: pyao\nversion: 1.0.0rc1\narchitectures:\n- arm64\nconfinement: strict\n",
                '{"commit":"example"}',
            ],
        ):
            metadata, _ = release.Store().inspect(Path("example.snap"), "pyao")
        self.assertEqual(metadata["architectures"], ["arm64"])

    def test_real_upload_command_never_passes_a_channel(self):
        with patch.object(
            release, "command", return_value="Revision 123 created for 'pyao'.\n"
        ) as run:
            revision = release.Store().upload(
                Path("example.snap"), "pyao", self.root / "upload.log"
            )
        self.assertEqual(revision, 123)
        self.assertEqual(run.call_args.args[0], ["snapcraft", "upload", "example.snap"])

    def test_interrupted_process_can_restore_from_its_private_receipt(self):
        receipt = self.prepare()
        candidate = next(iter(receipt["candidates"].values()))
        self.store.release(candidate["name"], candidate["revision"], "latest/edge")
        receipt["status"] = "promoting"
        result = release.rollback(self.stage / "state.json", receipt, self.store)
        self.assertEqual(result["status"], "rolled-back")
        self.assertEqual(self.store.current, receipt["baseline"])

    def test_postpublication_validation_can_restore_pair_but_not_overwrite_a_later_release(
        self,
    ):
        receipt = self.prepare()
        state = self.stage / "state.json"
        release.promote(state, self.store)
        args = SimpleNamespace(command="recover", state=state)
        self.store.current["pyao/amd64"]["revision"] = 999
        with self.assertRaisesRegex(RuntimeError, "recibo viejo"):
            release.execute(args, self.store)
        self.assertEqual(self.store.events.count("release"), len(release.PACKAGES))
        self.store.current = receipt["candidates"]
        with patch("builtins.print"):
            release.execute(args, self.store)
        self.assertEqual(self.store.current, receipt["baseline"])


if __name__ == "__main__":
    unittest.main()
