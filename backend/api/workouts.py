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
from datetime import timedelta, timezone

from sqlalchemy import func

from backend.schemas import (
    SetRestore,
    WorkoutLogIn,
    SetUpdate,
    WorkoutExerciseAdd,
    WorkoutExerciseOrder,
    WorkoutExerciseUpdate,
    WorkoutStart,
    WorkoutUpdate,
)
from backend.core.webhooks import fire_webhook
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
    month: str | None = Query(default=None, pattern=r"^\d{4}-\d{2}$"),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    q = select(Workout).where(Workout.owner_id == user.id, Workout.finished_at.is_not(None))
    if month:
        year, mon = int(month[:4]), int(month[5:7])
        from datetime import datetime as _dt

        start = _dt(year, mon, 1)
        end = _dt(year + (mon == 12), (mon % 12) + 1, 1)
        q = q.where(Workout.started_at >= start, Workout.started_at < end)
        workouts = db.execute(q.order_by(Workout.started_at.desc())).scalars().all()
    else:
        workouts = (
            db.execute(q.order_by(Workout.started_at.desc()).limit(limit).offset(offset))
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



def _recent_session_sets(
    db: Session, user_id: int, exercise_id: int, n: int = 3
) -> list[list[tuple[float, int]]]:
    """Working sets of the last n finished sessions containing the exercise,
    most recent first: [[(weight, reps), ...], ...]."""
    rows = db.execute(
        select(Workout.id, Workout.started_at, SetEntry.weight, SetEntry.reps)
        .join(WorkoutExercise, WorkoutExercise.workout_id == Workout.id)
        .join(SetEntry, SetEntry.workout_exercise_id == WorkoutExercise.id)
        .where(
            Workout.owner_id == user_id,
            Workout.finished_at.is_not(None),
            WorkoutExercise.exercise_id == exercise_id,
            SetEntry.is_completed.is_(True),
            SetEntry.is_warmup.is_(False),
            SetEntry.reps.is_not(None),
        )
        .order_by(Workout.started_at.desc())
    ).all()
    sessions: dict[int, list[tuple[float, int]]] = {}
    order: list[int] = []
    for wid, _started, weight, reps in rows:
        if wid not in sessions:
            if len(order) >= n:
                continue
            sessions[wid] = []
            order.append(wid)
        sessions[wid].append((weight or 0.0, reps or 0))
    return [sessions[w] for w in order]


def _stalled(sessions: list[list[tuple[float, int]]], rep_max: int) -> float | None:
    """Three sessions at the same top weight, none completing the rep target
    on every set -> return that weight, else None."""
    if len(sessions) < 3:
        return None
    tops = [max((w for w, _ in sess), default=0.0) for sess in sessions]
    if tops[0] <= 0 or any(abs(t - tops[0]) > 0.01 for t in tops):
        return None
    for sess in sessions:
        if all(reps >= rep_max for _, reps in sess):
            return None  # at least one session hit the target across the board
    return tops[0]


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
            suggestion = None
            kind = None
            if re_.rep_max:
                # Double progression: every previous working set hit rep_max
                # -> suggest last weight + increment
                prev = previous_sets(db, user.id, re_.exercise_id, exclude_workout_id=-1)
                working = [x for x in prev if x["reps"] is not None]
                if working:
                    top_weight = max((x["weight"] or 0) for x in working)
                    if all(x["reps"] >= re_.rep_max for x in working) and top_weight > 0:
                        suggestion = top_weight + (re_.increment or 2.5)
                        kind = "progress"
                    elif user.deload_hints:
                        # Three straight sessions stuck at the same weight
                        # without hitting the target -> suggest ~10% off
                        sessions = _recent_session_sets(db, user.id, re_.exercise_id)
                        stall_weight = _stalled(sessions, re_.rep_max)
                        if stall_weight is not None:
                            step = re_.increment or 2.5
                            suggestion = max(step, round(stall_weight * 0.9 / step) * step)
                            kind = "deload"
            we = WorkoutExercise(
                exercise_id=re_.exercise_id,
                position=re_.position,
                rest_seconds=re_.rest_seconds,
                superset_with_next=re_.superset_with_next,
                rep_min=re_.rep_min,
                rep_max=re_.rep_max,
                suggested_weight=suggestion,
                suggestion_kind=kind,
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
                superset_with_next=src_we.superset_with_next,
                rep_min=src_we.rep_min,
                rep_max=src_we.rep_max,
            )
            we.sets = [SetEntry(position=i) for i in range(max(1, len(src_we.sets)))]
            exercises.append(we)

    workout = Workout(owner_id=user.id, name=name or "Workout", started_at=utcnow())
    workout.exercises = exercises
    db.add(workout)
    db.commit()
    return serialize_workout(db, workout)




def _naive_utc(dt):
    if dt is None:
        return None
    if dt.tzinfo is not None:
        return dt.astimezone(timezone.utc).replace(tzinfo=None)
    return dt


def _build_logged_exercises(
    db: Session, user: User, body: WorkoutLogIn, finished_at
) -> list[WorkoutExercise]:
    """Resolve/create exercises and build completed WorkoutExercise rows for
    one-call logging. Names use the same suffix-tolerant matching as imports."""
    from backend.api.import_export import _guess_equipment, _match_exercise

    cache = {
        e.name.lower(): e
        for e in db.execute(
            select(Exercise).where(
                or_(Exercise.owner_id.is_(None), Exercise.owner_id == user.id)
            )
        ).scalars()
    }
    built: list[WorkoutExercise] = []
    for position, entry in enumerate(body.exercises):
        if entry.exercise_id is not None:
            exercise = _visible_exercise(db, user, entry.exercise_id)
        elif entry.name:
            exercise = _match_exercise(cache, entry.name)
            if exercise is None:
                exercise = Exercise(
                    name=entry.name.strip(),
                    muscle_group="Other",
                    equipment=_guess_equipment(entry.name),
                    owner_id=user.id,
                )
                db.add(exercise)
                db.flush()
                cache[exercise.name.lower()] = exercise
        else:
            raise HTTPException(
                status_code=422, detail="Each exercise needs exercise_id or name"
            )
        we = WorkoutExercise(
            exercise_id=exercise.id,
            position=position,
            rest_seconds=entry.rest_seconds,
            superset_with_next=entry.superset_with_next,
        )
        we.sets = [
            SetEntry(
                position=i,
                weight=s.weight,
                reps=s.reps,
                is_completed=True,
                is_warmup=s.is_warmup,
                set_type=s.set_type,
                rpe=s.rpe,
                completed_at=finished_at,
            )
            for i, s in enumerate(entry.sets)
        ]
        built.append(we)
    return built


def _log_window(body: WorkoutLogIn) -> tuple:
    started_at = _naive_utc(body.started_at)
    finished_at = _naive_utc(body.finished_at)
    if finished_at is None:
        finished_at = started_at + timedelta(seconds=body.duration_seconds or 3600)
    if finished_at <= started_at:
        raise HTTPException(status_code=422, detail="finished_at must be after started_at")
    return started_at, finished_at


@router.post("/log")
def log_workout(
    body: WorkoutLogIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Create a complete, finished workout in one call (API clients).
    Exercises resolve by id or by name (created under your account when
    unknown). PRs are recomputed chronologically, so backdating is fine."""
    started_at, finished_at = _log_window(body)
    workout = Workout(
        owner_id=user.id,
        name=body.name.strip(),
        notes=body.notes,
        started_at=started_at,
        finished_at=finished_at,
    )
    workout.exercises = _build_logged_exercises(db, user, body, finished_at)
    db.add(workout)
    db.commit()
    recompute_prs(db, user.id)
    fire_webhook(user, workout, source="api")
    data = serialize_workout(db, workout)
    data.update(
        duration_seconds=int((finished_at - started_at).total_seconds()),
        **workout_totals(workout),
    )
    return data


@router.put("/{workout_id}")
def replace_workout(
    workout_id: int,
    body: WorkoutLogIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Full-replace a finished workout with the same payload shape as /log."""
    workout = _get_own_workout(db, user, workout_id)
    if workout.finished_at is None:
        raise HTTPException(
            status_code=409, detail="Workout is in progress — finish it in the app first"
        )
    started_at, finished_at = _log_window(body)
    workout.name = body.name.strip()
    workout.notes = body.notes
    workout.started_at = started_at
    workout.finished_at = finished_at
    workout.exercises = _build_logged_exercises(db, user, body, finished_at)
    db.add(workout)
    db.commit()
    recompute_prs(db, user.id)
    data = serialize_workout(db, workout)
    data.update(
        duration_seconds=int((finished_at - started_at).total_seconds()),
        **workout_totals(workout),
    )
    return data


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
    # Program workouts advance their program's state machine on finish —
    # never on start, so a cancelled session doesn't burn a slot.
    from backend.api.programs import advance_program
    advance_program(db, workout)
    db.commit()
    fire_webhook(user, workout, source="app")

    totals = workout_totals(workout)
    duration = int((workout.finished_at - workout.started_at).total_seconds())

    # Context for the finish screen: lifetime count + count this week
    workout_number = db.execute(
        select(func.count(Workout.id)).where(
            Workout.owner_id == user.id, Workout.finished_at.is_not(None)
        )
    ).scalar()
    week_start = workout.started_at - timedelta(
        days=workout.started_at.weekday(),
        hours=workout.started_at.hour,
        minutes=workout.started_at.minute,
        seconds=workout.started_at.second,
    )
    week_workouts = db.execute(
        select(func.count(Workout.id)).where(
            Workout.owner_id == user.id,
            Workout.finished_at.is_not(None),
            Workout.started_at >= week_start,
        )
    ).scalar()

    # Compare against the previous finished workout with the same name
    previous_same = db.execute(
        select(Workout)
        .where(
            Workout.owner_id == user.id,
            Workout.finished_at.is_not(None),
            Workout.name == workout.name,
            Workout.id != workout.id,
        )
        .order_by(Workout.started_at.desc())
        .limit(1)
    ).scalar_one_or_none()
    comparison = None
    if previous_same is not None:
        prev_totals = workout_totals(previous_same)
        comparison = {
            "prev_volume": prev_totals["total_volume"],
            "prev_sets": prev_totals["total_sets"],
            "prev_date": previous_same.started_at,
        }

    return {
        "id": workout.id,
        "name": workout.name,
        "duration_seconds": duration,
        "total_volume": totals["total_volume"],
        "total_sets": totals["total_sets"],
        "prs": prs,
        "workout_number": workout_number,
        "week_workouts": week_workouts,
        "comparison": comparison,
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
    if "rest_seconds" in body.model_fields_set:
        we.rest_seconds = body.rest_seconds
    if body.superset_with_next is not None:
        we.superset_with_next = body.superset_with_next
    if body.exercise_id is not None and body.exercise_id != we.exercise_id:
        # Swap: keep logged sets, drop the old exercise's progression targets
        _visible_exercise(db, user, body.exercise_id)
        we.exercise_id = body.exercise_id
        we.rep_min = None
        we.rep_max = None
        we.suggested_weight = None
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
    body: SetRestore | None = None,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    workout = _get_own_workout(db, user, workout_id)
    we = next((x for x in workout.exercises if x.id == we_id), None)
    if we is None:
        raise HTTPException(status_code=404, detail="Exercise not in workout")
    if body is None:
        we.sets.append(SetEntry(position=len(we.sets)))
    else:
        # Undo of a deletion: slot the set back where it was
        pos = body.position if body.position is not None else len(we.sets)
        pos = min(pos, len(we.sets))
        for s in we.sets:
            if s.position >= pos:
                s.position += 1
        we.sets.append(
            SetEntry(
                position=pos,
                weight=body.weight,
                reps=body.reps,
                is_completed=body.is_completed,
                is_warmup=body.is_warmup,
                set_type=body.set_type,
                rpe=body.rpe,
                completed_at=utcnow() if body.is_completed else None,
            )
        )
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
    if "set_type" in body.model_fields_set:
        set_entry.set_type = body.set_type
    if "rpe" in body.model_fields_set:
        set_entry.rpe = body.rpe
    db.add(set_entry)
    db.commit()
    return {
        "id": set_entry.id,
        "position": set_entry.position,
        "weight": set_entry.weight,
        "reps": set_entry.reps,
        "is_completed": set_entry.is_completed,
        "is_warmup": set_entry.is_warmup,
        "set_type": set_entry.set_type,
        "is_pr": set_entry.is_pr,
        "rpe": set_entry.rpe,
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
