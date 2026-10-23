import importlib.util
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[1] / "snapshot_observation.py"
spec = importlib.util.spec_from_file_location("snapshot_observation", path)
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class TimedRedisTests(unittest.TestCase):
    def test_info_is_measured_as_well_as_ping(self):
        class Client:
            def info(self, section):
                return {section: True}
            def ping(self):
                return True
        rows = []
        client = probe.TimedRedis(Client(), rows)
        self.assertEqual(client.info("persistence"), {"persistence": True})
        self.assertTrue(client.ping())
        self.assertEqual([row["command"] for row in rows], ["info", "ping"])
        self.assertTrue(all(row["ok"] and row["seconds"] >= 0 for row in rows))

    def test_failure_is_recorded_and_remains_a_failure(self):
        class Client:
            def ping(self):
                raise TimeoutError("owned test")
        rows = []
        with self.assertRaises(TimeoutError):
            probe.TimedRedis(Client(), rows).ping()
        self.assertFalse(rows[0]["ok"])
        self.assertEqual(rows[0]["error"], "TimeoutError")
