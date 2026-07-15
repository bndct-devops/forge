"""Push subscriptions + server-scheduled rest-timer alerts.

The client tells us when the current rest ends; a timer thread fires the push
at that moment so the alert lands even with the phone locked. Pending timers
are in-memory only — a rest is a 1-5 minute horizon, so losing them across a
server restart is acceptable."""
import threading
from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from backend.core.clock import utcnow
from backend.core.database import SessionLocal, get_db
from backend.core.push import public_key_b64, send_push
from backend.core.security import get_current_user
from backend.models import User
from backend.models.push_subscription import PushSubscription

router = APIRouter(prefix="/push", tags=["push"])

_timers: dict[int, threading.Timer] = {}
_timers_lock = threading.Lock()


class SubscriptionKeys(BaseModel):
    p256dh: str
    auth: str


class SubscribeIn(BaseModel):
    endpoint: str
    keys: SubscriptionKeys


class UnsubscribeIn(BaseModel):
    endpoint: str


class RestTimerIn(BaseModel):
    ends_at: datetime | None  # null cancels


@router.get("/public-key")
def public_key():
    return {"key": public_key_b64()}


@router.post("/subscribe")
def subscribe(
    body: SubscribeIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    existing = db.execute(
        select(PushSubscription).where(PushSubscription.endpoint == body.endpoint)
    ).scalar_one_or_none()
    if existing:
        existing.user_id = user.id
        existing.p256dh = body.keys.p256dh
        existing.auth = body.keys.auth
        db.add(existing)
    else:
        db.add(
            PushSubscription(
                user_id=user.id,
                endpoint=body.endpoint,
                p256dh=body.keys.p256dh,
                auth=body.keys.auth,
            )
        )
    db.commit()
    return {"ok": True}


@router.post("/unsubscribe")
def unsubscribe(
    body: UnsubscribeIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    sub = db.execute(
        select(PushSubscription).where(
            PushSubscription.endpoint == body.endpoint,
            PushSubscription.user_id == user.id,
        )
    ).scalar_one_or_none()
    if sub:
        db.delete(sub)
        db.commit()
    return {"ok": True}


def _fire_rest_push(user_id: int) -> None:
    db = SessionLocal()
    try:
        subs = (
            db.execute(select(PushSubscription).where(PushSubscription.user_id == user_id))
            .scalars()
            .all()
        )
        for sub in subs:
            alive = send_push(
                {
                    "endpoint": sub.endpoint,
                    "keys": {"p256dh": sub.p256dh, "auth": sub.auth},
                },
                {"title": "Rest over", "body": "Time for your next set.", "tag": "rest-timer"},
            )
            if not alive:
                db.delete(sub)
        db.commit()
    finally:
        db.close()
    with _timers_lock:
        _timers.pop(user_id, None)


@router.post("/rest-timer")
def schedule_rest_push(
    body: RestTimerIn,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    with _timers_lock:
        existing = _timers.pop(user.id, None)
        if existing:
            existing.cancel()
        if body.ends_at is None:
            return {"scheduled": False}
        has_subs = (
            db.execute(
                select(PushSubscription.id).where(PushSubscription.user_id == user.id).limit(1)
            ).scalar()
            is not None
        )
        if not has_subs:
            return {"scheduled": False}
        ends_at = body.ends_at
        if ends_at.tzinfo is not None:
            ends_at = ends_at.astimezone(timezone.utc).replace(tzinfo=None)
        delay = (ends_at - utcnow()).total_seconds()
        if delay <= 0 or delay > 3600:
            return {"scheduled": False}
        timer = threading.Timer(delay, _fire_rest_push, args=[user.id])
        timer.daemon = True
        timer.start()
        _timers[user.id] = timer
    return {"scheduled": True}
