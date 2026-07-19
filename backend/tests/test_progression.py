"""Double progression and deload detection.
Documented at /docs/the-math — 'Progression & deload suggestions'.
"""
import pytest

from backend.api.workouts import _stalled, start_workout
from backend.models import Routine, RoutineExercise
from backend.schemas import WorkoutStart

from .conftest import log_workout, make_exercise


def make_routine(db, user, exercise, *, rep_min=6, rep_max=10, increment=None):
    r = Routine(owner_id=user.id, name="Test Routine")
    db.add(r)
    db.flush()
    db.add(
        RoutineExercise(
            routine_id=r.id,
            exercise_id=exercise.id,
            position=0,
            set_count=3,
            rep_min=rep_min,
            rep_max=rep_max,
            increment=increment,
        )
    )
    db.commit()
    return r


class _WE:
    """Dict-or-ORM adapter — start_workout returns the serialized workout."""

    def __init__(self, data):
        self.suggested_weight = data.get("suggested_weight")
        self.suggestion_kind = data.get("suggestion_kind")


def start_from(db, user, routine):
    w = start_workout(WorkoutStart(routine_id=routine.id), user=user, db=db)
    exercises = w["exercises"] if isinstance(w, dict) else w.exercises
    first = exercises[0]
    if isinstance(first, dict):
        return _WE(first)
    return first


class TestStalled:
    def test_three_identical_stuck_sessions(self):
        sessions = [[(80.0, 8), (80.0, 7)]] * 3
        assert _stalled(sessions, rep_max=10) == 80.0

    def test_fewer_than_three_sessions_is_not_a_stall(self):
        assert _stalled([[(80.0, 8)]] * 2, rep_max=10) is None

    def test_different_top_weights_is_not_a_stall(self):
        sessions = [[(82.5, 8)], [(80.0, 8)], [(80.0, 8)]]
        assert _stalled(sessions, rep_max=10) is None

    def test_one_session_hitting_target_breaks_the_stall(self):
        sessions = [[(80.0, 10), (80.0, 10)], [(80.0, 8)], [(80.0, 9)]]
        assert _stalled(sessions, rep_max=10) is None


class TestSuggestions:
    def test_progress_when_all_sets_hit_rep_max(self, db, user):
        bench = make_exercise(db)
        log_workout(db, user, days_ago=2, entries=[(bench, [(80, 10), (80, 10), (80, 10)])])
        we = start_from(db, user, make_routine(db, user, bench))
        assert we.suggested_weight == 82.5
        assert we.suggestion_kind == "progress"

    def test_custom_increment(self, db, user):
        bench = make_exercise(db)
        log_workout(db, user, days_ago=2, entries=[(bench, [(80, 10), (80, 10)])])
        we = start_from(db, user, make_routine(db, user, bench, increment=5))
        assert we.suggested_weight == 85

    def test_no_suggestion_mid_range(self, db, user):
        bench = make_exercise(db)
        log_workout(db, user, days_ago=2, entries=[(bench, [(80, 10), (80, 8)])])
        we = start_from(db, user, make_routine(db, user, bench))
        assert we.suggested_weight is None
        assert we.suggestion_kind is None

    def test_deload_after_three_stalled_sessions(self, db, user):
        bench = make_exercise(db)
        for days in (10, 6, 2):
            log_workout(db, user, days_ago=days, entries=[(bench, [(80, 8), (80, 7)])])
        we = start_from(db, user, make_routine(db, user, bench))
        assert we.suggestion_kind == "deload"
        # 80 × 0.9 = 72, rounded to the 2.5 step
        assert we.suggested_weight == 72.5

    def test_deload_respects_setting(self, db, user):
        user.deload_hints = False
        db.commit()
        bench = make_exercise(db)
        for days in (10, 6, 2):
            log_workout(db, user, days_ago=days, entries=[(bench, [(80, 8)])])
        we = start_from(db, user, make_routine(db, user, bench))
        assert we.suggestion_kind is None

    def test_no_rep_range_means_no_engine(self, db, user):
        bench = make_exercise(db)
        log_workout(db, user, days_ago=2, entries=[(bench, [(80, 10), (80, 10)])])
        we = start_from(db, user, make_routine(db, user, bench, rep_min=None, rep_max=None))
        assert we.suggested_weight is None

    def test_warmups_do_not_block_progression(self, db, user):
        bench = make_exercise(db)
        log_workout(
            db, user, days_ago=2,
            entries=[(bench, [{"weight": 40, "reps": 15, "is_warmup": True}, (80, 10), (80, 10)])],
        )
        we = start_from(db, user, make_routine(db, user, bench))
        assert we.suggestion_kind == "progress"
        assert we.suggested_weight == 82.5
