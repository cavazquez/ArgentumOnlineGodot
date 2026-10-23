"""Regression: R10 leaves slot 22 equipped before testing the installed Snap."""
import importlib.util
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[1] / "snap_ui_layout.py"
spec = importlib.util.spec_from_file_location("snap_ui_layout", path)
layout = importlib.util.module_from_spec(spec)
spec.loader.exec_module(layout)


class CompactBackpackTests(unittest.TestCase):
    def test_default_slots_retain_the_original_mouse_targets(self):
        self.assertEqual(layout.inventory_cell(1), (616, 180))
        self.assertEqual(layout.inventory_cell(30), (744, 340))

    def test_equipped_slot_22_moves_the_apple_to_the_previous_cell(self):
        hidden = layout.hidden_equipped_slots({"weapon": "22"}, {"slot_22": "563:1", "slot_30": "1:10"})
        self.assertEqual(hidden, [22])
        self.assertEqual(layout.inventory_cell(30, hidden), (712, 340))
        self.assertEqual(layout.inventory_cell(1, hidden), (616, 180))

    def test_multiple_equipment_layers_compact_across_a_grid_row(self):
        self.assertEqual(layout.inventory_cell(30, [2, 4, 7, 11, 19, 22]), (712, 324))
        self.assertEqual(layout.inventory_cell(8, [2, 4, 7, 11, 19, 22]), (744, 196))

    def test_five_equipped_items_also_recenter_the_shorter_grid(self):
        self.assertEqual(layout.inventory_cell(30, [2, 4, 7, 11, 19]), (744, 324))

    def test_probe_and_mouse_stay_inside_cells_measured_in_godot(self):
        # Measured using the authored scene in Godot 4.7.2: the grid's
        # global top is 161 with six rows and 177 with five rows. Its
        # GROW_DIRECTION_BOTH preserves the vertical center at y=257.
        for count, grid_top in enumerate((161, 161, 161, 161, 161, 177, 177)):
            hidden = [2, 4, 7, 11, 19, 22][:count]
            visible = [slot for slot in range(1, 31) if slot not in hidden]
            for index, slot in enumerate(visible):
                x, y = layout.inventory_cell(slot, hidden)
                left, top = 600 + (index % 5) * 32, grid_top + (index // 5) * 32
                with self.subTest(equipped=count, slot=slot):
                    self.assertGreaterEqual(x - 14, left)
                    self.assertLessEqual(x + 14, left + 32)
                    self.assertGreaterEqual(y - 14, top)
                    self.assertLessEqual(y + 10, top + 32)

    def test_logical_order_does_not_depend_on_equipment_field_order(self):
        self.assertEqual(layout.inventory_cell(30, [22, 2, 22]), layout.inventory_cell(30, [2, 22]))

    def test_empty_or_unequipped_slots_do_not_shift_the_grid(self):
        self.assertEqual(layout.hidden_equipped_slots({"weapon": "0", "helmet": "12"}, {}), [])

    def test_hidden_source_or_destination_is_rejected_before_typing(self):
        for slot in (1, 30):
            with self.assertRaises(ValueError):
                layout.inventory_cell(slot, [slot])

    def test_invalid_slot_numbers_are_rejected(self):
        for slot in (0, 31):
            with self.assertRaises(ValueError):
                layout.inventory_cell(slot)
            with self.assertRaises(ValueError):
                layout.inventory_cell(30, [slot])
