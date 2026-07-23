"""Weekly digest and daily weigh-in reminder over the existing Web Push
pipeline. The digest runs Sunday evenings (17:00 UTC tick or later); the
weigh-in reminder daily at the user's chosen hour, and only on days without
a logged weight. Documented at /docs/webhooks-metrics.
"""
import logging
import threading
import time
from datetime import date, datetime, timedelta

from sqlalchemy import select

from backend.core.clock import utcnow
from backend.core.database import SessionLocal
from backend.core.push import send_push
from backend.models import Measurement, PushSubscription, User, Workout
from backend.serializers import workout_totals

log = logging.getLogger("forge.digest")

DIGEST_HOUR_UTC = 17  # first hourly tick at/after this on Sundays


def _week_start(d: date) -> date:
    return d - timedelta(days=d.weekday())


def build_digest(db, user: User, today: date) -> str | None:
    """The digest line for the week containing `today`. None when there is
    nothing worth saying (no workouts in the last two weeks)."""
    since = _week_start(today) - timedelta(weeks=1)
    workouts = (
        db.execute(
            select(Workout).where(
                Workout.owner_id == user.id,
                Workout.finished_at.is_not(None),
                Workout.started_at >= since,
            )
        )
        .scalars()
        .all()
    )
    if not workouts:
        return None
    this_week = _week_start(today)
    cur = [w for w in workouts if _week_start(w.started_at.date()) == this_week]
    prev = [w for w in workouts if _week_start(w.started_at.date()) == since]
    cur_vol = sum(workout_totals(w)["total_volume"] for w in cur)
    prev_vol = sum(workout_totals(w)["total_volume"] for w in prev)
    prs = sum(workout_totals(w)["pr_count"] for w in cur)

    parts = [f"{len(cur)}/{user.weekly_goal} workouts", f"{round(cur_vol / 1000, 1)}k {user.unit}"]
    if prev_vol > 0 and cur_vol > 0:
        delta = round((cur_vol - prev_vol) / prev_vol * 100)
        parts[-1] += f" ({'+' if delta >= 0 else ''}{delta}%)"
    if prs:
        parts.append(f"{prs} PR{'s' if prs != 1 else ''}")
    return " · ".join(parts)


def _push_to_user(db, user: User, payload: dict) -> None:
    subs = (
        db.execute(select(PushSubscription).where(PushSubscription.user_id == user.id))
        .scalars()
        .all()
    )
    for sub in subs:
        alive = send_push(
            {"endpoint": sub.endpoint, "keys": {"p256dh": sub.p256dh, "auth": sub.auth}},
            payload,
        )
        if not alive:
            db.delete(sub)


def _send_digest(db, user: User, body: str) -> None:
    _push_to_user(
        db, user, {"title": "Your training week", "body": body, "tag": "weekly-digest"}
    )


def run_digests_if_due(now=None) -> int:
    """Hourly tick: Sunday, at/after the digest hour, once per user per week."""
    now = now or utcnow()
    if now.weekday() != 6 or now.hour < DIGEST_HOUR_UTC:
        return 0
    sent = 0
    db = SessionLocal()
    try:
        users = db.execute(select(User).where(User.weekly_digest.is_(True))).scalars().all()
        for user in users:
            if user.digest_sent_at and _week_start(user.digest_sent_at.date()) == _week_start(now.date()):
                continue  # already sent this week
            body = build_digest(db, user, now.date())
            if body is None:
                continue
            _send_digest(db, user, body)
            user.digest_sent_at = now
            sent += 1
        db.commit()
    finally:
        db.close()
    return sent


def run_weigh_in_reminders_if_due(now=None) -> int:
    """Hourly tick: at/after each user's chosen UTC hour, once per day — and
    a day with a logged weight needs no reminder at all."""
    now = now or utcnow()
    day_start = datetime(now.year, now.month, now.day)
    sent = 0
    db = SessionLocal()
    try:
        users = (
            db.execute(select(User).where(User.weigh_in_reminder.is_(True)))
            .scalars()
            .all()
        )
        for user in users:
            if now.hour < user.weigh_in_hour:
                continue
            if user.weigh_in_sent_at and user.weigh_in_sent_at >= day_start:
                continue  # already handled today
            logged_today = db.execute(
                select(Measurement.id).where(
                    Measurement.user_id == user.id,
                    Measurement.kind == "Weight",
                    Measurement.measured_at >= day_start,
                )
            ).first()
            if logged_today is None:
                _push_to_user(
                    db,
                    user,
                    {
                        "title": "Weigh-in",
                        "body": "30 seconds on the scale keeps the trend honest.",
                        "tag": "weigh-in",
                    },
                )
                sent += 1
            # Either way today is handled — a logged weight silences the ping
            user.weigh_in_sent_at = now
        db.commit()
    finally:
        db.close()
    return sent


def start_digest_scheduler() -> None:
    def loop() -> None:
        while True:
            try:
                run_digests_if_due()
            except Exception:
                log.exception("weekly digest failed")
            try:
                run_weigh_in_reminders_if_due()
            except Exception:
                log.exception("weigh-in reminder failed")
            time.sleep(3600)

    threading.Thread(target=loop, name="forge-digest", daemon=True).start()
