from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from backend.core.database import get_db
from backend.core.security import get_current_user
from backend.models import Exercise, Routine, RoutineExercise, User, Workout
from backend.schemas import RoutineIn

router = APIRouter(prefix="/routines", tags=["routines"])


def _serialize(db: Session, routine: Routine, last_performed=None) -> dict:
    exercises = []
    for re_ in routine.exercises:
        exercise = db.get(Exercise, re_.exercise_id)
        if exercise is None:
            continue
        exercises.append(
            {
                "exercise_id": re_.exercise_id,
                "name": exercise.name,
                "muscle_group": exercise.muscle_group,
                "equipment": exercise.equipment,
                "position": re_.position,
                "set_count": re_.set_count,
                "rest_seconds": re_.rest_seconds,
                "superset_with_next": re_.superset_with_next,
                "rep_min": re_.rep_min,
                "rep_max": re_.rep_max,
                "increment": re_.increment,
            }
        )
    return {
        "id": routine.id,
        "name": routine.name,
        "last_performed": last_performed,
        "exercises": exercises,
    }


def _get_own(db: Session, user: User, routine_id: int) -> Routine:
    routine = db.get(Routine, routine_id)
    if routine is None or routine.owner_id != user.id:
        raise HTTPException(status_code=404, detail="Routine not found")
    return routine


@router.get("")
def list_routines(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    routines = db.execute(
        select(Routine)
        .where(Routine.owner_id == user.id)
        .order_by(Routine.position, Routine.created_at)
    ).scalars()
    # "Last performed" matches finished workouts by name — workouts started
    # from a template inherit its name unless renamed
    last_by_name = dict(
        db.execute(
            select(Workout.name, func.max(Workout.started_at))
            .where(Workout.owner_id == user.id, Workout.finished_at.is_not(None))
            .group_by(Workout.name)
        ).all()
    )
    return [_serialize(db, r, last_by_name.get(r.name)) for r in routines]


@router.post("")
def create_routine(
    body: RoutineIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    max_pos = db.execute(
        select(func.coalesce(func.max(Routine.position), -1)).where(Routine.owner_id == user.id)
    ).scalar()
    routine = Routine(owner_id=user.id, name=body.name.strip(), position=max_pos + 1)
    routine.exercises = [
        RoutineExercise(
            exercise_id=e.exercise_id,
            position=i,
            set_count=e.set_count,
            rest_seconds=e.rest_seconds,
            superset_with_next=e.superset_with_next,
            rep_min=e.rep_min,
            rep_max=e.rep_max,
            increment=e.increment,
        )
        for i, e in enumerate(body.exercises)
    ]
    db.add(routine)
    db.commit()
    return _serialize(db, routine)


@router.get("/{routine_id}")
def get_routine(
    routine_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    return _serialize(db, _get_own(db, user, routine_id))


@router.put("/{routine_id}")
def update_routine(
    routine_id: int,
    body: RoutineIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    routine = _get_own(db, user, routine_id)
    routine.name = body.name.strip()
    routine.exercises = [
        RoutineExercise(
            exercise_id=e.exercise_id,
            position=i,
            set_count=e.set_count,
            rest_seconds=e.rest_seconds,
            superset_with_next=e.superset_with_next,
            rep_min=e.rep_min,
            rep_max=e.rep_max,
            increment=e.increment,
        )
        for i, e in enumerate(body.exercises)
    ]
    db.add(routine)
    db.commit()
    return _serialize(db, routine)


@router.delete("/{routine_id}")
def delete_routine(
    routine_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    routine = _get_own(db, user, routine_id)
    db.delete(routine)
    db.commit()
    return {"ok": True}
