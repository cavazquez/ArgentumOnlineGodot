"""La topología distingue salidas físicas, teleports y enlaces unidireccionales."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "world_topology", Path(__file__).parents[1] / "build-world-topology.py"
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class TopologyTests(unittest.TestCase):
    def test_no_reverse_teleport_is_invented(self):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            scenes = root / "Maps"
            scenes.mkdir()
            for n in (1, 2, 3, 4):
                (scenes / f"Map{n}.tscn").write_text("fixture")
            (root / "transitions_test.json").write_text(
                "\n".join(
                    json.dumps(r)
                    for r in [
                        {
                            "from_map": 1,
                            "exits": [
                                {"x": 50, "y": 7, "to_map": 2, "to_x": 50, "to_y": 93},
                                {"x": 50, "y": 50, "to_map": 3, "to_x": 60, "to_y": 60},
                            ],
                        },
                        {
                            "from_map": 2,
                            "exits": [
                                {"x": 50, "y": 93, "to_map": 1, "to_x": 50, "to_y": 7}
                            ],
                        },
                    ]
                )
            )
            data = module.build(root, scenes, None)
            self.assertEqual([], data["errors"])
            cardinal = next(e for e in data["edges"] if e["to"] == 2)
            teleport = next(e for e in data["edges"] if e["to"] == 3)
            self.assertEqual("cardinal", cardinal["kind"])
            self.assertTrue(cardinal["reciprocal"])
            self.assertEqual("teleport", teleport["kind"])
            self.assertFalse(teleport["reciprocal"])
            self.assertIn("4", data["maps"])
            self.assertEqual(
                4, len({tuple(v["position"]) for v in data["maps"].values()})
            )

    def test_diagonal_offset_and_invalid_destination_are_preserved(self):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            scenes = root / "Maps"
            scenes.mkdir()
            for n in (1, 2, 3):
                (scenes / f"Map{n}.tscn").write_text("fixture")
            rows = [
                {
                    "from_map": 1,
                    "exits": [
                        {"x": 93, "y": 93, "to_map": 2, "to_x": 7, "to_y": 7},
                        {"x": 7, "y": 40, "to_map": 3, "to_x": 93, "to_y": 60},
                        {"x": 7, "y": 40, "to_map": 999, "to_x": 93, "to_y": 60},
                    ],
                }
            ]
            (root / "transitions_fixture.json").write_text(json.dumps(rows[0]))
            data = module.build(root, scenes, None)
            diagonal = next(e for e in data["edges"] if e["to"] == 2)
            offset = next(e for e in data["edges"] if e["to"] == 3)
            self.assertEqual("diagonal", diagonal["kind"])
            self.assertFalse(diagonal["reciprocal"])
            self.assertEqual([1, 1], diagonal["direction"])
            self.assertEqual([[7, 40, 93, 60]], offset["exits"])
            self.assertEqual("cardinal", offset["kind"])
            self.assertEqual(1, len(data["errors"]))
            self.assertEqual(999, data["errors"][0]["to"])
