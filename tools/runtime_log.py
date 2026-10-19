"""Keep known engine diagnostics visible without accepting unrelated errors."""

import collections
import re


TOOLTIP_ISSUE = "https://github.com/godotengine/godot/issues/89657"
_ENGINE = "Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org"
_TOOLTIP = re.compile(
    r"Attempt to disconnect a nonexistent connection from 'root:<Window#(\d+)>'\. "
    r"Signal: '(focus_entered|tree_exited)', callable: ''\."
)


def classify_runtime_log(text: str) -> dict:
    """Allow only complete pairs from the pinned release engine; never hide logs.

    Godot #89657 is a release-template Callable hash bug on tooltip teardown.
    It is still present in 4.7.2. Remove this version-specific classification
    once the pinned stable templates contain the upstream fix (#123998).
    """
    unexpected = re.findall(r"^\s*SCRIPT ERROR:.*$", text, re.MULTILINE)
    messages = [message.strip() for message in re.findall(r"^\s*ERROR:(.*)$", text, re.MULTILINE)]
    candidates = []
    for message in messages:
        match = _TOOLTIP.fullmatch(message)
        if _ENGINE in text.splitlines() and match:
            candidates.append((match.group(1), match.group(2), message))
        else:
            unexpected.append(message)
    pairs = collections.Counter((window, signal) for window, signal, _ in candidates)
    complete = all(pairs[(window, "focus_entered")] == pairs[(window, "tree_exited")]
                   for window, _, _ in candidates)
    if not complete:
        unexpected.extend(message for _, _, message in candidates)
        candidates = []
    return {
        "passed": not unexpected,
        "unexpected_errors": unexpected,
        "known_engine_diagnostics": [
            {"issue": TOOLTIP_ISSUE, "message": message} for _, _, message in candidates
        ],
    }
