"""La repetición de export no oculta errores de scripts o recursos."""

import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("export_log", Path(__file__).resolve().parents[1] / "check-export-log.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ExportLogTest(unittest.TestCase):
    def test_clean_and_known_initial_cache(self):
        self.assertEqual(module.classify("[ DONE ] savepack\n"), 0)
        self.assertEqual(module.classify(self.known()), 2)

    def test_unrelated_errors_always_fail(self):
        self.assertEqual(module.classify("ERROR: Resource missing\n" + self.known()), 1)
        self.assertEqual(module.classify(self.known() + "SCRIPT ERROR: Invalid script\n"), 1)
        self.assertEqual(module.classify(self.known() + "ERROR: Resource missing\n"), 1)
        self.assertEqual(module.classify(self.known().replace("[ DONE ] savepack", "packing")), 1)

    @staticmethod
    def known():
        return "[ DONE ] savepack\n" + ("ERROR: The Image width specified (0 pixels) must be greater than 0 pixels.\n"
               "   at: initialize_data (core/io/image.cpp:2403)\nERROR: Invalid image: image is empty\n"
               "   at: create_from_image (scene/resources/image_texture.cpp:60)\n") * 3
