"""La fixture de dos portables debe aislar perfiles conservando el candidato."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("native_profile", Path(__file__).parents[1] / "native_client_profile.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
PROFILE = '[application]\nrun/main_scene="res://tests/integration_world.tscn"\nrun/flush_stdout_on_print=true\n'


class NativeProfileTests(unittest.TestCase):
    def test_two_windows_profiles_keep_the_candidate_and_assets(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            source = root / "candidate"
            source.mkdir()
            binary = source / "client.exe"
            binary.write_bytes(b"same verified binary")
            (source / "override.cfg").write_text(PROFILE)
            (source / "client.pck").write_bytes(b"same resources")
            for index in (1, 2):
                copied = module.isolated_copy(binary, root, index, "win32")
                self.assertEqual(copied.read_bytes(), binary.read_bytes())
                self.assertEqual((copied.parent / "client.pck").read_bytes(), b"same resources")
                self.assertIn('custom_user_dir_name="PyAO-validation-', (copied.parent / "override.cfg").read_text())
            self.assertNotEqual((root / "native-client-1/override.cfg").read_text(), (root / "native-client-2/override.cfg").read_text())
            self.assertEqual((source / "override.cfg").read_text(), PROFILE)

    def test_mac_bundle_keeps_resources_and_sets_both_overrides(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            bundle = root / "candidate/Test.app/Contents"
            executable = bundle / "MacOS/client"
            executable.parent.mkdir(parents=True)
            (bundle / "Resources").mkdir()
            executable.write_bytes(b"same mac binary")
            (executable.parent / "override.cfg").write_text(PROFILE)
            (bundle / "Resources/client.pck").write_bytes(b"same pck")
            copied = module.isolated_copy(executable, root, 1, "darwin")
            self.assertEqual(copied.read_bytes(), executable.read_bytes())
            self.assertEqual((copied.parent / "override.cfg").read_bytes(), (copied.parent.parent / "Resources/override.cfg").read_bytes())
            self.assertEqual((copied.parent.parent / "Resources/client.pck").read_bytes(), b"same pck")

    def test_linux_uses_existing_xdg_isolation(self):
        self.assertEqual(module.isolated_copy(Path("unchanged"), Path("unused"), 1, "linux"), Path("unchanged"))
