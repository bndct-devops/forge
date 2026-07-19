"""A tiny at-a-glance payload for dashboard tiles (gethomepage's customapi
widget and friends): am I on track this week? Works with a read-only token.
Documented at /docs/webhooks-metrics.
"""
from datetime import date, timedelta

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from backend.core.clock import utcnow
from backend.core.database import get_db
from backend.core.security import get_current_user
from backend.models import User, Workout
from backend.serializers import workout_totals

router = APIRouter(prefix="/widget", tags=["widget"])


def _week_start(d: date) -> date:
    return d - timedelta(days=d.weekday())


@router.get("")
def widget(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    workouts = (
        db.execute(
            select(Workout)
            .where(Workout.owner_id == user.id, Workout.finished_at.is_not(None))
            .order_by(Workout.started_at.desc())
        )
        .scalars()
        .all()
    )
    today = utcnow().date()
    this_week = _week_start(today)

    trained_weeks = {_week_start(w.started_at.date()) for w in workouts}
    streak = 0
    cursor = this_week if this_week in trained_weeks else this_week - timedelta(weeks=1)
    while cursor in trained_weeks:
        streak += 1
        cursor -= timedelta(weeks=1)

    week_workouts = [w for w in workouts if _week_start(w.started_at.date()) == this_week]
    week_volume = sum(workout_totals(w)["total_volume"] for w in week_workouts)

    last = workouts[0] if workouts else None
    days_since = (today - last.started_at.date()).days if last else None

    return {
        "streak_weeks": streak,
        "week_workouts": len(week_workouts),
        "weekly_goal": user.weekly_goal,
        "week_progress": f"{len(week_workouts)}/{user.weekly_goal}",
        "week_volume": round(week_volume, 1),
        "unit": user.unit,
        "last_workout_at": last.started_at.isoformat() + "Z" if last else None,
        "days_since_last": days_since,
        "last_workout": (
            "today" if days_since == 0
            else "yesterday" if days_since == 1
            else f"{days_since} days ago" if days_since is not None
            else "never"
        ),
    }
