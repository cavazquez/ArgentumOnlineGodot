"""Las fuentes vacías no pueden volver a las escenas generadas."""

from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from map_atlases import repair


class MapAtlasTests(unittest.TestCase):
    def test_all_maps_have_tiles_in_each_declared_atlas(self):
        maps = Path(__file__).resolve().parents[2] / "Maps"
        paths = list(maps.glob("Map*.tscn"))
        self.assertEqual(len(paths), 290)
        for path in paths:
            text = path.read_text(encoding="utf-8")
            corrected, removed = repair(text)
            self.assertEqual(removed, [], path.name)
            self.assertEqual(corrected, text)

    def test_removes_only_empty_atlas_and_its_reference(self):
        text = ('[gd_scene load_steps=5 format=4]\n\n'
                '[sub_resource type="TileSetAtlasSource" id="empty"]\ntexture = ExtResource("small")\n'
                '[sub_resource type="TileSetAtlasSource" id="full"]\ntexture = ExtResource("full")\n0:0/0 = 0\n'
                '[sub_resource type="TileSet" id="set"]\nsources/8081 = SubResource("empty")\nsources/7 = SubResource("full")\n'
                '[node name="Sprite" type="Sprite2D"]\ntexture = ExtResource("small")\n')
        corrected, removed = repair(text)
        self.assertEqual(removed, ["empty"])
        self.assertIn("load_steps=4", corrected)
        self.assertIn('sources/7 = SubResource("full")', corrected)
        self.assertIn('[node name="Sprite" type="Sprite2D"]\ntexture = ExtResource("small")', corrected)
        self.assertNotIn('SubResource("empty")', corrected)
        self.assertEqual(repair(corrected), (corrected, []))

    def test_refuses_removing_a_source_referenced_outside_tileset(self):
        text = ('[sub_resource type="TileSetAtlasSource" id="empty"]\n'
                '[node name="Other"]\ncustom = SubResource("empty")\n')
        with self.assertRaises(ValueError):
            repair(text)
