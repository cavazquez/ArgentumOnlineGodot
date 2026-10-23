"""La llegada segura no debe convertir al acompañante en el objetivo del encuentro."""
import ast
from pathlib import Path
from types import SimpleNamespace
import unittest

source = Path(__file__).resolve().parents[1] / "r10_world.py"
world = next(node for node in ast.parse(source.read_text()).body
             if isinstance(node, ast.ClassDef) and node.name == "R10World")
method = next(node for node in world.body if isinstance(node, ast.FunctionDef) and node.name == "encounter")
namespace = {}
exec(compile(ast.Module(body=[method], type_ignores=[]), str(source), "exec"), namespace)


class EncounterSeparationTests(unittest.TestCase):
    def test_companion_stays_outside_aggro_after_safe_arrival_adjustment(self):
        for nx, ny in ((18, 14), (9, 12), (95, 95)):
            with self.subTest(npc=(nx, ny)):
                npc = {"x": str(nx), "y": str(ny)}
                store = SimpleNamespace(hgetall=lambda _key: npc, scan_iter=lambda _pattern: ["npc:target"])
                requested = {}
                def relocate(_store, positions, **_kwargs):
                    requested.update(positions)
                    return positions
                runner = SimpleNamespace(targets={"combat": "target"}, relocate=relocate)
                namespace["encounter"](runner, store, {"_forbidden": set()}, "combat", 1, 2)
                _, px, py = requested[1]
                _, cx, cy = requested[2]
                self.assertEqual(abs(px - nx) + abs(py - ny), 1)
                companion_distance = abs(cx - nx) + abs(cy - ny)
                self.assertGreater(companion_distance - 3, 8)
                self.assertLessEqual(abs(cx - px) + abs(cy - py) + 6, 30)
