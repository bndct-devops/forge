"""Shared serialization + stats helpers used by the workout and exercise APIs."""
from sqlalchemy import select
from sqlalchemy.orm import Session

from backend.models import Exercise, SetEntry, Workout, WorkoutExercise


def epley_1rm(weight: float, reps: int) -> float:
    if reps <= 0:
        return 0.0
    if reps == 1:
        return weight
    return weight * (1 + reps / 30)


def completed_sets_query(user_id: int, exercise_id: int, before_workout_id: int | None = None):
    """Completed sets for one exercise across the user's *finished* workouts."""
    q = (
        select(SetEntry, Workout)
        .join(WorkoutExercise, SetEntry.workout_exercise_id == WorkoutExercise.id)
        .join(Workout, WorkoutExercise.workout_id == Workout.id)
        .where(
            Workout.owner_id == user_id,
            Workout.finished_at.is_not(None),
            WorkoutExercise.exercise_id == exercise_id,
            SetEntry.is_completed.is_(True),
            SetEntry.weight.is_not(None),
            SetEntry.reps.is_not(None),
        )
    )
    if before_workout_id is not None:
        q = q.where(Workout.id != before_workout_id)
    return q


def previous_sets(db: Session, user_id: int, exercise_id: int, exclude_workout_id: int) -> list[dict]:
    """The sets from the most recent finished workout containing this exercise."""
    last_workout_id = db.execute(
        select(Workout.id)
        .join(WorkoutExercise, WorkoutExercise.workout_id == Workout.id)
        .where(
            Workout.owner_id == user_id,
            Workout.finished_at.is_not(None),
            Workout.id != exclude_workout_id,
            WorkoutExercise.exercise_id == exercise_id,
        )
        .order_by(Workout.finished_at.desc())
        .limit(1)
    ).scalar()
    if last_workout_id is None:
        return []
    rows = db.execute(
        select(SetEntry)
        .join(WorkoutExercise, SetEntry.workout_exercise_id == WorkoutExercise.id)
        .where(
            WorkoutExercise.workout_id == last_workout_id,
            WorkoutExercise.exercise_id == exercise_id,
            SetEntry.is_completed.is_(True),
        )
        .order_by(SetEntry.position)
    ).scalars()
    return [{"weight": s.weight, "reps": s.reps, "is_pr": s.is_pr} for s in rows]


def historical_bests(db: Session, user_id: int, exercise_id: int, exclude_workout_id: int | None = None) -> dict:
    """Best weight and best estimated 1RM across all prior finished workouts."""
    best_weight = 0.0
    best_1rm = 0.0
    rows = db.execute(completed_sets_query(user_id, exercise_id, exclude_workout_id)).all()
    for set_entry, _workout in rows:
        best_weight = max(best_weight, set_entry.weight)
        best_1rm = max(best_1rm, epley_1rm(set_entry.weight, set_entry.reps))
    return {"weight": best_weight, "one_rm": best_1rm}


def serialize_workout(db: Session, workout: Workout, with_previous: bool = True) -> dict:
    exercises = []
    for we in workout.exercises:
        exercise = db.get(Exercise, we.exercise_id)
        exercises.append(
            {
                "id": we.id,
                "exercise_id": we.exercise_id,
                "name": exercise.name if exercise else "Unknown",
                "muscle_group": exercise.muscle_group if exercise else "",
                "equipment": exercise.equipment if exercise else "",
                "position": we.position,
                "rest_seconds": we.rest_seconds,
                "sets": [
                    {
                        "id": s.id,
                        "position": s.position,
                        "weight": s.weight,
                        "reps": s.reps,
                        "is_completed": s.is_completed,
                        "is_pr": s.is_pr,
                    }
                    for s in we.sets
                ],
                "previous_sets": (
                    previous_sets(db, workout.owner_id, we.exercise_id, workout.id)
                    if with_previous
                    else []
                ),
            }
        )
    return {
        "id": workout.id,
        "name": workout.name,
        "notes": workout.notes,
        "started_at": workout.started_at,
        "finished_at": workout.finished_at,
        "exercises": exercises,
    }


def workout_totals(workout: Workout) -> dict:
    volume = 0.0
    sets = 0
    prs = 0
    for we in workout.exercises:
        for s in we.sets:
            if s.is_completed and s.weight is not None and s.reps is not None:
                volume += s.weight * s.reps
                sets += 1
                if s.is_pr:
                    prs += 1
    return {"total_volume": round(volume, 1), "total_sets": sets, "pr_count": prs}
