"""Coordinates for logical inventory slots in the real compact backpack."""


def hidden_equipped_slots(equipment, inventory):
    """Return occupied logical slots hidden by the equipment panel."""
    slots = set()
    for value in equipment.values():
        slot = int(value)
        if 1 <= slot <= 30 and inventory.get(f"slot_{slot}"):
            slots.add(slot)
    return sorted(slots)


def inventory_cell(slot, hidden_slots=()):
    """Locate a displayed logical slot in the 800x600, five-column HUD."""
    hidden = set(hidden_slots)
    if not 1 <= slot <= 30 or any(not 1 <= value <= 30 for value in hidden):
        raise ValueError("Inventory slots must be between 1 and 30")
    if slot in hidden:
        raise ValueError("Equipped items are absent from the backpack")
    visible_index = slot - 1 - sum(value < slot for value in hidden)
    return (616 + 32 * (visible_index % 5), 180 + 32 * (visible_index // 5))
