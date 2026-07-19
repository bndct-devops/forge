"""Periodization schemes — pure functions, no I/O, documented at
/docs/the-math ('Programs') on the docs site. A scheme maps (week,
training max) to a list of prescribed sets; everything else (state,
advancement) lives in the programs API.

Percentages apply to the *training max* (TM), not a true 1RM. The
conventional TM is ~90% of your best estimated 1RM — the create-program
flow suggests exactly that.
"""

# Each week: list of (percent of TM, target reps, amrap) tuples.
SCHEMES: dict[str, dict] = {
    "531": {
        "name": "5/3/1",
        "description": "Wendler-style four-week wave: 5s, 3s, 5/3/1, deload. Last working set of weeks 1–3 is AMRAP (as many reps as possible, quality reps only).",
        "weeks": [
            [(0.65, 5, False), (0.75, 5, False), (0.85, 5, True)],
            [(0.70, 3, False), (0.80, 3, False), (0.90, 3, True)],
            [(0.75, 5, False), (0.85, 3, False), (0.95, 1, True)],
            [(0.40, 5, False), (0.50, 5, False), (0.60, 5, False)],  # deload
        ],
    },
    "linear": {
        "name": "Linear block",
        "description": "Four-week volume-to-intensity block: 3×10 @ 70%, 3×8 @ 75%, 3×6 @ 80%, 3×4 @ 85%, then the training max goes up and the block repeats.",
        "weeks": [
            [(0.70, 10, False)] * 3,
            [(0.75, 8, False)] * 3,
            [(0.80, 6, False)] * 3,
            [(0.85, 4, False)] * 3,
        ],
    },
}


def cycle_length(scheme: str) -> int:
    return len(SCHEMES[scheme]["weeks"])


def round_to_step(weight: float, step: float) -> float:
    if step <= 0:
        return round(weight, 1)
    return round(round(weight / step) * step, 2)


def prescription(scheme: str, week: int, training_max: float, step: float = 2.5) -> list[dict]:
    """Prescribed sets for a 1-based week of the cycle. Weights round to the
    plate step; a prescription never rounds below one step."""
    weeks = SCHEMES[scheme]["weeks"]
    plan = weeks[(week - 1) % len(weeks)]
    return [
        {
            "pct": pct,
            "weight": max(step, round_to_step(training_max * pct, step)),
            "reps": reps,
            "amrap": amrap,
        }
        for pct, reps, amrap in plan
    ]
