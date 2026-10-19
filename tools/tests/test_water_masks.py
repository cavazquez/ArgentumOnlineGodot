"""La costa usa datos del servidor sin modificar techos, bloqueos o gráficos."""

import base64
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "water_masks", Path(__file__).parents[1] / "build-water-masks.py"
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class WaterMaskTests(unittest.TestCase):
    def test_shore_update_preserves_other_flags_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            original = bytes([3, 4] + [0] * 9998)
            scene = root / "Map1.tscn"
            scene.write_text(
                'graphics=unchanged\nmetadata/data = PackedByteArray("'
                + base64.b64encode(original).decode()
                + '")\n'
            )
            (root / "objects_fixture.json").write_text(
                json.dumps({"m": 1, "x": 1, "y": 1, "t": "water"})
            )
            data = module.build(root, root)
            self.assertEqual([1], module.sync_scenes(data, root, check=True))
            self.assertEqual([1], module.sync_scenes(data, root))
            content = scene.read_text()
            updated = base64.b64decode(module.PATTERN.search(content)[2])
            self.assertEqual(7, updated[0])
            self.assertEqual(0, updated[1])
            self.assertEqual(
                [value & ~4 for value in original], [value & ~4 for value in updated]
            )
            self.assertIn("graphics=unchanged", content)
            self.assertEqual([], module.sync_scenes(data, root, check=True))

    def test_invalid_coordinates_fail_before_changing_scenes(self):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            scene = root / "Map1.tscn"
            scene.write_text("sentinel")
            (root / "blocked_fixture.json").write_text(
                json.dumps({"m": 1, "x": 101, "y": 1, "t": "w"})
            )
            with self.assertRaisesRegex(ValueError, "inválidas"):
                module.build(root, root)
            self.assertEqual("sentinel", scene.read_text())
