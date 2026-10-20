"""Un icono o un tipo de mueble no acreditan una animación de equipo."""

from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from equipment_catalog_audit import audit
from equipment_world import rendered_as


class EquipmentEvidenceTests(unittest.TestCase):
    def test_icon_and_boots_ropaje_do_not_hide_missing_avatar_art(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            (root / "data/items").mkdir(parents=True)
            (root / "data/items/sample.toml").write_text('[[item]]\nid=1\nName="Red"\nObjType=2\nGrhIndex=844\n\n[[item]]\nid=2\nName="Botas"\nObjType=20\nNumRopaje=1\n')
            report = audit(root, root)
            self.assertFalse(report["complete_avatar_coverage"])
            self.assertEqual(report["missing_resources"][0]["animation"], 0)
            self.assertEqual(report["unsupported_equipment"][0]["item_id"], 2)

    def test_placeholder_or_hidden_sprite_does_not_prove_equipment(self):
        layer = {"id": 12, "visible": True, "frame_count": 1, "resource": "res://placeholder.tres"}
        view = {"actor_equipment": {"7": {"weapon": layer}}}
        self.assertFalse(rendered_as(view, 7, {"weapon": 12}))
        layer["resource"] = "res://Resources/Character/Weapons/weapon_12.tres"
        self.assertTrue(rendered_as(view, 7, {"weapon": 12}))
        layer["visible"] = False
        self.assertFalse(rendered_as(view, 7, {"weapon": 12}))


if __name__ == "__main__": unittest.main()
