"""Aceptación estricta de la campaña completa, independiente del motor y Redis."""

from r10_world import acceptance as r10_acceptance

FULL_REQUIRED = {
    "full-thief",
    "full-navigation",
    "full-sea-exit",
    "full-fishing-zones",
    "full-mana",
    "full-pvp",
    "full-ui",
    "spells-a-to-b",
    "spells-b-to-a",
    "full-reconnect",
    "full-benchmark",
}


def acceptance(steps, seconds, **kwargs):
    base = r10_acceptance(steps, seconds, **kwargs)
    completed = {s["id"] for s in steps if s.get("passed") is True}
    skills = {
        s["observations"]["skill"]
        for s in steps
        if s.get("passed") is True
        and s.get("id", "").startswith("skill-")
        and type(s.get("observations", {}).get("skill")) is int
    }
    missing = sorted(FULL_REQUIRED - completed)
    passed = base["functional_passed"] and not missing and skills == set(range(1, 23))
    return {
        **base,
        "kind": "Campaña completa de dos clientes gráficos",
        "test_execution_passed": passed,
        "functional_passed": passed,
        "full_missing": missing,
        "skills": sorted(skills),
        "r10_gameplay_passed": passed and base["r10_gameplay_passed"],
    }
