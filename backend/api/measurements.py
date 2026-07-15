from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from backend.core.clock import utcnow
from backend.core.database import get_db
from backend.core.security import get_current_user
from backend.models import User
from backend.models.measurement import Measurement

router = APIRouter(prefix="/measurements", tags=["measurements"])

KINDS = [
    "Weight",
    "Body fat",
    "Neck",
    "Shoulders",
    "Chest",
    "Waist",
    "Hips",
    "Biceps",
    "Forearm",
    "Thigh",
    "Calf",
]


class MeasurementIn(BaseModel):
    kind: str
    value: float = Field(gt=0, lt=10000)
    measured_at: datetime | None = None


@router.get("")
def summary(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    latest_rows = db.execute(
        select(Measurement)
        .where(Measurement.user_id == user.id)
        .order_by(Measurement.kind, Measurement.measured_at.desc())
    ).scalars()
    latest: dict[str, Measurement] = {}
    counts: dict[str, int] = {}
    for m in latest_rows:
        counts[m.kind] = counts.get(m.kind, 0) + 1
        if m.kind not in latest:
            latest[m.kind] = m
    return [
        {
            "kind": kind,
            "count": counts.get(kind, 0),
            "latest": (
                {"value": latest[kind].value, "measured_at": latest[kind].measured_at}
                if kind in latest
                else None
            ),
        }
        for kind in KINDS
    ]


@router.post("")
def create(
    body: MeasurementIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if body.kind not in KINDS:
        raise HTTPException(status_code=400, detail="Unknown measurement kind")
    measured_at = body.measured_at or utcnow()
    if measured_at.tzinfo is not None:
        measured_at = measured_at.astimezone(timezone.utc).replace(tzinfo=None)
    m = Measurement(user_id=user.id, kind=body.kind, value=body.value, measured_at=measured_at)
    db.add(m)
    db.commit()
    return {"id": m.id, "kind": m.kind, "value": m.value, "measured_at": m.measured_at}


@router.get("/{kind}")
def history(
    kind: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if kind not in KINDS:
        raise HTTPException(status_code=404, detail="Unknown measurement kind")
    rows = db.execute(
        select(Measurement)
        .where(Measurement.user_id == user.id, Measurement.kind == kind)
        .order_by(Measurement.measured_at.desc())
    ).scalars()
    return [{"id": m.id, "value": m.value, "measured_at": m.measured_at} for m in rows]


@router.delete("/{measurement_id}")
def delete(
    measurement_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    m = db.get(Measurement, measurement_id)
    if m is None or m.user_id != user.id:
        raise HTTPException(status_code=404, detail="Measurement not found")
    db.delete(m)
    db.commit()
    return {"ok": True}
