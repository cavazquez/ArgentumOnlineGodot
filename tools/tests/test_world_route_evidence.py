"""La auditoría gráfica exige todos los mapas y enlaces, sin atribuirse red."""

import base64
import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "route_smoke", Path(__file__).parents[1] / "smoke-world-routes.py"
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class WorldRouteEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.topology = {
            "maps": {"1": {}, "2": {}},
            "edges": [{"from": 1, "to": 2}, {"from": 2, "to": 1}],
        }
        row = {
            "rendered": True,
            "flags": base64.b64encode(bytes(10000)).decode(),
            "cache": {
                "views": 1,
                "limit_views": 3,
                "estimated_bytes": 1000,
                "limit_bytes": 67108864,
            },
        }
        self.proof = {
            "passed": True,
            "display_server": "X11",
            "network_crossings": False,
            "maps": {"1": copy.deepcopy(row), "2": copy.deepcopy(row)},
            "rendered_pairs": [[1, 2], [2, 1]],
        }

    def test_complete_evidence(self):
        self.assertEqual(
            {"maps_rendered": 2, "directed_pairs_rendered": 2},
            module.validate_evidence(self.proof, self.topology),
        )

    def test_missing_map_or_pair_is_rejected(self):
        for key in ("maps", "rendered_pairs"):
            with self.subTest(key=key):
                proof = copy.deepcopy(self.proof)
                if key == "maps":
                    proof[key].pop("1")
                else:
                    proof[key].pop()
                with self.assertRaises(ValueError):
                    module.validate_evidence(proof, self.topology)

    def test_duplicates_invalid_ids_and_reversed_only_are_rejected(self):
        for pairs in (
            [[1, 2], [1, 2]],
            [[1, 2], [2, 1], [1, 2]],
            [[True, 2], [2, 1]],
            [[1.5, 2], [2, 1]],
        ):
            with self.subTest(pairs=pairs):
                self.proof["rendered_pairs"] = pairs
                with self.assertRaises(ValueError):
                    module.validate_evidence(self.proof, self.topology)

    def test_partial_mask_and_excessive_cache_are_rejected(self):
        for field, value in (
            ("flags", "AA=="),
            (
                "cache",
                {"views": 4, "limit_views": 3, "estimated_bytes": 1, "limit_bytes": 67108864},
            ),
        ):
            with self.subTest(field=field):
                proof = copy.deepcopy(self.proof)
                proof["maps"]["1"][field] = value
                with self.assertRaises(ValueError):
                    module.validate_evidence(proof, self.topology)

    def test_headless_or_network_claim_is_rejected(self):
        for field, value in (
            ("display_server", "headless"),
            ("display_server", None),
            ("network_crossings", True),
            ("passed", False),
        ):
            with self.subTest(field=field):
                proof = copy.deepcopy(self.proof)
                proof[field] = value
                with self.assertRaises(ValueError):
                    module.validate_evidence(proof, self.topology)
