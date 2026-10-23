"""Una falla de RDB no deja la fixture Redis viva ni expone argumentos secretos."""
import ast
import contextlib
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, call, patch

source = Path(__file__).resolve().parents[1] / "integration-world.py"
klass = next(n for n in ast.parse(source.read_text()).body if isinstance(n, ast.ClassDef) and n.name == "NativeRedis")
method = next(n for n in klass.body if isinstance(n, ast.FunctionDef) and n.name == "__exit__")


class OwnedRedisCleanupTests(unittest.TestCase):
    def test_failed_snapshot_uses_nosave_only_on_the_owned_client(self):
        class ResponseError(Exception): pass
        namespace = {"contextlib": contextlib, "json": json, "stop": Mock()}
        exec(compile(ast.Module(body=[method], type_ignores=[]), str(source), "exec"), namespace)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            evidence = root / "evidence"
            log = (root / "redis.log").open("wb")
            log.write(b"Private fixture: background save failed\n")
            client = SimpleNamespace(
                shutdown=Mock(side_effect=[ResponseError("synthetic-secret"), None]),
                info=Mock(side_effect=lambda section: {"rdb_last_bgsave_status": "err", "password": "synthetic-secret"} if section != "errorstats" else {"errorstat_MISCONF": {"count": 1}}),
            )
            fixture = SimpleNamespace(root=root, evidence=evidence, log=log, process=object(), wsl_data_dir=None, storage_kind="wsl-linux", client=lambda: contextlib.nullcontext(client))
            with patch.dict(sys.modules, {"redis.exceptions": SimpleNamespace(ResponseError=ResponseError)}):
                namespace["__exit__"](fixture)
            self.assertEqual(client.shutdown.call_args_list, [call(save=True), call(nosave=True)])
            namespace["stop"].assert_called_once_with(fixture.process)
            self.assertTrue(log.closed)
            proof = json.loads((evidence / "redis-runtime.json").read_text())
            self.assertEqual(proof["state"]["rdb_last_bgsave_status"], "err")
            self.assertNotIn("synthetic-secret", (evidence / "redis-runtime.json").read_text())
            self.assertIn("background save failed", (evidence / "redis-runtime.log").read_text())


if __name__ == "__main__": unittest.main()
