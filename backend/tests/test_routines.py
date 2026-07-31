"""Templates: per-set markers defined on a routine and carried onto the
sets a workout starts with."""

from backend.api.routines import create_routine
from backend.api.workouts import seed_from_routine
from backend.models import Routine
from backend.schemas import RoutineExerciseIn, RoutineIn
from backend.tests.conftest import make_exercise


class TestTemplateSetTypes:
    def test_amrap_last_set_round_trips_and_seeds(self, db, user):
        bench = make_exercise(db, "Bench Press")
        created = create_routine(
            RoutineIn(
                name="AMRAP finisher",
                exercises=[
                    RoutineExerciseIn(
                        exercise_id=bench.id,
                        set_count=3,
                        set_types=[None, None, "amrap"],
                    )
                ],
            ),
            user=user,
            db=db,
        )
        assert created["exercises"][0]["set_types"] == ["", "", "amrap"]

        routine = db.get(Routine, created["id"])
        seeded = seed_from_routine(db, user, routine)
        assert [s.set_type for s in seeded[0].sets] == [None, None, "amrap"]

    def test_no_markers_leaves_plain_sets(self, db, user):
        bench = make_exercise(db, "Bench Press")
        created = create_routine(
            RoutineIn(
                name="Plain",
                exercises=[RoutineExerciseIn(exercise_id=bench.id, set_count=2)],
            ),
            user=user,
            db=db,
        )
        assert created["exercises"][0]["set_types"] is None
        routine = db.get(Routine, created["id"])
        seeded = seed_from_routine(db, user, routine)
        assert [s.set_type for s in seeded[0].sets] == [None, None]
