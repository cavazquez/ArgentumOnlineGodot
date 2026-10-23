"""Recuperación de transporte acotada, con checksum obligatorio antes de extraer."""
import hashlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

source = Path(__file__).resolve().parents[1] / "build-test-redis.py"
spec = importlib.util.spec_from_file_location("redis_fixture_build", source)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class Partial(io.BytesIO):
    def read(self, size=-1):
        if self.tell():
            raise urllib.error.URLError("connection lost")
        return super().read(3)


class RedisDownloadTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.archive = Path(temporary.name) / "redis.tar.gz"
        self.payload = b"verified fixture source"
        checksum = patch.object(module, "SHA256", hashlib.sha256(self.payload).hexdigest())
        checksum.start()
        self.addCleanup(checksum.stop)
        sleeper = patch.object(module.time, "sleep")
        self.sleep = sleeper.start()
        self.addCleanup(sleeper.stop)

    def test_dns_failure_is_retried_and_still_verified(self):
        with patch.object(module.urllib.request, "urlopen", side_effect=[
            urllib.error.URLError("DNS unavailable"), io.BytesIO(self.payload),
        ]) as opening:
            module.download(self.archive)
        self.assertEqual(opening.call_count, 2)
        self.assertEqual(self.archive.read_bytes(), self.payload)

    def test_partial_file_is_replaced_before_retry(self):
        with patch.object(module.urllib.request, "urlopen", side_effect=[
            Partial(b"partial"), io.BytesIO(self.payload),
        ]):
            module.download(self.archive)
        self.assertEqual(self.archive.read_bytes(), self.payload)

    def test_transport_attempts_are_bounded(self):
        with patch.object(module.urllib.request, "urlopen", side_effect=urllib.error.URLError("DNS")) as opening:
            with self.assertRaises(urllib.error.URLError):
                module.download(self.archive)
        self.assertEqual(opening.call_count, 3)
        self.assertEqual(self.sleep.call_count, 2)

    def test_permanent_http_error_does_not_retry(self):
        error = urllib.error.HTTPError(module.URL, 404, "Not found", {}, None)
        with patch.object(module.urllib.request, "urlopen", side_effect=error) as opening:
            with self.assertRaises(urllib.error.HTTPError):
                module.download(self.archive)
        opening.assert_called_once()
        self.sleep.assert_not_called()

    def test_bad_checksum_is_rejected_without_retries(self):
        with patch.object(module.urllib.request, "urlopen", return_value=io.BytesIO(b"altered")) as opening:
            with self.assertRaisesRegex(ValueError, "SHA256"):
                module.download(self.archive)
        opening.assert_called_once()
        self.sleep.assert_not_called()
