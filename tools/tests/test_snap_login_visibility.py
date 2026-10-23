"""Replay observations from two real Store captures without a Pillow dependency."""
import ast
import json
from pathlib import Path
from types import SimpleNamespace
import unittest


SOURCE = Path(__file__).resolve().parents[1] / "snap-ui-smoke.py"
METHOD = next(node for node in ast.parse(SOURCE.read_text()).body
              if isinstance(node, ast.FunctionDef) and node.name == "login_visible")
namespace = {}
exec(compile(ast.Module(body=[METHOD], type_ignores=[]), str(SOURCE), "exec"), namespace)
visible = namespace["login_visible"]
STATES = json.loads((Path(__file__).parent / "fixtures/login_probe_samples.json").read_text())["states"]


class CaptureObservations:
    def __init__(self, state, *, blank=False):
        self.state = state
        self.blank = blank

    def convert(self, mode):
        return self

    def getpixel(self, point):
        return (0, 0, 0) if self.blank else self.state["pixels"][",".join(map(str, point))]

    def crop(self, box):
        count = 0 if self.blank else self.state["labels"][",".join(map(str, box))]
        region = SimpleNamespace(getcolors=lambda limit: [(count, 255)])
        region.convert = lambda mode: region
        return region


class SnapLoginVisibilityTests(unittest.TestCase):
    def test_first_login_without_a_saved_username(self):
        self.assertTrue(visible(CaptureObservations(STATES["empty_username"])))

    def test_reopened_form_with_a_saved_username(self):
        self.assertTrue(visible(CaptureObservations(STATES["remembered_username"])))

    def test_blank_transition_is_not_a_login_form(self):
        self.assertFalse(visible(CaptureObservations(STATES["empty_username"], blank=True)))


if __name__ == "__main__":
    unittest.main()
