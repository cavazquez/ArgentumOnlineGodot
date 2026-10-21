"""La campaña conserva el wheel, Python privado y audio del par seleccionado."""

import importlib.util
from pathlib import Path
from types import SimpleNamespace
import unittest

spec = importlib.util.spec_from_file_location("campaign_runtime", Path(__file__).parents[1] / "campaign-50.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class CampaignRuntimeTests(unittest.TestCase):
    def test_every_scenario_uses_the_selected_private_server_and_native_audio(self):
        args = SimpleNamespace(server_project=Path("server source"), godot=Path("Godot engine"), client_executable=Path("client export"), wheel=Path("server wheel.whl"), server_bundle=Path("private server"), client_audio="PulseAudio")
        for scenario in ("full", "potions", "expansion", "economy", "npcs", "npc-policy"):
            with self.subTest(scenario=scenario):
                command = module.scenario_command(args, scenario, 1800, Path("test output"))
                for flag, value in (("--wheel", "server wheel.whl"), ("--server-bundle", "private server"), ("--client-audio", "PulseAudio"), ("--scenario", scenario)):
                    self.assertEqual(command[command.index(flag) + 1], value)
                self.assertNotIn("--source", command)

    def test_wheel_only_mode_keeps_optional_arguments_absent(self):
        args = SimpleNamespace(server_project=Path("server"), godot=Path("godot"), client_executable=Path("client"), wheel=Path("server.whl"), server_bundle=None, client_audio=None)
        command = module.scenario_command(args, "full", 1800, Path("output"))
        self.assertNotIn("--server-bundle", command)
        self.assertNotIn("--client-audio", command)


if __name__ == "__main__": unittest.main()
