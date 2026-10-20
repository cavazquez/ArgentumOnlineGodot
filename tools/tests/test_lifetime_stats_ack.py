"""Contadores correctos no convierten una condena anterior en un ACK nuevo."""

import importlib.util
import sys
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "lifetime_stats_ack_subject", Path(__file__).parents[1] / "lifetime_stats_world.py"
)
module = importlib.util.module_from_spec(spec)
# El escenario completo requiere el servidor; el ACK de la vista es independiente
# de Redis y debe poder verificarse en el job de herramientas del cliente.
with patch.dict(
    sys.modules,
    {
        "full_world": SimpleNamespace(FullWorld=object),
        "skills_world": SimpleNamespace(prepare_fixture=None),
    },
):
    spec.loader.exec_module(module)


class LifetimeStatsACKTests(unittest.TestCase):
    def test_stale_sentence_is_rejected_before_returning_the_snapshot(self):
        seen = []
        fields = {name: "0" for name in module.LABELS.values()}

        def view(index, predicate, _):
            old = {"ministats": {**fields, "Cárcel: días restantes": "1"}}
            new = {"ministats": {**fields, "Cárcel: días restantes": "0"}}
            if index == 2:
                self.assertFalse(predicate(old))
            self.assertTrue(predicate(new))
            seen.append(index)
            return new

        world = SimpleNamespace(
            command=lambda *args: None, view=view, screen=lambda *args: None
        )
        with patch.object(
            module,
            "counters",
            return_value={i: {k: 0 for k in module.FIELDS} for i in (1, 2)},
        ):
            result = module.show(world, None, "expiry", jail_days={2: 0})
        self.assertEqual([1, 2], seen)
        self.assertEqual("0", result[2]["Cárcel: días restantes"])
