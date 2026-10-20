"""Matching counters cannot make an outdated sentence snapshot acceptable."""

from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lifetime_stats_view import FIELDS, LABELS, ministats_match


class SentenceSnapshotTests(unittest.TestCase):
    def test_waits_for_the_expected_sentence_with_the_same_counters(self):
        expected = dict.fromkeys(FIELDS, 3)
        values = {name: "3" for name in LABELS.values()}
        for previous in (None, "2", "1"):
            stale = dict(values)
            if previous is not None:
                stale["Cárcel: días restantes"] = previous
            self.assertFalse(
                ministats_match({"ministats": stale}, expected, jail_days=0)
            )
        values["Cárcel: días restantes"] = "0"
        self.assertTrue(ministats_match({"ministats": values}, expected, jail_days=0))
        values["Muertes propias"] = "2"
        self.assertFalse(ministats_match({"ministats": values}, expected, jail_days=0))
