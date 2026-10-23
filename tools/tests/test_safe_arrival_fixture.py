"""La fixture admite el ajuste del servidor y conserva mapa, identidad y límite."""
import ast
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import Mock

source = Path(__file__).resolve().parents[1] / "r10_world.py"
world = next(node for node in ast.parse(source.read_text()).body
             if isinstance(node, ast.ClassDef) and node.name == "R10World")
method = next(node for node in world.body if isinstance(node, ast.FunctionDef) and node.name == "relocate")
namespace = {}
exec(compile(ast.Module(body=[method], type_ignores=[]), str(source), "exec"), namespace)


class SafeArrivalFixtureTests(unittest.TestCase):
    def relocate(self, view, *, allowed):
        runner = SimpleNamespace(ids={2: 22}, names=["One", "Two"], command=Mock(),
                                 receipts=[], save=Mock())
        store = SimpleNamespace(exists=lambda key: False, hset=Mock())
        runner.wait = lambda predicate, label: self.assertTrue(predicate(), label)
        def check_view(index, predicate, label):
            if not predicate(view):
                raise RuntimeError(label)
            return view
        runner.view = check_view
        return namespace["relocate"](runner, store, {2: (1, 56, 53)}, allow_adjustment=allowed)

    def test_actual_nearby_arrival_is_accepted_only_when_allowed(self):
        view = {"map": 1, "x": 55, "y": 52, "name": "Two"}
        self.assertEqual(self.relocate(view, allowed=True), {2: (1, 55, 52)})
        with self.assertRaises(RuntimeError):
            self.relocate(view, allowed=False)

    def test_far_arrival_wrong_map_or_wrong_character_is_rejected(self):
        for view in ({"map": 1, "x": 52, "y": 53, "name": "Two"},
                     {"map": 2, "x": 56, "y": 53, "name": "Two"},
                     {"map": 1, "x": 56, "y": 53, "name": "Other"}):
            with self.subTest(view=view), self.assertRaises(RuntimeError):
                self.relocate(view, allowed=True)
