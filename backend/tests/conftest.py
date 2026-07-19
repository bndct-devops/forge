"""Shared test infrastructure: an isolated SQLite database per test run and
factories for building synthetic training histories.

The docs site (forge.bndct.sh/docs/the-math) documents every formula as a
contract; these tests are the enforcement. When a formula changes, the docs
page and the corresponding test change in the same commit.
"""
import os
import tempfile
from datetime import datetime, timedelta

import pytest

# Point the app at a throwaway data dir BEFORE any backend import constructs
# the engine.
os.environ["FORGE_DATA_DIR"] = tempfile.mkdtemp(prefix="forge-tests-")

from backend.core.database import Base, SessionLocal, engine  # noqa: E402
import backend.models  # noqa: E402,F401 — registers all tables
from backend.models import Exercise, SetEntry, User, Workout, WorkoutExercise  # noqa: E402

Base.metadata.create_all(engine)

# A fixed "now" — tests monkeypatch the modules' utcnow to this. Monday.
FROZEN_NOW = datetime(2026, 7, 20, 12, 0, 0)
TODAY = FROZEN_NOW.date()


@pytest.fixture()
def db():
    session = SessionLocal()
    yield session
    session.rollback()
    # Wipe between tests — cheap at this scale, keeps tests independent
    for table in reversed(Base.metadata.sorted_tables):
        session.execute(table.delete())
    session.commit()
    session.close()


@pytest.fixture()
def user(db):
    u = User(username="tester", hashed_password="x")
    db.add(u)
    db.commit()
    return u


@pytest.fixture()
def freeze_now(monkeypatch):
    """Freeze utcnow in every module that imported it by name."""
    for mod in ("backend.api.stats", "backend.api.workouts", "backend.core.clock"):
        try:
            monkeypatch.setattr(f"{mod}.utcnow", lambda: FROZEN_NOW)
        except AttributeError:
            pass
    return FROZEN_NOW


def make_exercise(db, name="Bench Press", muscle_group="Chest", equipment="Barbell"):
    ex = Exercise(name=name, muscle_group=muscle_group, equipment=equipment)
    db.add(ex)
    db.commit()
    return ex


def log_workout(
    db,
    user,
    days_ago,
    entries,
    *,
    hour=18,
    duration_minutes=60,
    rest_between_sets=None,
    now=FROZEN_NOW,
):
    """Create a finished workout `days_ago` days before FROZEN_NOW.

    entries: list of (exercise, sets) where sets is a list of set specs —
    either (weight, reps) tuples or dicts with keys weight/reps/is_warmup/
    rpe/set_type. rest_between_sets (seconds) populates completed_at stamps.
    """
    start = (now - timedelta(days=days_ago)).replace(hour=hour, minute=0, second=0)
    w = Workout(
        owner_id=user.id,
        name="Test Workout",
        started_at=start,
        finished_at=start + timedelta(minutes=duration_minutes),
    )
    db.add(w)
    db.flush()
    for pos, (ex, sets) in enumerate(entries):
        we = WorkoutExercise(workout_id=w.id, exercise_id=ex.id, position=pos)
        db.add(we)
        db.flush()
        stamp = start + timedelta(minutes=2)
        for i, spec in enumerate(sets):
            if isinstance(spec, dict):
                weight, reps = spec.get("weight"), spec.get("reps")
                extra = {k: v for k, v in spec.items() if k not in ("weight", "reps")}
            else:
                weight, reps = spec
                extra = {}
            se = SetEntry(
                workout_exercise_id=we.id,
                position=i,
                weight=weight,
                reps=reps,
                is_completed=True,
                completed_at=stamp,
                **extra,
            )
            db.add(se)
            if rest_between_sets is not None:
                stamp = stamp + timedelta(seconds=rest_between_sets)
            else:
                stamp = stamp + timedelta(seconds=120)
    db.commit()
    return w
