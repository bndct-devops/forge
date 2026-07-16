"""Login brute-force guard — in-memory, per-account and per-source-IP.

Per-account lockout kicks in first (protects each user even when the proxy
hides real client IPs); the IP threshold is higher and catches username
spraying. Counters decay after 15 quiet minutes. In-memory is fine here:
a restart resetting lockouts is harmless, and the app runs single-process.
"""
import threading
import time

_WINDOW = 900  # quiet seconds before a counter resets
_USER_THRESHOLD = 5
_IP_THRESHOLD = 30
_MAX_LOCK = 600

_lock = threading.Lock()
_entries: dict[str, dict] = {}


def _entry(key: str) -> dict:
    now = time.time()
    e = _entries.get(key)
    if e is None or now - e["last"] > _WINDOW:
        e = {"failures": 0, "locked_until": 0.0, "last": now}
        _entries[key] = e
    return e


def _apply_failure(key: str, threshold: int) -> None:
    e = _entry(key)
    e["failures"] += 1
    e["last"] = time.time()
    if e["failures"] >= threshold:
        penalty = min(_MAX_LOCK, 30 * 2 ** (e["failures"] - threshold))
        e["locked_until"] = time.time() + penalty


def retry_after(username: str, ip: str) -> int:
    """Seconds until another attempt is allowed; 0 = go ahead."""
    now = time.time()
    with _lock:
        remaining = 0.0
        for key in (f"u:{username.lower()}", f"ip:{ip}"):
            e = _entries.get(key)
            if e and e["locked_until"] > now and now - e["last"] <= _WINDOW:
                remaining = max(remaining, e["locked_until"] - now)
    return int(remaining + 0.999) if remaining > 0 else 0


def record_failure(username: str, ip: str) -> None:
    with _lock:
        _apply_failure(f"u:{username.lower()}", _USER_THRESHOLD)
        _apply_failure(f"ip:{ip}", _IP_THRESHOLD)


def record_success(username: str, ip: str) -> None:
    with _lock:
        _entries.pop(f"u:{username.lower()}", None)
        _entries.pop(f"ip:{ip}", None)
