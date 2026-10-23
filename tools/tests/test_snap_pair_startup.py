"""El primer Redis vacío tiene presupuesto propio; el reinicio y login no se amplían."""
import ast
from contextlib import nullcontext
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import Mock

source = Path(__file__).resolve().parents[1] / "snap-pair-login.py"
method = next(n for n in ast.parse(source.read_text()).body if isinstance(n, ast.FunctionDef) and n.name == "ready")


class SnapPairStartupTests(unittest.TestCase):
    def run_ready(self, initial):
        clock = [0.0]
        stream = SimpleNamespace(sendall=Mock(), recv=Mock(return_value=b"\x58"))
        context = SimpleNamespace(wrap_socket=Mock(return_value=nullcontext(stream)))
        def connect(*args, **kwargs):
            if clock[0] < 70: raise ConnectionRefusedError()
            return nullcontext(object())
        def advance(seconds): clock[0] += 70
        namespace = {
            "time": SimpleNamespace(monotonic=lambda: clock[0], sleep=advance),
            "ssl": SimpleNamespace(create_default_context=Mock(return_value=context)),
            "socket": SimpleNamespace(create_connection=connect),
        }
        exec(compile(ast.Module(body=[method], type_ignores=[]), str(source), "exec"), namespace)
        proof = namespace["ready"](SimpleNamespace(poll=lambda: None), 7666, "fixture.crt", initial=initial)
        namespace["ssl"].create_default_context.assert_called_once_with(cafile="fixture.crt")
        stream.sendall.assert_called_once_with(b"\x77")
        self.assertEqual(context.wrap_socket.call_args.kwargs["server_hostname"], "localhost")
        return proof

    def test_cold_catalog_start_can_finish_after_a_minute_with_verified_tls(self):
        self.assertEqual(self.run_ready(True), {"elapsed_seconds": 70.0, "budget_seconds": 240, "login_budget_changed": False})

    def test_warm_restart_still_fails_after_one_minute(self):
        with self.assertRaisesRegex(TimeoutError, "no abrió TLS"):
            self.run_ready(False)


if __name__ == "__main__": unittest.main()
