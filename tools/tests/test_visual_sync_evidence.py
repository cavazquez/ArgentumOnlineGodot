"""La evidencia visual exige animación real del actor en la ventana observada."""

import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from visual_sync_world import acceptance, login_effect_seen


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


if __name__ == "__main__":
    unittest.main()
