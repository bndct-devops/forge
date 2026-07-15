"""Training statistics: totals, weekly streak, calendar, volume trend,
muscle-group split. Warm-up sets never count (same rule as workout totals)."""
from collections import defaultdict
from datetime import date, timedelta

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from backend.core.clock import utcnow
from backend.core.database import get_db
from backend.core.security import get_current_user
from backend.models import Exercise, User, Workout
from backend.serializers import workout_totals

router = APIRouter(prefix="/stats", tags=["stats"])

CALENDAR_DAYS = 140  # 20 weeks
TREND_WEEKS = 12
SPLIT_DAYS = 30


def _week_start(d: date) -> date:
    return d - timedelta(days=d.weekday())


@router.get("")
def stats(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    workouts = (
        db.execute(
            select(Workout)
            .where(Workout.owner_id == user.id, Workout.finished_at.is_not(None))
            .order_by(Workout.started_at)
        )
        .scalars()
        .all()
    )
    exercises = {e.id: e for e in db.execute(select(Exercise)).scalars()}

    today = utcnow().date()
    total_volume = 0.0
    total_sets = 0
    total_prs = 0
    by_day: dict[str, int] = defaultdict(int)
    volume_by_week: dict[date, float] = defaultdict(float)
    workouts_by_week: dict[date, int] = defaultdict(int)
    trained_weeks: set[date] = set()
    split: dict[str, int] = defaultdict(int)
    split_since = today - timedelta(days=SPLIT_DAYS)

    for w in workouts:
        totals = workout_totals(w)
        total_volume += totals["total_volume"]
        total_sets += totals["total_sets"]
        total_prs += totals["pr_count"]

        day = w.started_at.date()
        by_day[day.isoformat()] += 1
        week = _week_start(day)
        trained_weeks.add(week)
        volume_by_week[week] += totals["total_volume"]
        workouts_by_week[week] += 1

        if day >= split_since:
            for we in w.exercises:
                exercise = exercises.get(we.exercise_id)
                if exercise is None:
                    continue
                working_sets = sum(1 for s in we.sets if s.is_completed and not s.is_warmup)
                split[exercise.muscle_group] += working_sets

    # Streak: consecutive trained weeks ending at the current week — or the
    # previous one, so the streak isn't "broken" before this week's session
    this_week = _week_start(today)
    streak = 0
    cursor = this_week if this_week in trained_weeks else this_week - timedelta(weeks=1)
    while cursor in trained_weeks:
        streak += 1
        cursor -= timedelta(weeks=1)

    calendar_start = today - timedelta(days=CALENDAR_DAYS - 1)
    calendar = [
        {"date": (calendar_start + timedelta(days=i)).isoformat(),
         "workouts": by_day.get((calendar_start + timedelta(days=i)).isoformat(), 0)}
        for i in range(CALENDAR_DAYS)
    ]

    weeks = []
    for i in range(TREND_WEEKS - 1, -1, -1):
        week = this_week - timedelta(weeks=i)
        weeks.append(
            {
                "week_start": week.isoformat(),
                "volume": round(volume_by_week.get(week, 0.0), 1),
                "workouts": workouts_by_week.get(week, 0),
            }
        )

    return {
        "totals": {
            "workouts": len(workouts),
            "volume": round(total_volume, 1),
            "sets": total_sets,
            "prs": total_prs,
            "since": workouts[0].started_at if workouts else None,
        },
        "streak_weeks": streak,
        "calendar": calendar,
        "weeks": weeks,
        "muscle_groups": sorted(
            ({"group": g, "sets": n} for g, n in split.items() if n > 0),
            key=lambda x: -x["sets"],
        ),
        "split_days": SPLIT_DAYS,
    }
