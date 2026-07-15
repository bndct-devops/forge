from datetime import datetime, timezone


def utcnow() -> datetime:
    """Naive UTC — SQLite round-trips naive datetimes, so store naive consistently."""
    return datetime.now(timezone.utc).replace(tzinfo=None)
