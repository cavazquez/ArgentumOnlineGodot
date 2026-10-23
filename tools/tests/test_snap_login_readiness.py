"""No introducir credenciales mientras el export todavía muestra el logo de Godot."""
import ast
from pathlib import Path
import unittest

source = Path(__file__).resolve().parents[1] / "snap-ui-smoke.py"
method = next(node for node in ast.parse(source.read_text()).body
              if isinstance(node, ast.FunctionDef) and node.name == "login_visible")
namespace = {}
exec(compile(ast.Module(body=[method], type_ignores=[]), str(source), "exec"), namespace)


class Screen:
    def __init__(self, background, labels=True):
        self.background = background
        self.labels = labels

    def convert(self, mode):
        return self

    def getpixel(self, point):
        return (self.background,) * 3

    def crop(self, box):
        return self

    def getcolors(self, limit):
        return [(100, 220 if self.labels else 0)]


class LoginReadinessTests(unittest.TestCase):
    def test_godot_splash_with_white_letters_is_not_the_form(self):
        self.assertFalse(namespace["login_visible"](Screen(35)))

    def test_empty_or_incomplete_window_does_not_accept_input(self):
        self.assertFalse(namespace["login_visible"](Screen(0)))
        self.assertFalse(namespace["login_visible"](Screen(20, labels=False)))

    def test_form_requires_dark_fields_and_visible_labels(self):
        self.assertTrue(namespace["login_visible"](Screen(20)))
