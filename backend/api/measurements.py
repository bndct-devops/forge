from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from backend.core.clock import utcnow
from backend.core.database import get_db
from backend.core.security import get_current_user
from backend.models import User
from backend.models.measurement import Measurement
from backend.trend import change_over, rate_per_week, smooth

router = APIRouter(prefix="/measurements", tags=["measurements"])

KINDS = [
    "Weight",
    "Height",
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


@router.get("/{kind}/trend")
def trend(
    kind: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Smoothed trend for a measurement kind: per-entry trend values, the
    rate of change per week, and the 28-day change. Height is a constant,
    not a trend — 404 keeps it off the chart."""
    if kind not in KINDS or kind == "Height":
        raise HTTPException(status_code=404, detail="Unknown measurement kind")
    rows = (
        db.execute(
            select(Measurement)
            .where(Measurement.user_id == user.id, Measurement.kind == kind)
            .order_by(Measurement.measured_at)
        )
        .scalars()
        .all()
    )
    entries = [(m.measured_at, m.value) for m in rows]
    smoothed = smooth(entries)
    points = [
        {
            "measured_at": at,
            "actual": value,
            "trend": round(t, 2),
        }
        for (at, value), t in zip(entries, smoothed)
    ]
    rate = rate_per_week(entries, smoothed)
    change = change_over(entries, smoothed)
    # BMI riff: only for Weight, only when a height is on file (kg/m²; a
    # height logged in inches converts on the client before saving, so the
    # stored unit follows the user's weight unit — cm for kg users)
    height = db.execute(
        select(Measurement)
        .where(Measurement.user_id == user.id, Measurement.kind == "Height")
        .order_by(Measurement.measured_at.desc())
    ).scalars().first()
    bmi = None
    if kind == "Weight" and height is not None and height.value > 0 and smoothed and user.unit == "kg":
        bmi = round(smoothed[-1] / (height.value / 100) ** 2, 1)
    return {
        "points": points,
        "trend": round(smoothed[-1], 2) if smoothed else None,
        "rate_per_week": round(rate, 2) if rate is not None else None,
        "change_28d": round(change, 2) if change is not None else None,
        "bmi": bmi,
    }


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


# ——— Health Auto Export ingest ———————————————————————————————————————————
# The iOS "Health Auto Export" app POSTs HealthKit metrics as JSON on a
# schedule — the practical bridge for Apple Health data, since Apple offers
# no server-side API. Documented at /docs/webhooks-metrics.

INGEST_KINDS = {
    "weight_body_mass": "Weight",
    "body_fat_percentage": "Body fat",
    "lean_body_mass": None,  # recognised but not stored (no matching kind)
}


def _parse_ingest_date(raw: str) -> datetime | None:
    for fmt in ("%Y-%m-%d %H:%M:%S %z", "%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%d"):
        try:
            dt = datetime.strptime(raw, fmt)
            return dt.astimezone(timezone.utc).replace(tzinfo=None) if dt.tzinfo else dt
        except ValueError:
            continue
    return None


@router.post("/ingest")
def ingest(
    payload: dict,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Accepts Health Auto Export's JSON shape:
    {"data": {"metrics": [{"name": "weight_body_mass", "units": "kg",
                            "data": [{"date": "...", "qty": 82.4}]}]}}
    Duplicate timestamps (per kind, to the minute) are skipped, so repeated
    exports are idempotent."""
    metrics = (payload.get("data") or {}).get("metrics")
    if not isinstance(metrics, list):
        raise HTTPException(status_code=400, detail="Expected data.metrics[]")

    added = 0
    skipped = 0
    for metric in metrics:
        kind = INGEST_KINDS.get(str(metric.get("name", "")))
        if kind is None:
            skipped += len(metric.get("data") or [])
            continue
        for point in metric.get("data") or []:
            qty = point.get("qty")
            when = _parse_ingest_date(str(point.get("date", "")))
            if qty is None or when is None:
                skipped += 1
                continue
            value = float(qty)
            # Body fat may arrive as a 0–1 fraction; store percent
            if kind == "Body fat" and value <= 1:
                value = round(value * 100, 1)
            window_lo = when - timedelta(minutes=1)
            window_hi = when + timedelta(minutes=1)
            exists = db.execute(
                select(Measurement.id).where(
                    Measurement.user_id == user.id,
                    Measurement.kind == kind,
                    Measurement.measured_at >= window_lo,
                    Measurement.measured_at <= window_hi,
                )
            ).first()
            if exists:
                skipped += 1
                continue
            db.add(
                Measurement(user_id=user.id, kind=kind, value=value, measured_at=when)
            )
            added += 1
    db.commit()
    return {"added": added, "skipped": skipped}
