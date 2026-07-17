"""Outbound webhook on finished workouts — fire-and-forget with an optional
HMAC-SHA256 signature so the receiver can verify origin."""
import hashlib
import hmac
import json
import logging
import threading
import urllib.request

from backend.models import User, Workout
from backend.serializers import workout_totals

log = logging.getLogger("forge.webhooks")
TIMEOUT = 5


def _payload(workout: Workout, source: str) -> dict:
    totals = workout_totals(workout)
    duration = (
        int((workout.finished_at - workout.started_at).total_seconds())
        if workout.finished_at
        else 0
    )
    return {
        "event": "workout.finished",
        "source": source,  # 'app' | 'api'
        "workout": {
            "id": workout.id,
            "name": workout.name,
            "started_at": workout.started_at.isoformat() + "Z",
            "finished_at": workout.finished_at.isoformat() + "Z"
            if workout.finished_at
            else None,
            "duration_seconds": duration,
            **totals,
        },
    }


def _post(url: str, secret: str | None, body: bytes) -> None:
    headers = {"Content-Type": "application/json", "User-Agent": "Forge-Webhook"}
    if secret:
        headers["X-Forge-Signature"] = (
            "sha256=" + hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()
        )
    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    try:
        urllib.request.urlopen(req, timeout=TIMEOUT)
    except Exception as e:
        log.warning("webhook delivery to %s failed: %s", url, e)


def fire_webhook(user: User, workout: Workout, source: str) -> None:
    """Non-blocking; reads what it needs before the request cycle ends."""
    url = user.webhook_url
    if not url:
        return
    body = json.dumps(_payload(workout, source)).encode()
    threading.Thread(
        target=_post, args=(url, user.webhook_secret, body), daemon=True
    ).start()
