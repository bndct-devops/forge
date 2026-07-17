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
from backend.models import Exercise, SetEntry, User, Workout, WorkoutExercise
from backend.serializers import epley_1rm, workout_totals

router = APIRouter(prefix="/stats", tags=["stats"])

CALENDAR_DAYS = 140  # 20 weeks
MUSCLE_TREND_WEEKS = 8
TREND_WEEKS = 12
SPLIT_DAYS = 30


def _week_start(d: date) -> date:
    return d - timedelta(days=d.weekday())


@router.get("/records")
def records(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """All-time bests per exercise, across everything ever logged."""
    rows = db.execute(
        select(SetEntry, Workout, WorkoutExercise.exercise_id)
        .join(WorkoutExercise, SetEntry.workout_exercise_id == WorkoutExercise.id)
        .join(Workout, WorkoutExercise.workout_id == Workout.id)
        .where(
            Workout.owner_id == user.id,
            Workout.finished_at.is_not(None),
            SetEntry.is_completed.is_(True),
            SetEntry.is_warmup.is_(False),
            SetEntry.reps.is_not(None),
        )
    ).all()
    exercises = {e.id: e for e in db.execute(select(Exercise)).scalars()}
    best: dict[int, dict] = {}
    for se, w, ex_id in rows:
        weight = se.weight or 0.0
        entry = best.setdefault(
            ex_id,
            {"best_weight": None, "best_1rm": None, "best_reps": None, "sessions": set()},
        )
        entry["sessions"].add(w.id)
        if weight > 0:
            if entry["best_weight"] is None or weight > entry["best_weight"]["weight"]:
                entry["best_weight"] = {"weight": weight, "reps": se.reps, "date": w.started_at}
            one_rm = round(epley_1rm(weight, se.reps), 1)
            if entry["best_1rm"] is None or one_rm > entry["best_1rm"]["value"]:
                entry["best_1rm"] = {"value": one_rm, "date": w.started_at}
        elif entry["best_reps"] is None or se.reps > entry["best_reps"]["reps"]:
            entry["best_reps"] = {"reps": se.reps, "date": w.started_at}
    result = []
    for ex_id, entry in best.items():
        exercise = exercises.get(ex_id)
        if exercise is None:
            continue
        result.append(
            {
                "exercise_id": ex_id,
                "name": exercise.name,
                "muscle_group": exercise.muscle_group,
                "best_weight": entry["best_weight"],
                "best_1rm": entry["best_1rm"],
                "best_reps": entry["best_reps"],
                "sessions": len(entry["sessions"]),
            }
        )
    result.sort(key=lambda r: r["name"].lower())
    return result


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
    last_by_group: dict[str, date] = {}
    muscle_weeks: dict[str, dict] = defaultdict(lambda: defaultdict(int))
    trend_since = _week_start(today) - timedelta(weeks=MUSCLE_TREND_WEEKS - 1)

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

        for we in w.exercises:
            exercise = exercises.get(we.exercise_id)
            if exercise is None:
                continue
            working_sets = sum(1 for s in we.sets if s.is_completed and not s.is_warmup)
            if working_sets == 0:
                continue
            prev = last_by_group.get(exercise.muscle_group)
            if prev is None or day > prev:
                last_by_group[exercise.muscle_group] = day
            if day >= split_since:
                split[exercise.muscle_group] += working_sets
            if week >= trend_since:
                muscle_weeks[exercise.muscle_group][week] += working_sets

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

    # Gap nudges: groups in the user's actual rotation (trained in the last
    # 60 days) that have gone quiet for 9+ days. Silent when the user hasn't
    # trained at all recently — the streak UI covers absence.
    nudges = []
    if user.gap_nudges and last_by_group:
        most_recent = max(last_by_group.values())
        if (today - most_recent).days <= 14:
            for group, last in last_by_group.items():
                days = (today - last).days
                if 9 <= days and last >= today - timedelta(days=60):
                    nudges.append({"group": group, "days": days})
            nudges.sort(key=lambda n: -n["days"])
            nudges = nudges[:2]

    return {
        "nudges": nudges,
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
        "muscle_trend": {
            group: [
                {
                    "week_start": (this_week - timedelta(weeks=i)).isoformat(),
                    "sets": weeks_map.get(this_week - timedelta(weeks=i), 0),
                }
                for i in range(MUSCLE_TREND_WEEKS - 1, -1, -1)
            ]
            for group, weeks_map in muscle_weeks.items()
        },
        "muscle_groups": sorted(
            ({"group": g, "sets": n} for g, n in split.items() if n > 0),
            key=lambda x: -x["sets"],
        ),
        "split_days": SPLIT_DAYS,
    }
