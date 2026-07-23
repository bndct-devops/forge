"""The periodization engine: scheme math, the state machine, and the
start→finish flow. Documented at /docs/programs and /docs/the-math.
"""
import pytest

from backend.api.programs import (
    ProgramIn,
    ProgramLiftIn,
    ProgramPatch,
    ProgramLiftPatch,
    advance_program,
    create_program,
    list_programs,
    start_program_workout,
    update_program,
)
from backend.api.workouts import finish_workout
from backend.models import Program, Routine, RoutineExercise, SetEntry, User, Workout
from backend.program_schemes import cycle_length, prescription, round_to_step

from .conftest import log_workout, make_exercise


def make_routine(db, user, name="Push accessories", exercises=(), set_counts=None):
    r = Routine(owner_id=user.id, name=name)
    r.exercises = [
        RoutineExercise(
            exercise_id=ex.id,
            position=i,
            set_count=(set_counts or {}).get(ex.id, 3),
            rep_min=8,
            rep_max=12,
        )
        for i, ex in enumerate(exercises)
    ]
    db.add(r)
    db.commit()
    return r


class TestSchemeMath:
    def test_531_week_one(self):
        sets = prescription("531", 1, training_max=100)
        assert [(s["pct"], s["reps"], s["amrap"]) for s in sets] == [
            (0.65, 5, False), (0.75, 5, False), (0.85, 5, True),
        ]
        assert [s["weight"] for s in sets] == [65.0, 75.0, 85.0]

    def test_531_deload_week(self):
        sets = prescription("531", 4, training_max=100)
        assert [s["pct"] for s in sets] == [0.40, 0.50, 0.60]
        assert not any(s["amrap"] for s in sets)

    def test_weights_round_to_the_plate_step(self):
        # 0.65 × 102.5 = 66.625 → 67.5 at a 2.5 step
        sets = prescription("531", 1, training_max=102.5)
        assert sets[0]["weight"] == 67.5
        # and to 5 at a 5 step (lb plates)
        sets = prescription("531", 1, training_max=102.5, step=5)
        assert sets[0]["weight"] == 65.0

    def test_prescription_never_rounds_below_one_step(self):
        sets = prescription("531", 4, training_max=4)  # 40% of 4 kg = 1.6
        assert all(s["weight"] >= 2.5 for s in sets)

    def test_linear_block_shape(self):
        assert cycle_length("linear") == 4
        w1 = prescription("linear", 1, 100)
        w4 = prescription("linear", 4, 100)
        assert [(s["weight"], s["reps"]) for s in w1] == [(70.0, 10)] * 3
        assert [(s["weight"], s["reps"]) for s in w4] == [(85.0, 4)] * 3

    def test_round_to_step(self):
        assert round_to_step(66.6, 2.5) == 67.5
        assert round_to_step(66.6, 5) == 65.0
        assert round_to_step(66.6, 0) == 66.6


def make_program(db, user, exercises, scheme="531", tms=(100.0, 140.0)):
    body = ProgramIn(
        name="Test 531",
        scheme=scheme,
        lifts=[
            ProgramLiftIn(exercise_id=ex.id, training_max=tm, increment=2.5 + 2.5 * i)
            for i, (ex, tm) in enumerate(zip(exercises, tms))
        ],
    )
    data = create_program(body, user=user, db=db)
    return db.get(Program, data["id"])


class TestStateMachine:
    def _finish_program_workout(self, db, user, program):
        data = start_program_workout(program.id, user=user, db=db)
        # complete every prefilled set, then finish
        w = db.get(Workout, data["id"])
        for we in w.exercises:
            for s in we.sets:
                s.is_completed = True
        db.commit()
        finish_workout(w.id, user=user, db=db)
        db.expire_all()

    def test_pointer_then_week_then_cycle(self, db, user):
        bench = make_exercise(db, "Bench Press")
        squat = make_exercise(db, "Back Squat", "Legs")
        p = make_program(db, user, [bench, squat])
        assert (p.current_week, p.lift_pointer, p.cycle_number) == (1, 0, 1)

        self._finish_program_workout(db, user, p)
        assert (p.current_week, p.lift_pointer) == (1, 1)

        self._finish_program_workout(db, user, p)
        assert (p.current_week, p.lift_pointer) == (2, 0)

        # Burn through weeks 2-4 (two sessions each): cycle should wrap
        for _ in range(6):
            self._finish_program_workout(db, user, p)
        assert (p.current_week, p.lift_pointer, p.cycle_number) == (1, 0, 2)
        # TM bumps: bench +2.5, squat +5 (per-lift increments)
        assert [l.training_max for l in p.lifts] == [102.5, 145.0]

    def test_cancelling_does_not_advance(self, db, user):
        bench = make_exercise(db, "Bench Press")
        p = make_program(db, user, [bench], tms=(100.0,))
        data = start_program_workout(p.id, user=user, db=db)
        w = db.get(Workout, data["id"])
        db.delete(w)
        db.commit()
        db.expire_all()
        assert (p.current_week, p.lift_pointer) == (1, 0)

    def test_non_program_workout_never_advances(self, db, user):
        bench = make_exercise(db, "Bench Press")
        p = make_program(db, user, [bench], tms=(100.0,))
        w = Workout(owner_id=user.id, name="Free workout")
        db.add(w)
        db.commit()
        advance_program(db, w)
        db.commit()
        db.expire_all()
        assert (p.current_week, p.lift_pointer) == (1, 0)


class TestProgramWorkouts:
    def test_start_prefills_prescription(self, db, user):
        bench = make_exercise(db, "Bench Press")
        p = make_program(db, user, [bench], tms=(100.0,))
        data = start_program_workout(p.id, user=user, db=db)
        assert data["name"] == "Test 531 — Bench Press (W1)"
        sets = db.query(SetEntry).all()
        assert [(s.weight, s.reps) for s in sets] == [(65.0, 5), (75.0, 5), (85.0, 5)]
        assert data["program"]["sets"][2]["amrap"] is True

    def test_start_appends_the_accessory_routine(self, db, user):
        bench = make_exercise(db, "Bench Press")
        pulldown = make_exercise(db, "Lat Pulldown", "Back", "Cable")
        curl = make_exercise(db, "Bicep Curl", "Arms", "Dumbbell")
        p = make_program(db, user, [bench], tms=(100.0,))
        routine = make_routine(db, user, exercises=[pulldown, curl])
        # A finished session where every set hit rep_max -> the accessory
        # arrives with a double-progression suggestion, like a template start
        log_workout(db, user, 2, [(pulldown, [(50.0, 12), (50.0, 12), (50.0, 12)])])
        update_program(
            p.id,
            ProgramPatch(lifts=[ProgramLiftPatch(id=p.lifts[0].id, routine_id=routine.id)]),
            user=user,
            db=db,
        )
        data = start_program_workout(p.id, user=user, db=db)
        w = db.get(Workout, data["id"])
        assert [(we.exercise_id, we.position) for we in w.exercises] == [
            (bench.id, 0), (pulldown.id, 1), (curl.id, 2),
        ]
        # Main lift prescribed, accessories empty with rep ranges + suggestion
        assert [s.weight for s in w.exercises[0].sets] == [65.0, 75.0, 85.0]
        acc = w.exercises[1]
        assert (acc.rep_min, acc.rep_max, len(acc.sets)) == (8, 12, 3)
        assert all(s.weight is None for s in acc.sets)
        assert (acc.suggested_weight, acc.suggestion_kind) == (52.5, "progress")

    def test_finishing_with_accessories_still_advances(self, db, user):
        bench = make_exercise(db, "Bench Press")
        curl = make_exercise(db, "Bicep Curl", "Arms", "Dumbbell")
        p = make_program(db, user, [bench], tms=(100.0,))
        routine = make_routine(db, user, exercises=[curl])
        update_program(
            p.id,
            ProgramPatch(lifts=[ProgramLiftPatch(id=p.lifts[0].id, routine_id=routine.id)]),
            user=user,
            db=db,
        )
        data = start_program_workout(p.id, user=user, db=db)
        w = db.get(Workout, data["id"])
        for we in w.exercises:
            for s in we.sets:
                s.is_completed = True
        db.commit()
        finish_workout(w.id, user=user, db=db)
        db.expire_all()
        assert p.current_week == 2  # single lift: one session = one week

    def test_deleted_routine_is_skipped_not_an_error(self, db, user):
        bench = make_exercise(db, "Bench Press")
        curl = make_exercise(db, "Bicep Curl", "Arms", "Dumbbell")
        p = make_program(db, user, [bench], tms=(100.0,))
        routine = make_routine(db, user, exercises=[curl])
        update_program(
            p.id,
            ProgramPatch(lifts=[ProgramLiftPatch(id=p.lifts[0].id, routine_id=routine.id)]),
            user=user,
            db=db,
        )
        db.delete(routine)
        db.commit()
        data = start_program_workout(p.id, user=user, db=db)
        w = db.get(Workout, data["id"])
        assert [we.exercise_id for we in w.exercises] == [bench.id]

    def test_patch_clears_the_routine_with_null(self, db, user):
        bench = make_exercise(db, "Bench Press")
        curl = make_exercise(db, "Bicep Curl", "Arms", "Dumbbell")
        p = make_program(db, user, [bench], tms=(100.0,))
        routine = make_routine(db, user, exercises=[curl])
        lift_id = p.lifts[0].id
        update_program(
            p.id,
            ProgramPatch(lifts=[ProgramLiftPatch(id=lift_id, routine_id=routine.id)]),
            user=user,
            db=db,
        )
        db.expire_all()
        assert p.lifts[0].routine_id == routine.id
        # Omitting routine_id leaves the link untouched
        update_program(
            p.id,
            ProgramPatch(lifts=[ProgramLiftPatch(id=lift_id, training_max=105.0)]),
            user=user,
            db=db,
        )
        db.expire_all()
        assert p.lifts[0].routine_id == routine.id
        # An explicit null clears it
        update_program(
            p.id,
            ProgramPatch(lifts=[ProgramLiftPatch(id=lift_id, routine_id=None)]),
            user=user,
            db=db,
        )
        db.expire_all()
        assert p.lifts[0].routine_id is None

    def test_someone_elses_routine_is_rejected(self, db, user):
        bench = make_exercise(db, "Bench Press")
        curl = make_exercise(db, "Bicep Curl", "Arms", "Dumbbell")
        p = make_program(db, user, [bench], tms=(100.0,))
        other = User(username="other", hashed_password="x")
        db.add(other)
        db.commit()
        foreign = make_routine(db, other, exercises=[curl])
        with pytest.raises(Exception) as e:
            update_program(
                p.id,
                ProgramPatch(lifts=[ProgramLiftPatch(id=p.lifts[0].id, routine_id=foreign.id)]),
                user=user,
                db=db,
            )
        assert getattr(e.value, "status_code", None) == 404

    def test_second_active_workout_is_refused(self, db, user):
        bench = make_exercise(db, "Bench Press")
        p = make_program(db, user, [bench], tms=(100.0,))
        start_program_workout(p.id, user=user, db=db)
        with pytest.raises(Exception) as e:
            start_program_workout(p.id, user=user, db=db)
        assert "409" in str(getattr(e.value, "status_code", "")) or getattr(e.value, "status_code", None) == 409


class TestApiGuards:
    def test_unknown_scheme_rejected(self, db, user):
        bench = make_exercise(db, "Bench Press")
        body = ProgramIn(name="x", scheme="atlantis", lifts=[ProgramLiftIn(exercise_id=bench.id, training_max=100)])
        with pytest.raises(Exception) as e:
            create_program(body, user=user, db=db)
        assert getattr(e.value, "status_code", None) == 400

    def test_patch_training_max_and_week(self, db, user):
        bench = make_exercise(db, "Bench Press")
        p = make_program(db, user, [bench], tms=(100.0,))
        lift_id = p.lifts[0].id
        update_program(
            p.id,
            ProgramPatch(current_week=3, lifts=[ProgramLiftPatch(id=lift_id, training_max=110.0)]),
            user=user,
            db=db,
        )
        db.expire_all()
        assert p.current_week == 3
        assert p.lifts[0].training_max == 110.0

    def test_patch_adds_a_lift(self, db, user):
        bench = make_exercise(db, "Bench Press")
        squat = make_exercise(db, "Back Squat", "Legs")
        p = make_program(db, user, [bench], tms=(100.0,))
        update_program(
            p.id,
            ProgramPatch(
                lifts=[
                    ProgramLiftPatch(id=p.lifts[0].id),
                    ProgramLiftPatch(exercise_id=squat.id, training_max=140.0, increment=5.0),
                ]
            ),
            user=user,
            db=db,
        )
        db.expire_all()
        assert [(l.exercise_id, l.position) for l in p.lifts] == [(bench.id, 0), (squat.id, 1)]
        assert p.lifts[1].training_max == 140.0
        assert p.lifts[1].increment == 5.0
        # Next session is still the lift the pointer was on
        assert p.lift_pointer == 0

    def test_patch_removes_a_lift_and_keeps_the_pointer_on_the_next_lift(self, db, user):
        bench = make_exercise(db, "Bench Press")
        squat = make_exercise(db, "Back Squat", "Legs")
        p = make_program(db, user, [bench, squat])
        p.lift_pointer = 1  # next session: squat
        db.commit()
        update_program(
            p.id,
            ProgramPatch(lifts=[ProgramLiftPatch(id=p.lifts[1].id)]),  # drop bench
            user=user,
            db=db,
        )
        db.expire_all()
        assert [(l.exercise_id, l.position) for l in p.lifts] == [(squat.id, 0)]
        assert p.lift_pointer == 0  # still points at squat

    def test_patch_removing_the_pointed_lift_clamps_the_pointer(self, db, user):
        bench = make_exercise(db, "Bench Press")
        squat = make_exercise(db, "Back Squat", "Legs")
        p = make_program(db, user, [bench, squat])
        p.lift_pointer = 1  # next session: squat
        db.commit()
        update_program(
            p.id,
            ProgramPatch(lifts=[ProgramLiftPatch(id=p.lifts[0].id)]),  # drop squat
            user=user,
            db=db,
        )
        db.expire_all()
        assert [l.exercise_id for l in p.lifts] == [bench.id]
        assert p.lift_pointer == 0

    def test_patch_rejects_an_empty_lift_list(self, db, user):
        bench = make_exercise(db, "Bench Press")
        p = make_program(db, user, [bench], tms=(100.0,))
        with pytest.raises(Exception) as e:
            update_program(p.id, ProgramPatch(lifts=[]), user=user, db=db)
        assert getattr(e.value, "status_code", None) == 400

    def test_patch_new_lift_requires_exercise_and_tm(self, db, user):
        bench = make_exercise(db, "Bench Press")
        p = make_program(db, user, [bench], tms=(100.0,))
        with pytest.raises(Exception) as e:
            update_program(
                p.id,
                ProgramPatch(lifts=[ProgramLiftPatch(id=p.lifts[0].id), ProgramLiftPatch(training_max=80.0)]),
                user=user,
                db=db,
            )
        assert getattr(e.value, "status_code", None) == 400

    def test_patch_week_beyond_cycle_rejected(self, db, user):
        bench = make_exercise(db, "Bench Press")
        p = make_program(db, user, [bench], tms=(100.0,))
        with pytest.raises(Exception) as e:
            update_program(p.id, ProgramPatch(current_week=5), user=user, db=db)
        assert getattr(e.value, "status_code", None) == 400

    def test_next_prescription_in_listing(self, db, user):
        bench = make_exercise(db, "Bench Press")
        p = make_program(db, user, [bench], tms=(100.0,))
        listing = list_programs(user=user, db=db)
        nxt = listing[0]["next"]
        assert nxt["exercise_name"] == "Bench Press"
        assert nxt["week"] == 1
        assert [s["weight"] for s in nxt["sets"]] == [65.0, 75.0, 85.0]
