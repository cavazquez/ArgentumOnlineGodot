"""La evidencia visual exige animación real del actor en la ventana observada."""

import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from visual_sync_world import VisualSyncWorld, acceptance, login_effect_seen


class VisualSyncEvidenceTests(unittest.TestCase):
    def test_packets_or_one_still_frame_do_not_prove_an_animation(self):
        view = {"fx_packets": [{"kind": "fx", "char_index": 7, "fx": 1, "loops": 1}]}
        self.assertFalse(login_effect_seen(view, 7))
        frame = {"char_index": 7, "fx": 1, "frame": 0, "visible": True, "playing": True}
        view["fx_frames"] = [frame, dict(frame)]
        self.assertFalse(login_effect_seen(view, 7))
        view["fx_frames"].append({**frame, "frame": 1})
        self.assertTrue(login_effect_seen(view, 7))
        self.assertFalse(login_effect_seen(view, 8))
        for row in view["fx_frames"]: row["visible"] = False
        self.assertFalse(login_effect_seen(view, 7))

    def test_both_scenarios_are_required(self):
        self.assertFalse(acceptance([{"id": "login-fx", "passed": True}], 10)["test_execution_passed"])
        self.assertTrue(acceptance([{"id": key, "passed": True} for key in ("login-fx", "meditation")], 10)["test_execution_passed"])

    def test_dummy_muted_or_interrupted_playback_cannot_prove_real_audio(self):
        world = VisualSyncWorld.__new__(VisualSyncWorld)
        world.expected_audio_driver = "PulseAudio"
        row = {"started": True, "finished": True, "driver": "PulseAudio", "resource": "res://Assets/Sfx/3.wav",
               "bus_muted": False, "master_muted": False, "bus_db": 0, "master_db": 0}
        view = {"audio_driver": "PulseAudio", "audio_playback": [row]}
        self.assertTrue(world.audio_completed(view, "res://Assets/Sfx/3.wav"))
        row["finished"] = False
        self.assertFalse(world.audio_completed(view))
        row["finished"] = True
        row["master_muted"] = True
        self.assertFalse(world.audio_completed(view))
        row["master_muted"] = False
        row["driver"] = view["audio_driver"] = world.expected_audio_driver = "Dummy"
        self.assertFalse(world.audio_completed(view))


if __name__ == "__main__":
    unittest.main()
