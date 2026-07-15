from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from backend.core.database import get_db
from backend.core.security import get_current_user
from backend.models import Exercise, User, Workout
from backend.schemas import ExerciseCreate, ExerciseOut
from backend.serializers import completed_sets_query, epley_1rm

router = APIRouter(prefix="/exercises", tags=["exercises"])


def _visible(user_id: int):
    return or_(Exercise.owner_id.is_(None), Exercise.owner_id == user_id)


@router.get("", response_model=list[ExerciseOut])
def list_exercises(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    rows = db.execute(
        select(Exercise).where(_visible(user.id)).order_by(Exercise.name)
    ).scalars()
    return [
        ExerciseOut(
            id=e.id,
            name=e.name,
            muscle_group=e.muscle_group,
            equipment=e.equipment,
            is_custom=e.owner_id is not None,
        )
        for e in rows
    ]


@router.post("", response_model=ExerciseOut)
def create_exercise(
    body: ExerciseCreate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    name = body.name.strip()
    exists = db.execute(
        select(Exercise).where(_visible(user.id), Exercise.name == name)
    ).scalar_one_or_none()
    if exists:
        raise HTTPException(status_code=400, detail="An exercise with that name already exists")
    exercise = Exercise(
        name=name,
        muscle_group=body.muscle_group,
        equipment=body.equipment,
        owner_id=user.id,
    )
    db.add(exercise)
    db.commit()
    return ExerciseOut(
        id=exercise.id,
        name=exercise.name,
        muscle_group=exercise.muscle_group,
        equipment=exercise.equipment,
        is_custom=True,
    )


@router.get("/{exercise_id}/stats")
def exercise_stats(
    exercise_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    exercise = db.execute(
        select(Exercise).where(Exercise.id == exercise_id, _visible(user.id))
    ).scalar_one_or_none()
    if exercise is None:
        raise HTTPException(status_code=404, detail="Exercise not found")

    rows = db.execute(
        completed_sets_query(user.id, exercise_id).order_by(Workout.started_at)
    ).all()

    best_weight = None
    best_1rm = None
    best_volume_set = None
    total_reps = 0
    total_volume = 0.0

    # Per-workout aggregation for history + chart
    by_workout: dict[int, dict] = {}
    for set_entry, workout in rows:
        one_rm = epley_1rm(set_entry.weight, set_entry.reps)
        set_volume = set_entry.weight * set_entry.reps
        total_reps += set_entry.reps
        total_volume += set_volume

        if best_weight is None or set_entry.weight > best_weight["weight"]:
            best_weight = {
                "weight": set_entry.weight,
                "reps": set_entry.reps,
                "date": workout.started_at,
            }
        if best_1rm is None or one_rm > best_1rm["value"]:
            best_1rm = {
                "value": round(one_rm, 1),
                "weight": set_entry.weight,
                "reps": set_entry.reps,
                "date": workout.started_at,
            }
        if best_volume_set is None or set_volume > best_volume_set["value"]:
            best_volume_set = {
                "value": round(set_volume, 1),
                "weight": set_entry.weight,
                "reps": set_entry.reps,
                "date": workout.started_at,
            }

        entry = by_workout.setdefault(
            workout.id,
            {
                "workout_id": workout.id,
                "workout_name": workout.name,
                "date": workout.started_at,
                "sets": [],
                "best_1rm": 0.0,
                "best_weight": 0.0,
                "volume": 0.0,
            },
        )
        entry["sets"].append(
            {"weight": set_entry.weight, "reps": set_entry.reps, "is_pr": set_entry.is_pr}
        )
        entry["best_1rm"] = round(max(entry["best_1rm"], one_rm), 1)
        entry["best_weight"] = max(entry["best_weight"], set_entry.weight)
        entry["volume"] = round(entry["volume"] + set_volume, 1)

    workouts = sorted(by_workout.values(), key=lambda w: w["date"])
    chart = [
        {
            "date": w["date"],
            "best_1rm": w["best_1rm"],
            "best_weight": w["best_weight"],
            "volume": w["volume"],
        }
        for w in workouts
    ]

    return {
        "exercise": {
            "id": exercise.id,
            "name": exercise.name,
            "muscle_group": exercise.muscle_group,
            "equipment": exercise.equipment,
            "is_custom": exercise.owner_id is not None,
        },
        "records": {
            "best_weight": best_weight,
            "best_1rm": best_1rm,
            "best_volume_set": best_volume_set,
            "total_reps": total_reps,
            "total_volume": round(total_volume, 1),
            "times_performed": len(workouts),
        },
        "chart": chart,
        "history": list(reversed(workouts)),
    }


@router.delete("/{exercise_id}")
def delete_exercise(
    exercise_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    exercise = db.get(Exercise, exercise_id)
    if exercise is None or exercise.owner_id != user.id:
        raise HTTPException(status_code=404, detail="Custom exercise not found")
    db.delete(exercise)
    db.commit()
    return {"ok": True}
