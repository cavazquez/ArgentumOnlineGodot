"""Aserciones de efectos sobre snapshots independientes de los servicios de juego."""


def player(row, section, index):
    values = row.get(section, {})
    return values.get(index, values.get(str(index), {}))


def check_effects(row, spell):
    """Un ACK y un FX no acreditan por sí solos que cambió el estado del objetivo."""
    failures = []
    before, after = (
        player(row, section, 2) for section in ("state_before", "state_after")
    )
    source_before, source_after = (
        player(row, section, 1) for section in ("state_before", "state_after")
    )
    if not row["cast_confirmed"]:
        if source_before.get("min_mana") != source_after.get("min_mana"):
            failures.append("rechazo con consumo de maná")
        return failures
    hp_before, hp_after = (int(value.get("min_hp", 0)) for value in (before, after))
    if spell.get("heals_hp") and hp_after <= hp_before:
        failures.append("curación sin aumento de HP")
    if spell.get("revives") and hp_after <= 0:
        failures.append("resurrección sin HP")
    damaging = any(int(spell.get(key, 0)) > 0 for key in ("min_damage", "max_damage"))
    if damaging and not any(
        spell.get(key) for key in ("heals_hp", "revives", "invokes")
    ):
        if hp_after >= hp_before:
            failures.append("ataque mágico sin daño")
    if spell["id"] == 45 and int(source_after["min_hp"]) <= int(
        source_before["min_hp"]
    ):
        failures.append("drenaje sin recuperar HP del lanzador")
    now = row["captured_at"]
    for flag, field in (
        ("poisons", "poisoned_until"),
        ("paralyzes", "immobilized_until"),
        ("immobilizes", "immobilized_until"),
        ("dumbs", "dumb_until"),
        ("makes_invisible", "invisible_until"),
    ):
        if spell.get(flag) and float(after.get(field, 0)) <= now:
            failures.append(flag + " sin estado persistido")
    for flag, field in (
        ("cures_poison", "poisoned_until"),
        ("removes_paralysis", "immobilized_until"),
        ("removes_stupidity", "dumb_until"),
    ):
        if spell.get(flag) and float(after.get(field, 0)) != 0:
            failures.append(flag + " sin limpiar el estado")
    for attribute in ("strength", "agility"):
        positive, negative = (
            spell.get(prefix + attribute) for prefix in ("increases_", "decreases_")
        )
        if not (positive or negative):
            continue
        attrs_before, attrs_after = (
            player(row, section, 2)
            for section in ("attributes_before", "attributes_after")
        )
        value = int(attrs_after.get(attribute + "_modifier_value", 0))
        if (value <= 0 if positive else value >= 0) or float(
            attrs_after.get(attribute + "_modifier_until", 0)
        ) <= now:
            failures.append(attribute + " sin modificador temporal correcto")
        if attrs_before.get(attribute) != attrs_after.get(attribute):
            failures.append(attribute + " base alterado permanentemente")
    if spell["id"] in (12, 13):
        needs_before, needs_after = (
            player(row, section, 2) for section in ("needs_before", "needs_after")
        )
        expected = max(
            0, int(needs_before["min_hunger"]) - (50 if spell["id"] == 12 else 100)
        )
        if int(needs_after["min_hunger"]) > expected:
            failures.append("hambre sin reducción efectiva")
    if (
        spell.get("morphs")
        and player(row, "after_views", 1)["appearance"]
        != player(row, "before_views", 2)["appearance"]
    ):
        failures.append("mimetismo sin copiar apariencia")
    if (spell.get("invokes") or spell.get("warps_pet")) and not row.get("pets"):
        failures.append("invocación sin mascota persistida")
    return failures
