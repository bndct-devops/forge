from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from backend.core.clock import utcnow
from backend.core.database import get_db
from backend.core.security import get_current_user
from backend.models import (
    Exercise,
    Routine,
    SetEntry,
    User,
    Workout,
    WorkoutExercise,
)
from datetime import timezone

from backend.schemas import (
    SetUpdate,
    WorkoutExerciseAdd,
    WorkoutExerciseOrder,
    WorkoutExerciseUpdate,
    WorkoutStart,
    WorkoutUpdate,
)
from backend.serializers import (
    detect_prs,
    historical_bests,
    previous_sets,
    recompute_prs,
    serialize_workout,
    workout_totals,
)

router = APIRouter(prefix="/workouts", tags=["workouts"])
sets_router = APIRouter(prefix="/sets", tags=["workouts"])


def _get_own_workout(db: Session, user: User, workout_id: int) -> Workout:
    workout = db.get(Workout, workout_id)
    if workout is None or workout.owner_id != user.id:
        raise HTTPException(status_code=404, detail="Workout not found")
    return workout


def _get_active(db: Session, user: User) -> Workout | None:
    return db.execute(
        select(Workout)
        .where(Workout.owner_id == user.id, Workout.finished_at.is_(None))
        .order_by(Workout.started_at.desc())
        .limit(1)
    ).scalar_one_or_none()


def _visible_exercise(db: Session, user: User, exercise_id: int) -> Exercise:
    exercise = db.execute(
        select(Exercise).where(
            Exercise.id == exercise_id,
            or_(Exercise.owner_id.is_(None), Exercise.owner_id == user.id),
        )
    ).scalar_one_or_none()
    if exercise is None:
        raise HTTPException(status_code=404, detail="Exercise not found")
    return exercise


# ── Static routes first (before /{workout_id}) ──────────────────────────────

@router.get("/active")
def active_workout(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    workout = _get_active(db, user)
    if workout is None:
        return None
    return serialize_workout(db, workout)


@router.get("")
def list_workouts(
    limit: int = Query(default=20, le=100),
    offset: int = 0,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    workouts = (
        db.execute(
            select(Workout)
            .where(Workout.owner_id == user.id, Workout.finished_at.is_not(None))
            .order_by(Workout.started_at.desc())
            .limit(limit)
            .offset(offset)
        )
        .scalars()
        .all()
    )
    result = []
    for w in workouts:
        totals = workout_totals(w)
        summaries = []
        for we in w.exercises:
            exercise = db.get(Exercise, we.exercise_id)
            completed = sum(1 for s in we.sets if s.is_completed)
            if exercise and completed:
                summaries.append(f"{completed} × {exercise.name}")
        duration = int((w.finished_at - w.started_at).total_seconds())
        result.append(
            {
                "id": w.id,
                "name": w.name,
                "started_at": w.started_at,
                "finished_at": w.finished_at,
                "duration_seconds": duration,
                "exercise_summaries": summaries,
                **totals,
            }
        )
    return result


@router.post("")
def start_workout(
    body: WorkoutStart,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if _get_active(db, user) is not None:
        raise HTTPException(status_code=409, detail="A workout is already in progress")

    name = body.name
    exercises: list[WorkoutExercise] = []
    if body.routine_id is not None:
        routine = db.get(Routine, body.routine_id)
        if routine is None or routine.owner_id != user.id:
            raise HTTPException(status_code=404, detail="Routine not found")
        name = name or routine.name
        for re_ in routine.exercises:
            we = WorkoutExercise(
                exercise_id=re_.exercise_id,
                position=re_.position,
                rest_seconds=re_.rest_seconds,
            )
            we.sets = [SetEntry(position=i) for i in range(re_.set_count)]
            exercises.append(we)
    elif body.workout_id is not None:
        source = db.get(Workout, body.workout_id)
        if source is None or source.owner_id != user.id:
            raise HTTPException(status_code=404, detail="Workout not found")
        name = name or source.name
        for src_we in source.exercises:
            we = WorkoutExercise(
                exercise_id=src_we.exercise_id,
                position=src_we.position,
                rest_seconds=src_we.rest_seconds,
            )
            we.sets = [SetEntry(position=i) for i in range(max(1, len(src_we.sets)))]
            exercises.append(we)

    workout = Workout(owner_id=user.id, name=name or "Workout", started_at=utcnow())
    workout.exercises = exercises
    db.add(workout)
    db.commit()
    return serialize_workout(db, workout)


# ── Per-workout routes ───────────────────────────────────────────────────────

@router.get("/{workout_id}")
def get_workout(
    workout_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    workout = _get_own_workout(db, user, workout_id)
    data = serialize_workout(db, workout, with_previous=workout.finished_at is None)
    if workout.finished_at is not None:
        duration = int((workout.finished_at - workout.started_at).total_seconds())
        data.update(duration_seconds=duration, **workout_totals(workout))
    return data


@router.patch("/{workout_id}")
def update_workout(
    workout_id: int,
    body: WorkoutUpdate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    workout = _get_own_workout(db, user, workout_id)
    if body.name is not None:
        workout.name = body.name.strip()
    if body.notes is not None:
        workout.notes = body.notes
    date_changed = False
    if body.started_at is not None:
        started = body.started_at
        if started.tzinfo is not None:
            started = started.astimezone(timezone.utc).replace(tzinfo=None)
        if workout.finished_at is not None:
            duration = workout.finished_at - workout.started_at
            workout.finished_at = started + duration
        workout.started_at = started
        date_changed = True
    db.add(workout)
    db.commit()
    # Moving a workout in time reorders history — PR flags must follow
    if date_changed and workout.finished_at is not None:
        recompute_prs(db, user.id)
        db.refresh(workout)
    return serialize_workout(db, workout, with_previous=workout.finished_at is None)


@router.delete("/{workout_id}")
def delete_workout(
    workout_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    workout = _get_own_workout(db, user, workout_id)
    db.delete(workout)
    db.commit()
    return {"ok": True}


@router.post("/{workout_id}/finish")
def finish_workout(
    workout_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    workout = _get_own_workout(db, user, workout_id)
    if workout.finished_at is not None:
        raise HTTPException(status_code=400, detail="Workout already finished")

    # Drop incomplete sets and exercises left empty
    for we in list(workout.exercises):
        we.sets = [s for s in we.sets if s.is_completed]
        for i, s in enumerate(we.sets):
            s.position = i
        if not we.sets:
            workout.exercises.remove(we)
    if not workout.exercises:
        raise HTTPException(
            status_code=400, detail="Complete at least one set before finishing"
        )

    # PR detection against each exercise's historical bests
    prs = []
    for we in workout.exercises:
        exercise = db.get(Exercise, we.exercise_id)
        bests = historical_bests(db, user.id, we.exercise_id, exclude_workout_id=workout.id)
        prs.extend(detect_prs(exercise.name if exercise else "Unknown", we.sets, bests))

    workout.finished_at = utcnow()
    db.add(workout)
    db.commit()

    totals = workout_totals(workout)
    duration = int((workout.finished_at - workout.started_at).total_seconds())
    return {
        "id": workout.id,
        "name": workout.name,
        "duration_seconds": duration,
        "total_volume": totals["total_volume"],
        "total_sets": totals["total_sets"],
        "prs": prs,
    }


@router.put("/{workout_id}/exercise-order")
def reorder_exercises(
    workout_id: int,
    body: WorkoutExerciseOrder,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    workout = _get_own_workout(db, user, workout_id)
    current_ids = {we.id for we in workout.exercises}
    if set(body.exercise_ids) != current_ids or len(body.exercise_ids) != len(current_ids):
        raise HTTPException(status_code=400, detail="Order must contain each exercise exactly once")
    position_by_id = {we_id: i for i, we_id in enumerate(body.exercise_ids)}
    for we in workout.exercises:
        we.position = position_by_id[we.id]
    db.add(workout)
    db.commit()
    db.refresh(workout)
    return serialize_workout(db, workout, with_previous=workout.finished_at is None)


@router.post("/{workout_id}/recompute")
def recompute_workout(
    workout_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Close out an editing session on a finished workout: prune sets left
    incomplete, drop emptied exercises, and rebuild the user's PR flags."""
    workout = _get_own_workout(db, user, workout_id)
    if workout.finished_at is None:
        raise HTTPException(status_code=400, detail="Workout is not finished")

    for we in list(workout.exercises):
        we.sets = [s for s in we.sets if s.is_completed]
        for i, s in enumerate(we.sets):
            s.position = i
        if not we.sets:
            workout.exercises.remove(we)
    for i, we in enumerate(workout.exercises):
        we.position = i

    if not workout.exercises:
        db.delete(workout)
        db.commit()
        recompute_prs(db, user.id)
        return {"deleted": True}

    db.add(workout)
    db.commit()
    recompute_prs(db, user.id)

    db.refresh(workout)
    data = serialize_workout(db, workout, with_previous=False)
    duration = int((workout.finished_at - workout.started_at).total_seconds())
    data.update(duration_seconds=duration, **workout_totals(workout))
    return data


# ── Exercises within a workout ───────────────────────────────────────────────

@router.post("/{workout_id}/exercises")
def add_exercise(
    workout_id: int,
    body: WorkoutExerciseAdd,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    workout = _get_own_workout(db, user, workout_id)
    _visible_exercise(db, user, body.exercise_id)

    # Mirror the set count of the last time this exercise was performed
    prev = previous_sets(db, user.id, body.exercise_id, workout.id)
    set_count = max(len(prev), 1)

    we = WorkoutExercise(
        workout_id=workout.id,
        exercise_id=body.exercise_id,
        position=len(workout.exercises),
    )
    we.sets = [SetEntry(position=i) for i in range(set_count)]
    workout.exercises.append(we)
    db.add(workout)
    db.commit()
    return serialize_workout(db, workout)


@router.patch("/{workout_id}/exercises/{we_id}")
def update_workout_exercise(
    workout_id: int,
    we_id: int,
    body: WorkoutExerciseUpdate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    workout = _get_own_workout(db, user, workout_id)
    we = next((x for x in workout.exercises if x.id == we_id), None)
    if we is None:
        raise HTTPException(status_code=404, detail="Exercise not in workout")
    we.rest_seconds = body.rest_seconds
    db.add(we)
    db.commit()
    return serialize_workout(db, workout)


@router.delete("/{workout_id}/exercises/{we_id}")
def remove_exercise(
    workout_id: int,
    we_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    workout = _get_own_workout(db, user, workout_id)
    we = next((x for x in workout.exercises if x.id == we_id), None)
    if we is None:
        raise HTTPException(status_code=404, detail="Exercise not in workout")
    workout.exercises.remove(we)
    for i, x in enumerate(workout.exercises):
        x.position = i
    db.add(workout)
    db.commit()
    return serialize_workout(db, workout)


@router.post("/{workout_id}/exercises/{we_id}/sets")
def add_set(
    workout_id: int,
    we_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    workout = _get_own_workout(db, user, workout_id)
    we = next((x for x in workout.exercises if x.id == we_id), None)
    if we is None:
        raise HTTPException(status_code=404, detail="Exercise not in workout")
    we.sets.append(SetEntry(position=len(we.sets)))
    db.add(we)
    db.commit()
    return serialize_workout(db, workout)


# ── Individual sets ──────────────────────────────────────────────────────────

def _get_own_set(db: Session, user: User, set_id: int) -> tuple[SetEntry, Workout]:
    row = db.execute(
        select(SetEntry, Workout)
        .join(WorkoutExercise, SetEntry.workout_exercise_id == WorkoutExercise.id)
        .join(Workout, WorkoutExercise.workout_id == Workout.id)
        .where(SetEntry.id == set_id, Workout.owner_id == user.id)
    ).first()
    if row is None:
        raise HTTPException(status_code=404, detail="Set not found")
    return row[0], row[1]


@sets_router.patch("/{set_id}")
def update_set(
    set_id: int,
    body: SetUpdate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    set_entry, _workout = _get_own_set(db, user, set_id)
    if body.weight is not None:
        set_entry.weight = body.weight
    if body.reps is not None:
        set_entry.reps = body.reps
    if body.is_completed is not None:
        set_entry.is_completed = body.is_completed
        set_entry.completed_at = utcnow() if body.is_completed else None
    if body.is_warmup is not None:
        set_entry.is_warmup = body.is_warmup
    db.add(set_entry)
    db.commit()
    return {
        "id": set_entry.id,
        "position": set_entry.position,
        "weight": set_entry.weight,
        "reps": set_entry.reps,
        "is_completed": set_entry.is_completed,
        "is_warmup": set_entry.is_warmup,
        "is_pr": set_entry.is_pr,
    }


@sets_router.delete("/{set_id}")
def delete_set(
    set_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    set_entry, _workout = _get_own_set(db, user, set_id)
    we = db.get(WorkoutExercise, set_entry.workout_exercise_id)
    db.delete(set_entry)
    db.flush()
    if we is not None:
        remaining = sorted((s for s in we.sets if s.id != set_id), key=lambda s: s.position)
        for i, s in enumerate(remaining):
            s.position = i
    db.commit()
    return {"ok": True}
