"""Measurement trend smoothing — pure functions, no I/O. Documented at
/docs/the-math ('Measurement trend').

Scale readings are noisy (±1 kg of water and glycogen day to day); the
signal is an exponentially-smoothed trend in the Hacker's Diet tradition.
The smoother is time-aware: each new reading pulls the trend toward it by
``1 - 0.9**gap_days``, which collapses to the classic 10% daily step for
daily weigh-ins and takes proportionally bigger steps across gaps, so
weekly weigh-ins behave identically to daily ones.
"""
from datetime import datetime

# Daily carry factor: a reading one day later moves the trend 10% of the way
DAILY_CARRY = 0.9


def smooth(entries: list[tuple[datetime, float]]) -> list[float]:
    """Trend value at each entry. Entries must be chronological."""
    trend: list[float] = []
    for i, (at, value) in enumerate(entries):
        if not trend:
            trend.append(value)
            continue
        gap_days = max((at - entries[i - 1][0]).total_seconds() / 86400, 0.0)
        alpha = 1 - DAILY_CARRY**gap_days
        trend.append(trend[-1] + alpha * (value - trend[-1]))
    return trend


def rate_per_week(
    entries: list[tuple[datetime, float]], trend: list[float], window_days: int = 28
) -> float | None:
    """Least-squares slope of the trend over the last window, in units/week.
    Needs at least two trend points spanning 5+ days inside the window."""
    if not entries:
        return None
    cutoff = entries[-1][0].timestamp() - window_days * 86400
    xs = [e[0].timestamp() / 86400 for e, _t in zip(entries, trend) if e[0].timestamp() >= cutoff]
    ys = [t for e, t in zip(entries, trend) if e[0].timestamp() >= cutoff]
    if len(xs) < 2 or xs[-1] - xs[0] < 5:
        return None
    n = len(xs)
    mean_x = sum(xs) / n
    mean_y = sum(ys) / n
    denom = sum((x - mean_x) ** 2 for x in xs)
    if denom == 0:
        return None
    slope_per_day = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys)) / denom
    return slope_per_day * 7


def change_over(
    entries: list[tuple[datetime, float]], trend: list[float], window_days: int = 28
) -> float | None:
    """Trend now minus the trend at the start of the window (the oldest trend
    point inside it). None until the data spans 5+ days."""
    if len(entries) < 2:
        return None
    cutoff = entries[-1][0].timestamp() - window_days * 86400
    inside = [(e[0], t) for e, t in zip(entries, trend) if e[0].timestamp() >= cutoff]
    if len(inside) < 2:
        return None
    span_days = (inside[-1][0] - inside[0][0]).total_seconds() / 86400
    if span_days < 5:
        return None
    return trend[-1] - inside[0][1]
