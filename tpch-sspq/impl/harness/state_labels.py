#!/usr/bin/env python3.11
"""Fail-closed guard against state-dependent prose that misstates the state.

WHY THIS FILE EXISTS
--------------------
Nine separate instances of one defect were found across ten boundary-cohort
generations, always the same shape and always just outside whichever delta was under
review: a sentence, heading or JSON field asserting something about a state that can
change, written for one state and not conditioned on it. Examples that actually
shipped and had to be corrected: "the chosen combination rule" while the rule was
undecided; "must be flagged UNPROVABLE_ON_THIS_HOST" while every such determination
was withheld; a note hardcoded for the escalated state that would be false the moment
a rule was chosen; `"applied": True` sitting two keys away from `"STOP_AND_REPORT":
true`.

Patching the tenth instance would not stop an eleventh. Review is the wrong control
for this: a reviewer has to notice absence-of-conditioning in prose, which is exactly
what nine reviews failed at. So the control moves into the generators. Each generator
declares, for the state it is in, which phrases MUST NOT appear in what it just
produced, and refuses to emit output that contains one. A future contributor who adds
"the applied factor" to an escalated-state artifact gets a hard failure instead of a
reviewer's maybe.

THE STATE
---------
`escalated` is true when IMPL-SSOT section 6-d-1's combination rule is undecided
(`combination.rule == "USER_DECISION_REQUIRED"`). While escalated the campaign has
chosen no factor, so nothing may be described as applied, chosen or final, and no
`UNPROVABLE_ON_THIS_HOST` verdict may be asserted for a query whose MDE depends on the
factor. Once a rule is chosen the opposite holds: nothing may be described as
provisional, illustrative or withheld.

THE ONE EXCEPTION, WHICH IS NOT A LOOPHOLE
------------------------------------------
Q01-Q06 use their DIRECTLY MEASURED restart-regime paired CV (section 6-d-1 step 6).
No combination rule enters their MDE, so their verdicts are asserted in both states and
the pending decision cannot move them. Text that names that exception explicitly is
therefore allowed to speak of asserted verdicts while escalated — which is why the
forbidden lists below target the phrases that claim a factor was applied or that a
determination was made *because of* a factor, not the word "asserted" itself.
"""

# Phrases that must NOT appear in an artifact produced while the rule is UNDECIDED.
# Each one asserts that a factor was selected, applied, or made final.
FORBIDDEN_WHEN_ESCALATED = (
    "chosen combination rule",
    "the chosen rule",
    "uses the chosen",
    "the applied rule",
    "the applied factor",
    "corrected MDE is final",
    "MDE is final",
    "may become provable",
    "errs toward flagging",
    "must be flagged `UNPROVABLE_ON_THIS_HOST`",
    "must be flagged UNPROVABLE_ON_THIS_HOST",
    "CANNOT be proven on this host",
    "No factor was chosen here",
    "Corrected MDE (applied)",
    '"applied": true',
)

# Phrases that must NOT appear once a rule HAS been chosen. Each one asserts that the
# decision is still open.
FORBIDDEN_WHEN_SETTLED = (
    "USER_DECISION_REQUIRED",
    "WITHHELD",
    "withheld_pending_user_factor_decision",
    "ILLUSTRATIVE ONLY",
    "illustrative, no rule applied",
    "provisional for factor-dependent queries",
    "NO combination rule has been chosen",
    "no rule is chosen",
    "pending the section 6-d-1 rule decision",
    "ONCE THE RULE IS CHOSEN:",
)


class StateLabelViolation(SystemExit):
    """Raised instead of emitting an artifact that misstates its own state."""


def _string_values(obj):
    """Every string VALUE in a JSON document, excluding key names.

    Key names are part of the schema, not prose, and a permanent key can legitimately
    collide with a forbidden phrase: `user_decision_required` is emitted unconditionally
    (its VALUE is the state-dependent part, None once a rule is chosen) while
    FORBIDDEN_WHEN_SETTLED contains "USER_DECISION_REQUIRED". Checking the serialized
    document would therefore have failed a correct settled-rule run on its own schema.
    Values are what make claims; keys are not.
    """
    if isinstance(obj, str):
        yield obj
    elif isinstance(obj, dict):
        for v in obj.values():
            yield from _string_values(v)
    elif isinstance(obj, list):
        for v in obj:
            yield from _string_values(v)


def check_json(obj, escalated, what):
    """Guard a JSON document by inspecting its string VALUES only (see _string_values)."""
    check("\n".join(_string_values(obj)), escalated, what)
    return obj


def check(text, escalated, what):
    """Refuse to emit `text` if it contains a phrase forbidden in this state.

    `escalated` must be the real state, read from the calibration document rather than
    passed in by hand, so the check cannot be satisfied by lying about the state.
    """
    forbidden = FORBIDDEN_WHEN_ESCALATED if escalated else FORBIDDEN_WHEN_SETTLED
    lowered = text.lower()
    hits = [p for p in forbidden if p.lower() in lowered]
    if hits:
        state = "ESCALATED (no combination rule chosen)" if escalated \
            else "SETTLED (a combination rule is in force)"
        raise StateLabelViolation(
            f"state-label violation in {what}: state is {state}, but the output contains "
            f"{len(hits)} phrase(s) that contradict it: {hits!r}. "
            "Condition the wording on the state instead of hardcoding it — see "
            "harness/state_labels.py for why this is a hard failure rather than a review note."
        )
    return text


def escalated_from_calibration(calib):
    """The single source of truth for the state. Never infer it any other way."""
    return bool(calib.get("STOP_AND_REPORT")) or \
        (calib.get("combination") or {}).get("rule") == "USER_DECISION_REQUIRED"


def escalated_from_baseline(baseline):
    corr = baseline.get("restart_variance_correction") or {}
    rule = (corr.get("combination_rule") or {}).get("rule")
    return rule == "USER_DECISION_REQUIRED"
