"""Prometheus text exposition for the authenticated user — point a scrape
job at /api/metrics with a read-only API token as the bearer credential."""
from datetime import timezone

from fastapi import APIRouter, Depends
from fastapi.responses import PlainTextResponse
from sqlalchemy.orm import Session

from backend.api.stats import stats as compute_stats
from backend.core.database import get_db
from backend.core.security import get_current_user
from backend.models import User

router = APIRouter(tags=["metrics"])


@router.get("/metrics", response_class=PlainTextResponse)
def metrics(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    data = compute_stats(user=user, db=db)
    totals = data["totals"]
    week = data["weeks"][-1] if data["weeks"] else {"workouts": 0, "volume": 0}
    label = f'{{user="{user.username}"}}'

    lines = [
        "# HELP forge_workouts_total Finished workouts, lifetime.",
        "# TYPE forge_workouts_total counter",
        f"forge_workouts_total{label} {totals['workouts']}",
        "# HELP forge_sets_total Completed working sets, lifetime.",
        "# TYPE forge_sets_total counter",
        f"forge_sets_total{label} {totals['sets']}",
        "# HELP forge_volume_kg_total Lifted volume in the user's unit, lifetime.",
        "# TYPE forge_volume_kg_total counter",
        f"forge_volume_kg_total{label} {totals['volume']}",
        "# HELP forge_prs_total Personal records, lifetime.",
        "# TYPE forge_prs_total counter",
        f"forge_prs_total{label} {totals['prs']}",
        "# HELP forge_streak_weeks Current consecutive training-week streak.",
        "# TYPE forge_streak_weeks gauge",
        f"forge_streak_weeks{label} {data['streak_weeks']}",
        "# HELP forge_week_workouts Workouts in the current week.",
        "# TYPE forge_week_workouts gauge",
        f"forge_week_workouts{label} {week['workouts']}",
        "# HELP forge_week_volume Volume in the current week.",
        "# TYPE forge_week_volume gauge",
        f"forge_week_volume{label} {week['volume']}",
        "# HELP forge_weekly_goal Configured weekly workout goal.",
        "# TYPE forge_weekly_goal gauge",
        f"forge_weekly_goal{label} {user.weekly_goal}",
    ]

    last = max((d for d in data["calendar"] if d["workouts"] > 0), default=None, key=lambda d: d["date"])
    if last is not None:
        from datetime import datetime

        ts = datetime.fromisoformat(last["date"]).replace(tzinfo=timezone.utc).timestamp()
        lines += [
            "# HELP forge_last_workout_timestamp_seconds Date of the most recent workout (midnight UTC).",
            "# TYPE forge_last_workout_timestamp_seconds gauge",
            f"forge_last_workout_timestamp_seconds{label} {int(ts)}",
        ]
    return "\n".join(lines) + "\n"
