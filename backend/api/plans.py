from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from backend.api.routines import _serialize
from backend.core.database import get_db
from backend.core.security import get_current_user
from backend.models import Exercise, Routine, RoutineExercise, User
from backend.plans_catalog import PLANS

router = APIRouter(prefix="/plans", tags=["plans"])


@router.get("")
def list_plans():
    return [
        {
            "key": plan["key"],
            "name": plan["name"],
            "description": plan["description"],
            "routines": [
                {
                    "name": routine["name"],
                    "exercises": [
                        {"name": name, "set_count": sets} for name, sets, _rest in routine["exercises"]
                    ],
                }
                for routine in plan["routines"]
            ],
        }
        for plan in PLANS
    ]


@router.post("/{key}/adopt")
def adopt_plan(
    key: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    plan = next((p for p in PLANS if p["key"] == key), None)
    if plan is None:
        raise HTTPException(status_code=404, detail="Plan not found")

    seed_by_name = {
        e.name: e
        for e in db.execute(select(Exercise).where(Exercise.owner_id.is_(None))).scalars()
    }
    max_pos = db.execute(
        select(func.coalesce(func.max(Routine.position), -1)).where(Routine.owner_id == user.id)
    ).scalar()

    created = []
    for offset, routine_spec in enumerate(plan["routines"]):
        routine = Routine(
            owner_id=user.id, name=routine_spec["name"], position=max_pos + 1 + offset
        )
        routine.exercises = [
            RoutineExercise(
                exercise_id=seed_by_name[name].id,
                position=i,
                set_count=sets,
                rest_seconds=rest,
            )
            for i, (name, sets, rest) in enumerate(routine_spec["exercises"])
            if name in seed_by_name
        ]
        db.add(routine)
        created.append(routine)
    db.commit()
    return [_serialize(db, r) for r in created]
