"""El comparador distingue agua, paredes y el bit independiente de techo."""

import base64
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("terrain_audit", Path(__file__).parents[1] / "audit-terrain.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class TerrainTests(unittest.TestCase):
    def test_every_cell_and_mask_semantics_are_checked(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "metadata_fixture.json").write_text('{"i":1}\n')
            (root / "blocked_fixture.json").write_text('{"m":1,"x":1,"y":1,"t":"w"}\n{"m":1,"x":2,"y":1,"t":"b"}\n')
            (root / "objects_fixture.json").write_text('{"m":1,"x":3,"y":1,"t":"tree"}\n')
            flags = bytearray(10000)
            flags[:3] = bytes([4, 3, 1])  # water, wall+roof, tree
            proof = root / "proof.json"
            def write(): proof.write_text(json.dumps({"maps":{"1":{"flags":base64.b64encode(flags).decode()}}}))
            write()
            result = module.inspect(root, proof)
            self.assertTrue(result["passed"])
            self.assertEqual(10000, result["tiles_compared"])
            flags[9999] = 1
            write()
            result = module.inspect(root, proof)
            self.assertFalse(result["passed"])
            self.assertEqual((100,100), (result["differences"][0]["x"], result["differences"][0]["y"]))
