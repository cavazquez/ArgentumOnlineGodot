"""The distributed RTT case must not invalidate the final peer-chat acceptance."""

from pathlib import Path
import sys
import unittest
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).parents[1]))
from structure_profile_matrix import run_matrix


class StructureProfileFixtureTests(unittest.TestCase):
    def test_matrix_measures_separate_maps_then_restores_peer_visibility(self):
        world = SimpleNamespace()
        cases, resets = [], []
        world.reset = lambda _store: resets.append(dict(world.base))
        world.benchmark = lambda _store, **options: cases.append((dict(world.base), options))
        run_matrix(world, object(), 30, 40)
        self.assertEqual(len(cases), 3)
        self.assertEqual({v[0] for v in cases[0][0].values()}, {2})
        self.assertEqual(cases[1][1]["slow_readers"], 0)
        self.assertEqual({v[0] for v in cases[2][0].values()}, {1, 2})
        self.assertEqual({v[0] for v in world.base.values()}, {2})
        self.assertEqual(resets[-1], world.base)
