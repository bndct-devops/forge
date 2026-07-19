"""Periodization programs: create from a scheme, get the next session's
prescription, start it as a live workout. State advances when a program
workout is *finished* (see workouts.finish_workout), so cancelling a
session never burns it.
"""
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from backend.core.database import get_db
from backend.core.security import get_current_user
from backend.models import Exercise, Program, ProgramLift, SetEntry, User, Workout, WorkoutExercise
from backend.program_schemes import SCHEMES, cycle_length, prescription
from backend.serializers import serialize_workout

router = APIRouter(prefix="/programs", tags=["programs"])


class ProgramLiftIn(BaseModel):
    exercise_id: int
    training_max: float = Field(gt=0, lt=1000)
    increment: float = Field(default=2.5, gt=0, le=50)


class ProgramIn(BaseModel):
    name: str = Field(min_length=1, max_length=128)
    scheme: str
    rounding: float = Field(default=2.5, gt=0, le=25)
    lifts: list[ProgramLiftIn] = Field(min_length=1, max_length=10)


class ProgramLiftPatch(BaseModel):
    id: int
    training_max: float | None = Field(default=None, gt=0, lt=1000)
    increment: float | None = Field(default=None, gt=0, le=50)


class ProgramPatch(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=128)
    current_week: int | None = Field(default=None, ge=1, le=8)
    lift_pointer: int | None = Field(default=None, ge=0)
    lifts: list[ProgramLiftPatch] | None = None


def _get_own(db: Session, user: User, program_id: int) -> Program:
    p = db.get(Program, program_id)
    if p is None or p.owner_id != user.id:
        raise HTTPException(status_code=404, detail="Program not found")
    return p


def _serialize(db: Session, p: Program) -> dict:
    exercises = {
        e.id: e
        for e in db.execute(
            select(Exercise).where(Exercise.id.in_([l.exercise_id for l in p.lifts]))
        ).scalars()
    }
    next_lift = p.lifts[p.lift_pointer % len(p.lifts)] if p.lifts else None
    return {
        "id": p.id,
        "name": p.name,
        "scheme": p.scheme,
        "scheme_name": SCHEMES[p.scheme]["name"],
        "rounding": p.rounding,
        "current_week": p.current_week,
        "cycle_length": cycle_length(p.scheme),
        "cycle_number": p.cycle_number,
        "lift_pointer": p.lift_pointer,
        "lifts": [
            {
                "id": l.id,
                "exercise_id": l.exercise_id,
                "name": exercises[l.exercise_id].name if l.exercise_id in exercises else "?",
                "training_max": l.training_max,
                "increment": l.increment,
            }
            for l in p.lifts
        ],
        "next": (
            {
                "lift_id": next_lift.id,
                "exercise_id": next_lift.exercise_id,
                "exercise_name": (
                    exercises[next_lift.exercise_id].name
                    if next_lift.exercise_id in exercises
                    else "?"
                ),
                "week": p.current_week,
                "sets": prescription(
                    p.scheme, p.current_week, next_lift.training_max, p.rounding
                ),
            }
            if next_lift
            else None
        ),
    }


@router.get("/schemes")
def schemes():
    """The scheme definitions, verbatim — transparency endpoint."""
    return {
        key: {
            "name": s["name"],
            "description": s["description"],
            "weeks": [
                [{"pct": pct, "reps": reps, "amrap": amrap} for pct, reps, amrap in week]
                for week in s["weeks"]
            ],
        }
        for key, s in SCHEMES.items()
    }


@router.get("")
def list_programs(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    programs = (
        db.execute(
            select(Program).where(Program.owner_id == user.id).order_by(Program.created_at)
        )
        .scalars()
        .all()
    )
    return [_serialize(db, p) for p in programs]


@router.post("")
def create_program(
    body: ProgramIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)
):
    if body.scheme not in SCHEMES:
        raise HTTPException(status_code=400, detail="Unknown scheme")
    for lift in body.lifts:
        ex = db.get(Exercise, lift.exercise_id)
        if ex is None:
            raise HTTPException(status_code=404, detail="Exercise not found")
    p = Program(
        owner_id=user.id, name=body.name, scheme=body.scheme, rounding=body.rounding
    )
    p.lifts = [
        ProgramLift(
            exercise_id=l.exercise_id,
            position=i,
            training_max=l.training_max,
            increment=l.increment,
        )
        for i, l in enumerate(body.lifts)
    ]
    db.add(p)
    db.commit()
    return _serialize(db, p)


@router.patch("/{program_id}")
def update_program(
    program_id: int,
    body: ProgramPatch,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    p = _get_own(db, user, program_id)
    if body.name is not None:
        p.name = body.name
    if body.current_week is not None:
        if body.current_week > cycle_length(p.scheme):
            raise HTTPException(status_code=400, detail="Week beyond the scheme's cycle")
        p.current_week = body.current_week
    if body.lift_pointer is not None:
        if body.lift_pointer >= len(p.lifts):
            raise HTTPException(status_code=400, detail="Pointer beyond the lift list")
        p.lift_pointer = body.lift_pointer
    for patch in body.lifts or []:
        lift = next((l for l in p.lifts if l.id == patch.id), None)
        if lift is None:
            raise HTTPException(status_code=404, detail="Program lift not found")
        if patch.training_max is not None:
            lift.training_max = patch.training_max
        if patch.increment is not None:
            lift.increment = patch.increment
    db.commit()
    return _serialize(db, p)


@router.delete("/{program_id}")
def delete_program(
    program_id: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)
):
    p = _get_own(db, user, program_id)
    db.delete(p)
    db.commit()
    return {"ok": True}


@router.post("/{program_id}/start-workout")
def start_program_workout(
    program_id: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)
):
    p = _get_own(db, user, program_id)
    if not p.lifts:
        raise HTTPException(status_code=400, detail="Program has no lifts")
    active = db.execute(
        select(Workout).where(Workout.owner_id == user.id, Workout.finished_at.is_(None))
    ).scalar_one_or_none()
    if active is not None:
        raise HTTPException(status_code=409, detail="A workout is already in progress")

    lift = p.lifts[p.lift_pointer % len(p.lifts)]
    exercise = db.get(Exercise, lift.exercise_id)
    sets = prescription(p.scheme, p.current_week, lift.training_max, p.rounding)

    w = Workout(
        owner_id=user.id,
        name=f"{p.name} — {exercise.name} (W{p.current_week})",
        program_id=p.id,
        program_lift_id=lift.id,
    )
    we = WorkoutExercise(exercise_id=lift.exercise_id, position=0)
    # Weight AND reps prefilled: logging a prescribed set is one tap; the
    # AMRAP set's reps get corrected upward by whatever actually happened.
    we.sets = [
        SetEntry(position=i, weight=s["weight"], reps=s["reps"])
        for i, s in enumerate(sets)
    ]
    w.exercises = [we]
    db.add(w)
    db.commit()
    data = serialize_workout(db, w)
    data["program"] = {
        "id": p.id,
        "week": p.current_week,
        "sets": sets,
        "scheme_name": SCHEMES[p.scheme]["name"],
    }
    return data


def advance_program(db: Session, workout: Workout) -> None:
    """Called from finish_workout for program-generated workouts. Advances
    the lift pointer; wraps into week advancement; wraps into a new cycle
    with training-max bumps. Deterministic and documented in the docs."""
    if workout.program_id is None:
        return
    p = db.get(Program, workout.program_id)
    if p is None or not p.lifts:
        return
    p.lift_pointer += 1
    if p.lift_pointer >= len(p.lifts):
        p.lift_pointer = 0
        p.current_week += 1
        if p.current_week > cycle_length(p.scheme):
            p.current_week = 1
            p.cycle_number += 1
            for lift in p.lifts:
                lift.training_max = round(lift.training_max + lift.increment, 2)
