"""The two oldest promises: Epley e1RM and PR detection.
Documented at /docs/the-math — 'Estimated one-rep max' and 'Personal records'.
"""
from backend.serializers import detect_prs, epley_1rm, recompute_prs, workout_totals
from backend.models import SetEntry

from .conftest import log_workout, make_exercise


def test_epley_basic():
    assert epley_1rm(100, 10) == 100 * (1 + 10 / 30)
    assert epley_1rm(80, 8) == 80 * (1 + 8 / 30)


def test_epley_single_is_the_weight():
    assert epley_1rm(140, 1) == 140


def test_epley_zero_or_negative_reps():
    assert epley_1rm(100, 0) == 0.0
    assert epley_1rm(100, -3) == 0.0


def _set(weight, reps, *, warmup=False, completed=True):
    return SetEntry(
        position=0, weight=weight, reps=reps, is_completed=completed, is_warmup=warmup
    )


def fresh_bests():
    return {"weight": 0.0, "one_rm": 0.0, "bw_reps": 0}


def test_weight_pr_detected():
    sets = [_set(100, 5)]
    prs = detect_prs("Bench Press", sets, fresh_bests())
    assert sets[0].is_pr is True
    assert [p["kind"] for p in prs] == ["weight"]


def test_e1rm_pr_without_weight_pr():
    # 100×1 sets weight best 100, e1RM best 100.
    bests = fresh_bests()
    detect_prs("Bench", [_set(100, 1)], bests)
    # 90×10 → e1RM 120: no weight PR, but an e1RM PR.
    sets = [_set(90, 10)]
    prs = detect_prs("Bench", sets, bests)
    assert sets[0].is_pr is True
    assert [p["kind"] for p in prs] == ["1rm"]


def test_warmups_never_pr():
    sets = [_set(200, 5, warmup=True)]
    prs = detect_prs("Bench", sets, fresh_bests())
    assert prs == []
    assert sets[0].is_pr is False


def test_incomplete_sets_never_pr():
    sets = [_set(200, 5, completed=False)]
    assert detect_prs("Bench", sets, fresh_bests()) == []


def test_bodyweight_reps_pr():
    bests = fresh_bests()
    prs = detect_prs("Pull-Up", [_set(None, 12)], bests)
    assert [p["kind"] for p in prs] == ["reps"]
    assert bests["bw_reps"] == 12
    # Fewer reps later: no PR
    sets = [_set(None, 10)]
    assert detect_prs("Pull-Up", sets, bests) == []
    assert sets[0].is_pr is False


def test_recompute_is_chronological(db, user):
    """Backdating a heavier workout must strip the newer workout's PR flag."""
    bench = make_exercise(db)
    w_new = log_workout(db, user, days_ago=5, entries=[(bench, [(100, 5)])])
    recompute_prs(db, user.id)
    db.commit()
    new_set = db.query(SetEntry).join(
        SetEntry.__table__.metadata.tables["workout_exercises"]
    ).filter_by(workout_id=w_new.id).first()
    assert new_set.is_pr is True

    # Now insert an OLDER workout that already lifted more.
    log_workout(db, user, days_ago=30, entries=[(bench, [(110, 5)])])
    recompute_prs(db, user.id)
    db.commit()
    db.expire_all()
    flags = {
        w.started_at.date(): [s.is_pr for we in w.exercises for s in we.sets]
        for w in db.query(type(w_new)).all()
    }
    older_day, newer_day = sorted(flags)
    assert flags[older_day] == [True]   # the backdated 110 holds the record
    assert flags[newer_day] == [False]  # 100 five days ago is no longer a PR


def test_workout_totals_exclude_warmups(db, user):
    bench = make_exercise(db)
    w = log_workout(
        db, user, days_ago=1,
        entries=[(bench, [{"weight": 60, "reps": 10, "is_warmup": True}, (100, 5), (100, 5)])],
    )
    totals = workout_totals(w)
    assert totals["total_sets"] == 2
    assert totals["total_volume"] == 1000.0
