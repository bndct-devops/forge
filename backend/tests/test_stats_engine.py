"""The stats/analysis engine — streaks, nudges, and every Trends formula.
Documented at /docs/the-math. Each test states the promise it enforces.

All tests freeze 'today' to FROZEN_NOW (a Monday, 12:00 UTC) and call the
stats endpoint function directly.
"""
import pytest

from backend.api.stats import stats
from backend.models import Measurement

from .conftest import FROZEN_NOW, log_workout, make_exercise


@pytest.fixture()
def get_stats(db, user, freeze_now):
    def _run(tz_offset=0):
        return stats(tz_offset=tz_offset, user=user, db=db)

    return _run


def bw_set(e1rm):
    """A (weight, reps) pair whose Epley e1RM is exactly `e1rm` (reps=10)."""
    return (e1rm * 0.75, 10)


class TestStreak:
    def test_streak_survives_an_untrained_current_week(self, db, user, get_stats):
        bench = make_exercise(db)
        # Trained the three previous weeks (Wednesdays), nothing yet this week
        for days in (5, 12, 19):
            log_workout(db, user, days_ago=days, entries=[(bench, [(80, 5)])])
        assert get_stats()["streak_weeks"] == 3

    def test_gap_breaks_streak(self, db, user, get_stats):
        bench = make_exercise(db)
        for days in (5, 12, 26):  # week -3 is missing
            log_workout(db, user, days_ago=days, entries=[(bench, [(80, 5)])])
        assert get_stats()["streak_weeks"] == 2

    def test_longest_streak_reported(self, db, user, get_stats):
        bench = make_exercise(db)
        for days in (5, 12, 26, 33, 40, 47):  # runs of 2 and 4
            log_workout(db, user, days_ago=days, entries=[(bench, [(80, 5)])])
        assert get_stats()["extras"]["longest_streak_weeks"] == 4


class TestNudges:
    def test_quiet_group_in_rotation_is_nudged(self, db, user, get_stats):
        bench = make_exercise(db, "Bench Press", "Chest")
        squat = make_exercise(db, "Back Squat", "Legs")
        log_workout(db, user, days_ago=1, entries=[(bench, [(80, 5)])])
        log_workout(db, user, days_ago=10, entries=[(squat, [(100, 5)])])
        nudges = get_stats()["nudges"]
        assert [n["group"] for n in nudges] == ["Legs"]
        assert nudges[0]["days"] == 10

    def test_group_never_trained_is_not_nudged(self, db, user, get_stats):
        bench = make_exercise(db, "Bench Press", "Chest")
        log_workout(db, user, days_ago=1, entries=[(bench, [(80, 5)])])
        assert get_stats()["nudges"] == []  # Legs absent: not in rotation

    def test_other_group_never_nudges(self, db, user, get_stats):
        bench = make_exercise(db, "Bench Press", "Chest")
        odd = make_exercise(db, "Mystery Machine", "Other")
        log_workout(db, user, days_ago=1, entries=[(bench, [(80, 5)])])
        log_workout(db, user, days_ago=12, entries=[(odd, [(30, 10)])])
        assert get_stats()["nudges"] == []

    def test_silent_when_not_training_at_all(self, db, user, get_stats):
        bench = make_exercise(db, "Bench Press", "Chest")
        squat = make_exercise(db, "Back Squat", "Legs")
        log_workout(db, user, days_ago=20, entries=[(bench, [(80, 5)])])
        log_workout(db, user, days_ago=25, entries=[(squat, [(100, 5)])])
        # Most recent training is 20 days ago (> 14): absence, not imbalance
        assert get_stats()["nudges"] == []

    def test_respects_setting(self, db, user, get_stats):
        user.gap_nudges = False
        bench = make_exercise(db, "Bench Press", "Chest")
        squat = make_exercise(db, "Back Squat", "Legs")
        log_workout(db, user, days_ago=1, entries=[(bench, [(80, 5)])])
        log_workout(db, user, days_ago=10, entries=[(squat, [(100, 5)])])
        assert get_stats()["nudges"] == []


class TestFormAndFatigue:
    def test_gated_below_14_days_of_history(self, db, user, get_stats):
        bench = make_exercise(db)
        log_workout(db, user, days_ago=5, entries=[(bench, [(80, 10)])])
        assert get_stats()["trends"]["load"] is None

    def test_cramming_reads_as_overreaching(self, db, user, get_stats):
        bench = make_exercise(db)
        log_workout(db, user, days_ago=100, entries=[(bench, [(60, 10)])])
        for days in range(1, 6):  # five heavy sessions in the last five days
            log_workout(db, user, days_ago=days, entries=[(bench, [(100, 10)] * 5)])
        load = get_stats()["trends"]["load"]
        assert load["status"] == "overreaching"

    def test_layoff_reads_as_fresh(self, db, user, get_stats):
        bench = make_exercise(db)
        # Eight consistent weeks, then 12 quiet days: fatigue decays 4× faster
        for week in range(2, 10):
            log_workout(db, user, days_ago=week * 7 - 2, entries=[(bench, [(100, 10)] * 5)])
        load = get_stats()["trends"]["load"]
        assert load["status"] == "fresh"

    def test_chart_window_is_90_days(self, db, user, get_stats):
        bench = make_exercise(db)
        log_workout(db, user, days_ago=200, entries=[(bench, [(80, 10)])])
        log_workout(db, user, days_ago=1, entries=[(bench, [(80, 10)])])
        assert len(get_stats()["trends"]["load"]["days"]) == 90


class TestRecovery:
    def test_two_day_rest_outperforms_one_day(self, db, user, get_stats):
        bench = make_exercise(db)
        # Alternating gaps; a session's e1RM depends on the gap BEFORE it:
        # 1 rest day → 98, 2 rest days → 102
        day = 40
        schedule = [(day, None)]
        for gap in [1, 2] * 11:
            day -= gap
            schedule.append((day, gap))
        for days_ago, preceding_gap in schedule:
            e1 = 100.0 if preceding_gap is None else (98.0 if preceding_gap == 1 else 102.0)
            log_workout(db, user, days_ago=days_ago, entries=[(bench, [bw_set(e1)])])
        rec = get_stats()["trends"]["recovery"]
        assert rec is not None
        by_bucket = {r["bucket"]: r for r in rec}
        assert by_bucket["1"]["n"] >= 3 and by_bucket["2"]["n"] >= 3
        assert by_bucket["2"]["pct"] > by_bucket["1"]["pct"]

    def test_gated_on_thin_data(self, db, user, get_stats):
        bench = make_exercise(db)
        for days in (10, 8, 6, 4, 2):
            log_workout(db, user, days_ago=days, entries=[(bench, [(80, 8)])])
        assert get_stats()["trends"]["recovery"] is None


class TestStandards:
    def _bodyweight(self, db, user, value=80.0):
        db.add(Measurement(user_id=user.id, kind="Weight", value=value,
                           measured_at=FROZEN_NOW))
        db.commit()

    def test_score_and_level(self, db, user, get_stats):
        self._bodyweight(db, user, 80.0)
        bench = make_exercise(db, "Bench Press", "Chest", equipment="Barbell")
        log_workout(db, user, days_ago=3, entries=[(bench, [bw_set(100.0)])])
        rows = get_stats()["trends"]["standards"]
        assert len(rows) == 1
        row = rows[0]
        # 100 / 80 = 1.25×BW: past Intermediate (1.0), halfway to Advanced (1.5)
        assert row["lift"] == "Bench Press"
        assert row["ratio"] == 1.25
        assert row["level"] == "Intermediate"
        assert row["score"] == pytest.approx(3.5, abs=0.01)

    def test_machines_never_count(self, db, user, get_stats):
        self._bodyweight(db, user, 80.0)
        machine = make_exercise(db, "Machine Chest Press", "Chest", equipment="Machine")
        log_workout(db, user, days_ago=3, entries=[(machine, [bw_set(200.0)])])
        assert get_stats()["trends"]["standards"] is None

    def test_gated_without_bodyweight(self, db, user, get_stats):
        bench = make_exercise(db, "Bench Press", "Chest", equipment="Barbell")
        log_workout(db, user, days_ago=3, entries=[(bench, [bw_set(100.0)])])
        assert get_stats()["trends"]["standards"] is None


class TestDetraining:
    def test_average_loss_per_week(self, db, user, get_stats):
        # Three 28-day layoffs, each costing exactly 10% → 2.5%/week
        exercises = [make_exercise(db, f"Lift {i}", "Chest") for i in range(3)]
        for ex in exercises:
            log_workout(db, user, days_ago=60, entries=[(ex, [bw_set(100.0)])])
            log_workout(db, user, days_ago=32, entries=[(ex, [bw_set(90.0)])])
        det = get_stats()["trends"]["detraining"]
        assert det["events"] == 3
        assert det["pct_per_week"] == pytest.approx(2.5, abs=0.01)

    def test_gated_below_three_events(self, db, user, get_stats):
        ex = make_exercise(db, "Lift", "Chest")
        log_workout(db, user, days_ago=60, entries=[(ex, [bw_set(100.0)])])
        log_workout(db, user, days_ago=32, entries=[(ex, [bw_set(90.0)])])
        assert get_stats()["trends"]["detraining"] is None


class TestForecast:
    def test_rising_lift_gets_slope_and_milestone(self, db, user, get_stats):
        bench = make_exercise(db)
        # Weekly sessions, e1RM climbing 2.5/week: 100 … 110
        for i, e1 in enumerate([100, 102.5, 105, 107.5, 110]):
            log_workout(db, user, days_ago=(4 - i) * 7 + 1, entries=[(bench, [bw_set(e1)])])
        fc = get_stats()["trends"]["forecast"]
        assert len(fc) == 1
        row = fc[0]
        assert row["slope"] == pytest.approx(2.5, abs=0.05)
        assert row["milestone"] == 120
        assert row["eta"] is not None

    def test_flat_lift_reports_no_milestone(self, db, user, get_stats):
        bench = make_exercise(db)
        for i in range(5):
            log_workout(db, user, days_ago=i * 7 + 1, entries=[(bench, [bw_set(100.0)])])
        row = get_stats()["trends"]["forecast"][0]
        assert row["milestone"] is None and row["eta"] is None

    def test_gated_below_four_points(self, db, user, get_stats):
        bench = make_exercise(db)
        for i in range(3):
            log_workout(db, user, days_ago=i * 7 + 1, entries=[(bench, [bw_set(100.0)])])
        assert get_stats()["trends"]["forecast"] == []


class TestTimeOfDay:
    def test_morning_lifter_detected(self, db, user, get_stats):
        bench = make_exercise(db)
        day = 40
        for i in range(4):  # stronger mornings
            log_workout(db, user, days_ago=day - i * 8, hour=8, entries=[(bench, [bw_set(105.0)])])
        for i in range(4):  # weaker evenings
            log_workout(db, user, days_ago=day - 4 - i * 8, hour=18, entries=[(bench, [bw_set(95.0)])])
        times = get_stats()["trends"]["times"]
        by = {t["bucket"]: t for t in times}
        assert by["Morning"]["index"] == 105
        assert by["Evening"]["index"] == 95

    def test_single_slot_lift_contributes_nothing(self, db, user, get_stats):
        bench = make_exercise(db)
        for i in range(6):
            log_workout(db, user, days_ago=2 + i * 3, hour=18, entries=[(bench, [bw_set(100.0)])])
        assert get_stats()["trends"]["times"] is None


class TestPacing:
    def test_measured_rest_and_outlier_filters(self, db, user, get_stats):
        bench = make_exercise(db)
        log_workout(db, user, days_ago=2, rest_between_sets=120,
                    entries=[(bench, [(80, 8)] * 4)])
        # Drop-set taps (5 s) and a phone call (700 s) must both be discarded
        log_workout(db, user, days_ago=4, rest_between_sets=5,
                    entries=[(bench, [(60, 10)] * 3)])
        log_workout(db, user, days_ago=6, rest_between_sets=700,
                    entries=[(bench, [(60, 10)] * 3)])
        pacing = get_stats()["trends"]["pacing"]
        assert pacing["avg_rest_seconds"] == 120

    def test_density_is_volume_per_minute(self, db, user, get_stats):
        bench = make_exercise(db)
        log_workout(db, user, days_ago=2, duration_minutes=30,
                    entries=[(bench, [(100, 10)] * 3)])  # 3000 kg / 30 min
        assert get_stats()["trends"]["pacing"]["avg_density"] == 100.0


class TestBlocks:
    def test_current_vs_previous_block(self, db, user, get_stats):
        bench = make_exercise(db, "Bench Press", "Chest")
        log_workout(db, user, days_ago=40, entries=[(bench, [(100, 10)] * 2)])  # previous block
        log_workout(db, user, days_ago=5, entries=[(bench, [(100, 10)] * 3)])   # current block
        blocks = get_stats()["trends"]["blocks"]
        assert blocks["previous"] == {"volume": 2000.0, "workouts": 1}
        assert blocks["current"] == {"volume": 3000.0, "workouts": 1}
        chest = next(g for g in blocks["groups"] if g["group"] == "Chest")
        assert (chest["previous"], chest["current"]) == (2, 3)

    def test_gated_without_a_previous_block(self, db, user, get_stats):
        bench = make_exercise(db)
        log_workout(db, user, days_ago=5, entries=[(bench, [(100, 10)])])
        assert get_stats()["trends"]["blocks"] is None


class TestProgramInsights:
    """TM headroom + cycle-over-cycle: AMRAP e1RM against the training max
    reconstructed by replaying the program state machine backwards."""

    def _finish_session(self, db, user, program_id, amrap_reps, days_ago):
        from datetime import timedelta

        from backend.api.programs import start_program_workout
        from backend.api.workouts import finish_workout
        from backend.models import Workout

        data = start_program_workout(program_id, user=user, db=db)
        w = db.get(Workout, data["id"])
        w.started_at = FROZEN_NOW - timedelta(days=days_ago)
        sets = w.exercises[0].sets
        for s in sets:
            s.is_completed = True
        sets[-1].reps = amrap_reps  # the AMRAP set: reps corrected upward
        db.commit()
        finish_workout(w.id, user=user, db=db)
        w.finished_at = w.started_at
        db.commit()
        db.expire_all()

    def _make_program(self, db, user, exercise, tm=100.0):
        from backend.api.programs import ProgramIn, ProgramLiftIn, create_program

        data = create_program(
            ProgramIn(
                name="531",
                scheme="531",
                lifts=[ProgramLiftIn(exercise_id=exercise.id, training_max=tm)],
            ),
            user=user,
            db=db,
        )
        return data["id"]

    def test_headroom_from_amrap_sets(self, db, user, get_stats):
        bench = make_exercise(db, "Bench Press")
        pid = self._make_program(db, user, bench, tm=100.0)
        # Week 1: top set 85×10 -> e1RM 113.3 -> +13.3% vs TM 100
        self._finish_session(db, user, pid, amrap_reps=10, days_ago=10)
        # Week 2: top set 90×5 -> e1RM 105.0 -> +5.0%
        self._finish_session(db, user, pid, amrap_reps=5, days_ago=8)
        rows = get_stats()["trends"]["headroom"]
        assert len(rows) == 1
        row = rows[0]
        assert row["lift"] == "Bench Press"
        assert [p["week"] for p in row["points"]] == [1, 2]
        assert row["latest"]["weight"] == 90.0
        assert row["latest"]["e1rm"] == pytest.approx(105.0)
        assert row["latest"]["headroom"] == pytest.approx(5.0)
        assert row["latest"]["tm"] == 100.0
        assert row["points"][0]["headroom"] == pytest.approx(13.3)

    def test_tm_is_reconstructed_across_cycle_bumps(self, db, user, get_stats):
        bench = make_exercise(db, "Bench Press")
        pid = self._make_program(db, user, bench, tm=100.0)
        # Two full cycles: 8 sessions, 5 reps on every AMRAP set. After the
        # first cycle the TM bumps 100 -> 102.5; headroom must be computed
        # against the TM of the session's own cycle.
        for i in range(8):
            self._finish_session(db, user, pid, amrap_reps=5, days_ago=40 - i * 4)
        rows = get_stats()["trends"]["headroom"]
        points = rows[0]["points"]
        # Deload weeks (4) carry no AMRAP -> 3 points per cycle
        assert [(p["cycle"], p["week"]) for p in points] == [
            (1, 1), (1, 2), (1, 3), (2, 1), (2, 2), (2, 3),
        ]
        assert all(p["tm"] == 100.0 for p in points[:3])
        assert all(p["tm"] == 102.5 for p in points[3:])
        # Cycle 2 week 1: 0.85 × 102.5 rounds to 87.5 at the 2.5 step
        assert points[3]["weight"] == 87.5

    def test_cycle_over_cycle_needs_two_cycles(self, db, user, get_stats):
        bench = make_exercise(db, "Bench Press")
        pid = self._make_program(db, user, bench, tm=100.0)
        for i in range(3):
            self._finish_session(db, user, pid, amrap_reps=5, days_ago=20 - i * 4)
        assert get_stats()["trends"]["cycles"] is None

        for i in range(5):
            self._finish_session(db, user, pid, amrap_reps=6, days_ago=8 - i)
        cycles = get_stats()["trends"]["cycles"]
        assert len(cycles) == 1
        week1 = next(wk for wk in cycles[0]["weeks"] if wk["week"] == 1)
        assert [(c["cycle"], c["weight"], c["reps"]) for c in week1["cycles"]] == [
            (1, 85.0, 5), (2, 87.5, 6),
        ]

    def test_gated_without_program_sessions(self, db, user, get_stats):
        bench = make_exercise(db)
        log_workout(db, user, days_ago=5, entries=[(bench, [(80, 5)])])
        assert get_stats()["trends"]["headroom"] is None
        assert get_stats()["trends"]["cycles"] is None


class TestVelocity:
    """Progression velocity: sessions per weight increase on rep-range work."""

    def _rep_range_session(self, db, user, exercise, days_ago, tops):
        w = log_workout(db, user, days_ago, entries=[(exercise, [(t, 10) for t in tops])])
        for we in w.exercises:
            we.rep_min, we.rep_max = 8, 12
        db.commit()
        return w

    def test_sessions_per_increase(self, db, user, get_stats):
        row_ex = make_exercise(db, "Dumbbell Row", "Back", "Dumbbell")
        # Tops: 50, 50, 52.5, 52.5, 52.5, 55 -> increases after 2 and 3 sessions
        for i, top in enumerate([50, 50, 52.5, 52.5, 52.5, 55]):
            self._rep_range_session(db, user, row_ex, days_ago=30 - i * 4, tops=[top] * 3)
        rows = get_stats()["trends"]["velocity"]
        assert len(rows) == 1
        r = rows[0]
        assert r["name"] == "Dumbbell Row"
        assert r["sessions_per_increase"] == 2.5
        assert r["increases"] == 2
        assert (r["current_weight"], r["sessions_at_current"]) == (55.0, 1)
        assert (r["last_min_reps"], r["rep_max"]) == (10, 12)

    def test_gated_below_two_increases(self, db, user, get_stats):
        row_ex = make_exercise(db, "Dumbbell Row", "Back", "Dumbbell")
        for i, top in enumerate([50, 50, 52.5]):
            self._rep_range_session(db, user, row_ex, days_ago=20 - i * 4, tops=[top] * 3)
        assert get_stats()["trends"]["velocity"] is None

    def test_plain_sets_without_rep_range_never_count(self, db, user, get_stats):
        bench = make_exercise(db)
        for i, top in enumerate([50, 52.5, 55, 57.5]):
            log_workout(db, user, days_ago=20 - i * 4, entries=[(bench, [(top, 10)])])
        assert get_stats()["trends"]["velocity"] is None
