"""No se usa el checkout del servidor al probar un paquete con Python privado."""

import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).parents[1]))
from server_bundle import digest, verify_bundle


class ServerBundleTests(unittest.TestCase):
    def test_identity_hashes_and_unexpected_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "private"
            root.mkdir()
            python = root / "python.exe"
            python.write_bytes(b"private runtime")
            wheel = Path(temporary) / "server.whl"
            wheel.write_bytes(b"wheel")
            record = {"dirty": False, "version": "1.0.0rc5", "commit": "a" * 40, "wheel_sha256": digest(wheel), "files": {"python.exe": digest(python)}, "python_path": "python.exe"}
            (root / "server-candidate.json").write_text(json.dumps(record))
            self.assertEqual(verify_bundle(root, "a" * 40, "1.0.0rc5", wheel), python)
            with self.assertRaises(ValueError): verify_bundle(root, "b" * 40, "1.0.0rc5", wheel)
            (root / "extra").write_text("unexpected")
            with self.assertRaises(ValueError): verify_bundle(root, "a" * 40, "1.0.0rc5", wheel)
            (root / "extra").unlink()
            python.write_bytes(b"modified runtime")
            with self.assertRaises(ValueError): verify_bundle(root, "a" * 40, "1.0.0rc5", wheel)

    def test_python_cannot_escape_to_an_installed_interpreter(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "payload").write_bytes(b"approved")
            wheel = root / "server.whl"
            wheel.write_bytes(b"wheel")
            files = {p.name: digest(p) for p in (root / "payload", wheel)}
            record = {"dirty": False, "version": "1.0.0rc5", "commit": "a" * 40, "wheel_sha256": digest(wheel), "files": files, "python_path": "../python"}
            (root / "server-candidate.json").write_text(json.dumps(record))
            with self.assertRaises(ValueError): verify_bundle(root, "a" * 40, "1.0.0rc5", wheel)


if __name__ == "__main__": unittest.main()
