from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from backend.core.database import get_db
from backend.core.security import get_current_user
from pydantic import BaseModel, Field

from backend.models import Exercise, ExerciseNote, SetEntry, User, Workout, WorkoutExercise
from backend.schemas import ExerciseCreate, ExerciseOut, RecategorizeIn
from backend.serializers import completed_sets_query, epley_1rm

router = APIRouter(prefix="/exercises", tags=["exercises"])


def _visible(user_id: int):
    return or_(Exercise.owner_id.is_(None), Exercise.owner_id == user_id)


@router.get("", response_model=list[ExerciseOut])
def list_exercises(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    last_used_sq = (
        select(
            WorkoutExercise.exercise_id.label("exercise_id"),
            func.max(Workout.started_at).label("last_used"),
        )
        .join(Workout, WorkoutExercise.workout_id == Workout.id)
        .where(Workout.owner_id == user.id, Workout.finished_at.is_not(None))
        .group_by(WorkoutExercise.exercise_id)
        .subquery()
    )
    rows = db.execute(
        select(Exercise, last_used_sq.c.last_used)
        .outerjoin(last_used_sq, Exercise.id == last_used_sq.c.exercise_id)
        .where(_visible(user.id))
        .order_by(Exercise.name)
    ).all()
    return [
        ExerciseOut(
            id=e.id,
            name=e.name,
            muscle_group=e.muscle_group,
            equipment=e.equipment,
            grip=e.grip,
            grip_width=e.grip_width,
            attachment=e.attachment,
            variant_of_id=e.variant_of_id,
            is_custom=e.owner_id is not None,
            last_used=last_used,
        )
        for e, last_used in rows
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
        grip=body.grip,
        grip_width=body.grip_width,
        attachment=body.attachment,
        owner_id=user.id,
    )
    db.add(exercise)
    db.commit()
    return ExerciseOut(
        id=exercise.id,
        name=exercise.name,
        muscle_group=exercise.muscle_group,
        equipment=exercise.equipment,
        grip=exercise.grip,
        grip_width=exercise.grip_width,
        attachment=exercise.attachment,
        is_custom=True,
    )


class VariantIn(BaseModel):
    grip: str | None = Field(default=None, max_length=24)
    grip_width: str | None = Field(default=None, max_length=16)
    attachment: str | None = Field(default=None, max_length=24)
    equipment: str | None = Field(default=None, max_length=32)


def _variant_name(base: Exercise, body: VariantIn) -> str:
    """Compose a readable canonical name from the modifiers that differ from
    the base: 'Close-Grip Bench Press (Smith Machine)' style."""
    name = base.name
    if body.grip_width and body.grip_width != base.grip_width:
        name = f"{body.grip_width}-Grip {name}"
    parts = []
    if body.grip and body.grip != base.grip:
        parts.append(body.grip)
    if body.equipment and body.equipment != base.equipment:
        parts.append(body.equipment)
    if body.attachment and body.attachment != base.attachment:
        parts.append(body.attachment)
    if parts:
        name = f"{name} ({', '.join(parts)})"
    return name


@router.post("/{exercise_id}/variant", response_model=ExerciseOut)
def create_variant(
    exercise_id: int,
    body: VariantIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Spawn a variant of an exercise from modifier toggles. The variant is
    linked into the base movement's family and tracks its own history."""
    source = db.execute(
        select(Exercise).where(Exercise.id == exercise_id, _visible(user.id))
    ).scalar_one_or_none()
    if source is None:
        raise HTTPException(status_code=404, detail="Exercise not found")
    # Variants always hang off the family root, never off another variant
    base = db.get(Exercise, source.variant_of_id) if source.variant_of_id else source

    if not any([body.grip, body.grip_width, body.attachment, body.equipment]):
        raise HTTPException(status_code=422, detail="Pick at least one modifier")

    name = _variant_name(base, body)
    existing = db.execute(
        select(Exercise).where(_visible(user.id), Exercise.name == name)
    ).scalar_one_or_none()
    if existing is not None:
        # Same combination already exists — hand it back instead of erroring
        return ExerciseOut(
            id=existing.id,
            name=existing.name,
            muscle_group=existing.muscle_group,
            equipment=existing.equipment,
            grip=existing.grip,
            grip_width=existing.grip_width,
            attachment=existing.attachment,
            variant_of_id=existing.variant_of_id,
            is_custom=existing.owner_id is not None,
        )

    exercise = Exercise(
        name=name,
        muscle_group=base.muscle_group,
        equipment=body.equipment or base.equipment,
        grip=body.grip,
        grip_width=body.grip_width,
        attachment=body.attachment,
        variant_of_id=base.id,
        owner_id=user.id,
    )
    db.add(exercise)
    db.commit()
    return ExerciseOut(
        id=exercise.id,
        name=exercise.name,
        muscle_group=exercise.muscle_group,
        equipment=exercise.equipment,
        grip=exercise.grip,
        grip_width=exercise.grip_width,
        attachment=exercise.attachment,
        variant_of_id=exercise.variant_of_id,
        is_custom=True,
    )


@router.post("/recategorize")
def recategorize(
    body: RecategorizeIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Bulk-fix muscle groups — mainly for imported exercises that landed in 'Other'."""
    updated = 0
    for item in body.items:
        exercise = db.get(Exercise, item.id)
        if exercise is None or exercise.owner_id != user.id:
            continue
        if exercise.muscle_group != item.muscle_group:
            exercise.muscle_group = item.muscle_group
            db.add(exercise)
            updated += 1
    db.commit()
    return {"updated": updated}


class NoteIn(BaseModel):
    text: str = Field(max_length=2000)


@router.put("/{exercise_id}/note")
def put_note(
    exercise_id: int,
    body: NoteIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    exercise = db.execute(
        select(Exercise).where(Exercise.id == exercise_id, _visible(user.id))
    ).scalar_one_or_none()
    if exercise is None:
        raise HTTPException(status_code=404, detail="Exercise not found")
    note = db.execute(
        select(ExerciseNote).where(
            ExerciseNote.user_id == user.id, ExerciseNote.exercise_id == exercise_id
        )
    ).scalar_one_or_none()
    text = body.text.strip()
    if not text:
        if note is not None:
            db.delete(note)
    elif note is None:
        db.add(ExerciseNote(user_id=user.id, exercise_id=exercise_id, text=text))
    else:
        note.text = text
        db.add(note)
    db.commit()
    return {"text": text}


@router.get("/{exercise_id}/recent")
def recent_sessions(
    exercise_id: int,
    limit: int = 3,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The last few sessions of this exercise — for the mid-workout peek."""
    workout_ids = db.execute(
        select(Workout.id, Workout.name, Workout.started_at)
        .join(WorkoutExercise, WorkoutExercise.workout_id == Workout.id)
        .where(
            Workout.owner_id == user.id,
            Workout.finished_at.is_not(None),
            WorkoutExercise.exercise_id == exercise_id,
        )
        .order_by(Workout.started_at.desc())
        .limit(min(limit, 10))
    ).all()
    sessions = []
    for wid, name, started_at in workout_ids:
        rows = db.execute(
            completed_sets_query(user.id, exercise_id)
            .where(Workout.id == wid)
            .order_by(SetEntry.position)
        ).all()
        sessions.append(
            {
                "workout_id": wid,
                "name": name,
                "date": started_at,
                "sets": [
                    {"weight": se.weight, "reps": se.reps, "is_pr": se.is_pr, "rpe": se.rpe}
                    for se, _w in rows
                ],
            }
        )
    return sessions


@router.get("/{exercise_id}/stats")
def exercise_stats(
    exercise_id: int,
    family: bool = False,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    exercise = db.execute(
        select(Exercise).where(Exercise.id == exercise_id, _visible(user.id))
    ).scalar_one_or_none()
    if exercise is None:
        raise HTTPException(status_code=404, detail="Exercise not found")

    base_for_family = exercise.variant_of_id or exercise.id
    if family:
        stat_ids = [
            e.id
            for e in db.execute(
                select(Exercise).where(
                    _visible(user.id),
                    or_(Exercise.id == base_for_family, Exercise.variant_of_id == base_for_family),
                )
            ).scalars()
        ]
    else:
        stat_ids = [exercise_id]

    rows = db.execute(
        completed_sets_query(user.id, stat_ids).order_by(Workout.started_at)
    ).all()

    best_weight = None
    best_1rm = None
    best_volume_set = None
    best_reps = None  # bodyweight sets (no load) — most reps
    total_reps = 0
    total_volume = 0.0

    # Per-workout aggregation for history + chart
    by_workout: dict[int, dict] = {}
    for set_entry, workout in rows:
        weight = set_entry.weight or 0.0
        one_rm = epley_1rm(weight, set_entry.reps) if weight > 0 else 0.0
        set_volume = weight * set_entry.reps
        total_reps += set_entry.reps
        total_volume += set_volume

        if weight > 0:
            if best_weight is None or weight > best_weight["weight"]:
                best_weight = {
                    "weight": weight,
                    "reps": set_entry.reps,
                    "date": workout.started_at,
                }
            if best_1rm is None or one_rm > best_1rm["value"]:
                best_1rm = {
                    "value": round(one_rm, 1),
                    "weight": weight,
                    "reps": set_entry.reps,
                    "date": workout.started_at,
                }
            if best_volume_set is None or set_volume > best_volume_set["value"]:
                best_volume_set = {
                    "value": round(set_volume, 1),
                    "weight": weight,
                    "reps": set_entry.reps,
                    "date": workout.started_at,
                }
        elif best_reps is None or set_entry.reps > best_reps["reps"]:
            best_reps = {"weight": 0, "reps": set_entry.reps, "date": workout.started_at}

        entry = by_workout.setdefault(
            workout.id,
            {
                "workout_id": workout.id,
                "workout_name": workout.name,
                "date": workout.started_at,
                "sets": [],
                "best_1rm": 0.0,
                "best_weight": 0.0,
                "best_reps": 0,
                "volume": 0.0,
                "rpe_sum": 0.0,
                "rpe_n": 0,
            },
        )
        entry["sets"].append(
            {"weight": weight, "reps": set_entry.reps, "is_pr": set_entry.is_pr}
        )
        entry["best_1rm"] = round(max(entry["best_1rm"], one_rm), 1)
        entry["best_weight"] = max(entry["best_weight"], weight)
        entry["best_reps"] = max(entry["best_reps"], set_entry.reps)
        entry["volume"] = round(entry["volume"] + set_volume, 1)
        if set_entry.rpe is not None:
            entry["rpe_sum"] += set_entry.rpe
            entry["rpe_n"] += 1

    workouts = sorted(by_workout.values(), key=lambda w: w["date"])
    chart = [
        {
            "date": w["date"],
            "best_1rm": w["best_1rm"],
            "best_weight": w["best_weight"],
            "best_reps": w["best_reps"],
            "volume": w["volume"],
            "avg_rpe": round(w["rpe_sum"] / w["rpe_n"], 1) if w["rpe_n"] else None,
        }
        for w in workouts
    ]
    for w in workouts:
        del w["rpe_sum"], w["rpe_n"]

    base_id = exercise.variant_of_id or exercise.id
    family_members = db.execute(
        select(Exercise)
        .where(
            _visible(user.id),
            or_(Exercise.id == base_id, Exercise.variant_of_id == base_id),
        )
        .order_by(Exercise.name)
    ).scalars().all()
    # Only a family when there is more than one member; includes the current
    # exercise so the client can render it highlighted in place
    variations = (
        [
            {
                "id": v.id,
                "name": v.name,
                "grip": v.grip,
                "grip_width": v.grip_width,
                "attachment": v.attachment,
                "equipment": v.equipment,
            }
            for v in family_members
        ]
        if len(family_members) > 1
        else []
    )

    note = db.execute(
        select(ExerciseNote.text).where(
            ExerciseNote.user_id == user.id, ExerciseNote.exercise_id == exercise_id
        )
    ).scalar_one_or_none()

    return {
        "exercise": {
            "id": exercise.id,
            "name": exercise.name,
            "muscle_group": exercise.muscle_group,
            "equipment": exercise.equipment,
            "grip": exercise.grip,
            "grip_width": exercise.grip_width,
            "attachment": exercise.attachment,
            "variant_of_id": exercise.variant_of_id,
            "is_custom": exercise.owner_id is not None,
        },
        "note": note or "",
        "variations": variations,
        "records": {
            "best_weight": best_weight,
            "best_1rm": best_1rm,
            "best_volume_set": best_volume_set,
            "best_reps": best_reps,
            "total_reps": total_reps,
            "total_volume": round(total_volume, 1),
            "times_performed": len(workouts),
        },
        "chart": chart,
        "history": list(reversed(workouts)),
    }


@router.patch("/{exercise_id}", response_model=ExerciseOut)
def update_exercise(
    exercise_id: int,
    body: ExerciseCreate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    exercise = db.get(Exercise, exercise_id)
    if exercise is None or exercise.owner_id != user.id:
        raise HTTPException(status_code=404, detail="Custom exercise not found")
    name = body.name.strip()
    clash = db.execute(
        select(Exercise).where(
            _visible(user.id), Exercise.name == name, Exercise.id != exercise_id
        )
    ).scalar_one_or_none()
    if clash:
        raise HTTPException(status_code=400, detail="An exercise with that name already exists")
    exercise.name = name
    exercise.muscle_group = body.muscle_group
    exercise.equipment = body.equipment
    exercise.grip = body.grip
    exercise.grip_width = body.grip_width
    exercise.attachment = body.attachment
    db.add(exercise)
    db.commit()
    return ExerciseOut(
        id=exercise.id,
        name=exercise.name,
        muscle_group=exercise.muscle_group,
        equipment=exercise.equipment,
        grip=exercise.grip,
        grip_width=exercise.grip_width,
        attachment=exercise.attachment,
        variant_of_id=exercise.variant_of_id,
        is_custom=True,
    )


@router.delete("/{exercise_id}")
def delete_exercise(
    exercise_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    exercise = db.get(Exercise, exercise_id)
    if exercise is None or exercise.owner_id != user.id:
        raise HTTPException(status_code=404, detail="Custom exercise not found")
    # Deleting would cascade through logged history — refuse instead
    uses = db.execute(
        select(func.count(WorkoutExercise.id)).where(
            WorkoutExercise.exercise_id == exercise_id
        )
    ).scalar()
    if uses:
        raise HTTPException(
            status_code=409,
            detail=f"Exercise appears in {uses} logged workout(s) — history would be lost",
        )
    db.delete(exercise)
    db.commit()
    return {"ok": True}
