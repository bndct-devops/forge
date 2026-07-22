"""Offline sync — /workouts/sync upserts a full client document by
(owner, client_id). Replays must never duplicate, finishes run the same
pipeline as /finish, and backdated offline finishes keep PR flags
chronologically correct."""
from datetime import timedelta

import pytest
from fastapi import HTTPException
from sqlalchemy import select

from backend.api.workouts import sync_workout
from backend.models import SetEntry, Workout
from backend.schemas import SyncExerciseIn, SyncSetIn, WorkoutSyncIn

from .conftest import FROZEN_NOW, log_workout, make_exercise


def _doc(exercise, *, client_id="test-client-0001", finished=False, weight=100.0,
         started_at=FROZEN_NOW, completed=True, server_id=None):
    return WorkoutSyncIn(
        client_id=client_id,
        id=server_id,
        name="Offline Session",
        started_at=started_at,
        finished_at=started_at + timedelta(minutes=45) if finished else None,
        exercises=[
            SyncExerciseIn(
                exercise_id=exercise.id,
                position=0,
                sets=[
                    SyncSetIn(position=0, weight=weight, reps=5, is_completed=completed),
                    SyncSetIn(position=1, weight=weight, reps=5, is_completed=completed),
                ],
            )
        ],
    )


def test_sync_creates_then_updates_active(db, user):
    ex = make_exercise(db)
    res = sync_workout(_doc(ex), user, db)
    assert res["finish"] is None
    assert res["workout"]["client_id"] == "test-client-0001"
    first_id = res["workout"]["id"]

    # Replaying with a change updates the same row — no duplicate
    res2 = sync_workout(_doc(ex, weight=105.0), user, db)
    assert res2["workout"]["id"] == first_id
    assert db.execute(select(Workout).where(Workout.owner_id == user.id)).scalars().all()[0].id == first_id
    weights = {s.weight for s in db.execute(select(SetEntry)).scalars()}
    assert weights == {105.0}


def test_sync_finish_computes_prs_and_is_idempotent(db, user):
    ex = make_exercise(db)
    log_workout(db, user, days_ago=7, entries=[(ex, [(90.0, 5)])])

    res = sync_workout(_doc(ex, finished=True, weight=100.0), user, db)
    assert res["workout"] is None
    finish = res["finish"]
    assert finish["total_sets"] == 2
    assert any(p["kind"] == "weight" and p["value"] == 100.0 for p in finish["prs"])

    # Replay of the same finished document: same workout, still one row
    res2 = sync_workout(_doc(ex, finished=True, weight=100.0), user, db)
    assert res2["finish"]["id"] == finish["id"]
    finished = db.execute(
        select(Workout).where(Workout.owner_id == user.id, Workout.finished_at.is_not(None))
    ).scalars().all()
    assert len(finished) == 2  # the seeded history workout + the synced one


def test_backdated_finish_recomputes_prs_chronologically(db, user):
    ex = make_exercise(db)
    # Existing workout 2 days ago hit 100 kg and is flagged as the PR
    later = log_workout(db, user, days_ago=2, entries=[(ex, [(100.0, 5)])])
    from backend.serializers import recompute_prs

    recompute_prs(db, user.id)

    # Offline session from 5 days ago arrives late with 110 kg
    res = sync_workout(
        _doc(ex, finished=True, weight=110.0, started_at=FROZEN_NOW - timedelta(days=5)),
        user,
        db,
    )
    assert res["finish"] is not None
    db.expire_all()
    later_sets = [s for we in later.exercises for s in we.sets]
    # The later 100 kg lift is no longer a PR — the offline 110 kg predates it
    assert not any(s.is_pr for s in later_sets)


def test_sync_active_conflicts_with_other_active(db, user):
    ex = make_exercise(db)
    sync_workout(_doc(ex, client_id="device-a-000001"), user, db)
    with pytest.raises(HTTPException) as e:
        sync_workout(_doc(ex, client_id="device-b-000001"), user, db)
    assert e.value.status_code == 409


def test_sync_finish_with_nothing_completed_creates_nothing(db, user):
    ex = make_exercise(db)
    res = sync_workout(_doc(ex, finished=True, completed=False), user, db)
    assert res == {"workout": None, "finish": None}
    assert db.execute(select(Workout).where(Workout.owner_id == user.id)).scalars().all() == []


def test_sync_adopts_server_id_workout(db, user):
    """A workout started online (server id, no client_id) that went dirty
    offline syncs onto the same row and gains the client_id."""
    ex = make_exercise(db)
    w = Workout(owner_id=user.id, name="Online Start", started_at=FROZEN_NOW)
    db.add(w)
    db.commit()

    res = sync_workout(_doc(ex, server_id=w.id), user, db)
    assert res["workout"]["id"] == w.id
    db.expire_all()
    assert w.client_id == "test-client-0001"
    assert len(w.exercises) == 1
