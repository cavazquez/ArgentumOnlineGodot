"""El smoke acepta el esquema de su fixture y rechaza estados incompatibles."""
from pathlib import Path
import sys
import unittest
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from store_schema_evidence import verify_schema


class StoreSchemaEvidenceTests(unittest.TestCase):
    def test_current_and_future_fixture_versions_do_not_need_a_literal_update(self):
        for expected in (5, 6):
            with self.subTest(expected=expected):
                store = Mock()
                store.hget.return_value = str(expected)
                self.assertEqual(verify_schema(store, expected), expected)
                store.hget.assert_called_once_with("schema:state", "version")

    def test_older_schema_is_rejected(self):
        store = Mock()
        store.hget.return_value = "4"
        with self.assertRaisesRegex(RuntimeError, "esperado 5, recibido '4'"):
            verify_schema(store, 5)

    def test_newer_schema_is_rejected(self):
        store = Mock()
        store.hget.return_value = "6"
        with self.assertRaisesRegex(RuntimeError, "esperado 5, recibido '6'"):
            verify_schema(store, 5)

    def test_missing_schema_is_rejected(self):
        store = Mock()
        store.hget.return_value = None
        with self.assertRaisesRegex(RuntimeError, "esperado 5, recibido None"):
            verify_schema(store, 5)
