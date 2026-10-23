"""El ensayo distingue un formato nuevo de una pérdida real del equipo protegido."""
import ast
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import Mock

# Ejecutar el método real sin importar la preparación de mapas del servidor.
source = Path(__file__).resolve().parents[1] / "full_world.py"
world_class = next(n for n in ast.parse(source.read_text()).body if isinstance(n, ast.ClassDef) and n.name == "FullWorld")
method = next(n for n in world_class.body if isinstance(n, ast.FunctionDef) and n.name == "thief_objects")
namespace = {}
exec(compile(ast.Module(body=[method], type_ignores=[]), str(source), "exec"), namespace)


class ThiefItemEvidenceTests(unittest.TestCase):
    def exercise(self, change=None):
        world = SimpleNamespace()
        world.ids = {1: 101, 2: 202}
        world.reset = Mock()
        world.command = Mock()
        world.items = Mock(return_value={1: (15, 1)})
        world.both_screens = Mock()
        world.passed = Mock()
        fields = {"slot_1": "i1:15:" + "a" * 32, "weapon": "1"}
        store = SimpleNamespace(hget=lambda key, field: fields.get(field))
        moved = [False]
        def steal(*args):
            moved[0] = True
            if change: fields.update(change)
        world.attempt = Mock(side_effect=steal)
        world.count = Mock(side_effect=lambda store, player, item: 3 + (1 if player == 1 else -1) * int(moved[0]))
        world.wait = Mock(side_effect=lambda predicate, label: self.assertTrue(predicate(), label))
        namespace["thief_objects"](world, store, 50, 50)
        world.passed.assert_called_once()

    def test_individual_identity_does_not_report_a_false_theft(self):
        self.exercise()

    def test_replaced_or_removed_identity_still_fails(self):
        for value in (None, "", "i1:15:" + "b" * 32, "15:1"):
            with self.subTest(value=value), self.assertRaisesRegex(RuntimeError, "equipo protegido"):
                self.exercise({"slot_1": value})

    def test_equipment_removed_from_its_slot_still_fails(self):
        with self.assertRaisesRegex(RuntimeError, "equipo protegido"):
            self.exercise({"weapon": "0"})


if __name__ == "__main__": unittest.main()
