"""Pure snapshot checks shared by the native runner and isolated tool tests."""

FIELDS = ("deaths", "player_kills", "citizen_kills", "criminal_kills", "npc_kills")
LABELS = dict(
    zip(
        FIELDS,
        (
            "Muertes propias",
            "Usuarios Matados",
            "Ciudadanos Matados",
            "Criminales Matados",
            "NPCs Matados",
        ),
    )
)


def ministats_match(view, expected, jail_days=None):
    values = view.get("ministats", {})
    return all(
        values.get(name) == str(expected[key]) for key, name in LABELS.items()
    ) and (jail_days is None or values.get("Cárcel: días restantes") == str(jail_days))
