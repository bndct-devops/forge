"""Shared serialization + stats helpers used by the workout and exercise APIs."""
from sqlalchemy import select
from sqlalchemy.orm import Session

from backend.models import Exercise, ExerciseNote, SetEntry, Workout, WorkoutExercise


def epley_1rm(weight: float, reps: int) -> float:
    if reps <= 0:
        return 0.0
    if reps == 1:
        return weight
    return weight * (1 + reps / 30)


def completed_sets_query(user_id: int, exercise_id: int, before_workout_id: int | None = None):
    """Completed working sets (warm-ups excluded) for one exercise across the
    user's *finished* workouts."""
    q = (
        select(SetEntry, Workout)
        .join(WorkoutExercise, SetEntry.workout_exercise_id == WorkoutExercise.id)
        .join(Workout, WorkoutExercise.workout_id == Workout.id)
        .where(
            Workout.owner_id == user_id,
            Workout.finished_at.is_not(None),
            WorkoutExercise.exercise_id == exercise_id,
            SetEntry.is_completed.is_(True),
            SetEntry.is_warmup.is_(False),
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
            SetEntry.is_warmup.is_(False),
        )
        .order_by(SetEntry.position)
    ).scalars()
    return [{"weight": s.weight, "reps": s.reps, "is_pr": s.is_pr} for s in rows]


def historical_bests(db: Session, user_id: int, exercise_id: int, exclude_workout_id: int | None = None) -> dict:
    """Best weight, best estimated 1RM, and best bodyweight reps across all
    prior finished workouts."""
    best_weight = 0.0
    best_1rm = 0.0
    best_bw_reps = 0
    rows = db.execute(completed_sets_query(user_id, exercise_id, exclude_workout_id)).all()
    for set_entry, _workout in rows:
        weight = set_entry.weight or 0.0
        if weight > 0:
            best_weight = max(best_weight, weight)
            best_1rm = max(best_1rm, epley_1rm(weight, set_entry.reps))
        else:
            best_bw_reps = max(best_bw_reps, set_entry.reps)
    return {"weight": best_weight, "one_rm": best_1rm, "bw_reps": best_bw_reps}


def serialize_workout(db: Session, workout: Workout, with_previous: bool = True) -> dict:
    notes = {
        n.exercise_id: n.text
        for n in db.execute(
            select(ExerciseNote).where(
                ExerciseNote.user_id == workout.owner_id,
                ExerciseNote.exercise_id.in_([we.exercise_id for we in workout.exercises]),
            )
        ).scalars()
    }
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
                "note": notes.get(we.exercise_id, ""),
                "position": we.position,
                "rest_seconds": we.rest_seconds,
                "sets": [
                    {
                        "id": s.id,
                        "position": s.position,
                        "weight": s.weight,
                        "reps": s.reps,
                        "is_completed": s.is_completed,
                        "is_warmup": s.is_warmup,
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
    """Volume and set count over completed working sets — warm-ups don't count."""
    volume = 0.0
    sets = 0
    prs = 0
    for we in workout.exercises:
        for s in we.sets:
            if s.is_completed and not s.is_warmup and s.reps is not None:
                volume += (s.weight or 0.0) * s.reps
                sets += 1
                if s.is_pr:
                    prs += 1
    return {"total_volume": round(volume, 1), "total_sets": sets, "pr_count": prs}


def detect_prs(exercise_name: str, sets, bests: dict) -> list[dict]:
    """Mark PR flags on completed working sets against running bests (mutates
    both `sets` and `bests`); returns the PR descriptions. Shared by live
    finish and import recompute so the two can never disagree."""
    prs: list[dict] = []
    for s in sets:
        s.is_pr = False
        if not s.is_completed or s.is_warmup or s.reps is None:
            continue
        weight = s.weight or 0.0
        got_pr = False
        if weight > 0:
            one_rm = epley_1rm(weight, s.reps)
            if weight > bests["weight"]:
                bests["weight"] = weight
                got_pr = True
                prs.append(
                    {"exercise_name": exercise_name, "kind": "weight", "value": weight, "reps": s.reps}
                )
            if one_rm > bests["one_rm"]:
                bests["one_rm"] = one_rm
                if not got_pr:
                    prs.append(
                        {
                            "exercise_name": exercise_name,
                            "kind": "1rm",
                            "value": round(one_rm, 1),
                            "reps": s.reps,
                        }
                    )
                got_pr = True
        elif s.reps > bests["bw_reps"]:
            bests["bw_reps"] = s.reps
            got_pr = True
            prs.append(
                {"exercise_name": exercise_name, "kind": "reps", "value": s.reps, "reps": s.reps}
            )
        s.is_pr = got_pr
    return prs


def recompute_prs(db: Session, user_id: int) -> None:
    """Rebuild every PR flag for a user chronologically — used after imports,
    which can insert history before existing workouts."""
    workouts = (
        db.execute(
            select(Workout)
            .where(Workout.owner_id == user_id, Workout.finished_at.is_not(None))
            .order_by(Workout.started_at, Workout.id)
        )
        .scalars()
        .all()
    )
    bests: dict[int, dict] = {}
    for workout in workouts:
        for we in workout.exercises:
            exercise = db.get(Exercise, we.exercise_id)
            b = bests.setdefault(we.exercise_id, {"weight": 0.0, "one_rm": 0.0, "bw_reps": 0})
            detect_prs(exercise.name if exercise else "Unknown", we.sets, b)
    db.commit()
