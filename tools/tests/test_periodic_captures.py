"""La permanencia recoge PNG nativos, incluso cuando ya cerró el canal RPC."""

import hashlib
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).parents[1]))
from periodic_captures import collect_native_captures, ensure_fresh_captures, require_native_captures

PNG = b"\x89PNG\r\n\x1a\nfixture-pixels\x00\x00\x00\x00IEND\xaeB`\x82"


class PeriodicCaptureTests(unittest.TestCase):
    def test_native_files_after_control_channel_closes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            ensure_fresh_captures(root)
            (root / "godot-1.png").write_bytes(PNG)
            (root / "godot-1-0307s.png").write_bytes(PNG)
            (root / "godot-2-0309s.png").write_bytes(PNG)
            records = collect_native_captures(root, [])
            self.assertEqual([row["client"] for row in records], [1, 2])
            self.assertEqual([row["elapsed_seconds"] for row in records], [307, 309])
            self.assertEqual(records[0]["sha256"], hashlib.sha256(PNG).hexdigest())
            self.assertEqual(collect_native_captures(root, records), records)
            require_native_captures(records, 600)

    def test_partial_write_is_not_published(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            image = root / "godot-1-0301s.png"
            image.write_bytes(PNG[:-12])
            self.assertEqual(collect_native_captures(root, []), [])
            image.write_bytes(PNG)
            self.assertEqual(len(collect_native_captures(root, [])), 1)

    def test_previous_run_and_incomplete_pair_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "godot-1-0300s.png").write_bytes(PNG)
            with self.assertRaises(ValueError): ensure_fresh_captures(root)
            with self.assertRaises(RuntimeError):
                require_native_captures(collect_native_captures(root, []), 600)

    def test_verified_capture_cannot_change_or_disappear(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            image = root / "godot-1-0300s.png"
            image.write_bytes(PNG)
            records = collect_native_captures(root, [])
            image.write_bytes(PNG.replace(b"pixels", b"altered"))
            with self.assertRaises(ValueError): collect_native_captures(root, records)
            image.unlink()
            with self.assertRaises(ValueError): collect_native_captures(root, records)

    def test_link_and_invalid_capture_time_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            target = root / "real.png"
            target.write_bytes(PNG)
            link = root / "godot-1-0300s.png"
            link.symlink_to(target)
            with self.assertRaises(ValueError): collect_native_captures(root, [])
            link.unlink()
            (root / "godot-1-0001s.png").write_bytes(PNG)
            with self.assertRaises(ValueError): collect_native_captures(root, [])
