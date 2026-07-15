"""Seed the database with a curated set of weight-training exercises.

Strength work only by design — Forge tracks iron, not cardio.
Idempotent: existing global exercises are never duplicated.
"""
from sqlalchemy import select
from sqlalchemy.orm import Session

from backend.models.exercise import Exercise

EXERCISES = [
    # Chest
    ("Bench Press", "Chest", "Barbell"),
    ("Incline Bench Press", "Chest", "Barbell"),
    ("Decline Bench Press", "Chest", "Barbell"),
    ("Dumbbell Bench Press", "Chest", "Dumbbell"),
    ("Incline Dumbbell Press", "Chest", "Dumbbell"),
    ("Decline Dumbbell Press", "Chest", "Dumbbell"),
    ("Chest Fly", "Chest", "Dumbbell"),
    ("Cable Fly", "Chest", "Cable"),
    ("Machine Chest Press", "Chest", "Machine"),
    ("Pec Deck", "Chest", "Machine"),
    ("Push-Up", "Chest", "Bodyweight"),
    ("Dip", "Chest", "Bodyweight"),
    # Back
    ("Deadlift", "Back", "Barbell"),
    ("Barbell Row", "Back", "Barbell"),
    ("Pendlay Row", "Back", "Barbell"),
    ("Dumbbell Row", "Back", "Dumbbell"),
    ("T-Bar Row", "Back", "Machine"),
    ("Chest Supported Row", "Back", "Machine"),
    ("Seated Cable Row", "Back", "Cable"),
    ("Lat Pulldown", "Back", "Cable"),
    ("Straight-Arm Pulldown", "Back", "Cable"),
    ("Pull-Up", "Back", "Bodyweight"),
    ("Chin-Up", "Back", "Bodyweight"),
    ("Inverted Row", "Back", "Bodyweight"),
    ("Pullover", "Back", "Dumbbell"),
    ("Back Extension", "Back", "Bodyweight"),
    ("Good Morning", "Back", "Barbell"),
    ("Rack Pull", "Back", "Barbell"),
    # Shoulders
    ("Overhead Press", "Shoulders", "Barbell"),
    ("Push Press", "Shoulders", "Barbell"),
    ("Seated Dumbbell Press", "Shoulders", "Dumbbell"),
    ("Arnold Press", "Shoulders", "Dumbbell"),
    ("Machine Shoulder Press", "Shoulders", "Machine"),
    ("Lateral Raise", "Shoulders", "Dumbbell"),
    ("Cable Lateral Raise", "Shoulders", "Cable"),
    ("Front Raise", "Shoulders", "Dumbbell"),
    ("Rear Delt Fly", "Shoulders", "Dumbbell"),
    ("Cable Reverse Fly", "Shoulders", "Cable"),
    ("Face Pull", "Shoulders", "Cable"),
    ("Barbell Shrug", "Shoulders", "Barbell"),
    ("Dumbbell Shrug", "Shoulders", "Dumbbell"),
    ("Upright Row", "Shoulders", "Barbell"),
    # Arms
    ("Barbell Curl", "Arms", "Barbell"),
    ("EZ Bar Curl", "Arms", "EZ Bar"),
    ("Bicep Curl", "Arms", "Dumbbell"),
    ("Hammer Curl", "Arms", "Dumbbell"),
    ("Incline Dumbbell Curl", "Arms", "Dumbbell"),
    ("Preacher Curl", "Arms", "EZ Bar"),
    ("Concentration Curl", "Arms", "Dumbbell"),
    ("Cable Curl", "Arms", "Cable"),
    ("Skull Crusher", "Arms", "EZ Bar"),
    ("Tricep Pushdown", "Arms", "Cable"),
    ("Overhead Tricep Extension", "Arms", "Dumbbell"),
    ("Tricep Extension", "Arms", "Dumbbell"),
    ("Close-Grip Bench Press", "Arms", "Barbell"),
    ("Wrist Curl", "Arms", "Dumbbell"),
    # Legs
    ("Back Squat", "Legs", "Barbell"),
    ("Front Squat", "Legs", "Barbell"),
    ("Hack Squat", "Legs", "Machine"),
    ("Leg Press", "Legs", "Machine"),
    ("Romanian Deadlift", "Legs", "Barbell"),
    ("Sumo Deadlift", "Legs", "Barbell"),
    ("Trap Bar Deadlift", "Legs", "Trap Bar"),
    ("Single-Leg Deadlift", "Legs", "Dumbbell"),
    ("Hip Thrust", "Legs", "Barbell"),
    ("Glute Bridge", "Legs", "Bodyweight"),
    ("Bulgarian Split Squat", "Legs", "Dumbbell"),
    ("Walking Lunge", "Legs", "Dumbbell"),
    ("Static Lunge", "Legs", "Bodyweight"),
    ("Leg Extension", "Legs", "Machine"),
    ("Leg Curl", "Legs", "Machine"),
    ("Glute Ham Raise", "Legs", "Machine"),
    ("Nordic Hamstring Curl", "Legs", "Bodyweight"),
    ("Calf Raise", "Legs", "Bodyweight"),
    ("Seated Calf Raise", "Legs", "Machine"),
    ("Pistol Squat", "Legs", "Bodyweight"),
    ("Goblet Squat", "Legs", "Dumbbell"),
    # Core
    ("Plank", "Core", "Bodyweight"),
    ("Side Plank", "Core", "Bodyweight"),
    ("Hanging Leg Raise", "Core", "Bodyweight"),
    ("Hanging Knee Raise", "Core", "Bodyweight"),
    ("Cable Crunch", "Core", "Cable"),
    ("Cable Woodchop", "Core", "Cable"),
    ("Russian Twist", "Core", "Bodyweight"),
    ("Ab Wheel Rollout", "Core", "Other"),
    ("Weighted Sit-Up", "Core", "Bodyweight"),
    ("Dead Bug", "Core", "Bodyweight"),
    # Olympic / full body
    ("Clean and Jerk", "Full Body", "Barbell"),
    ("Power Clean", "Full Body", "Barbell"),
    ("Snatch", "Full Body", "Barbell"),
    ("Thruster", "Full Body", "Barbell"),
    ("Kettlebell Swing", "Full Body", "Kettlebell"),
    ("Farmer's Walk", "Full Body", "Dumbbell"),
]


# Grip metadata + variation grouping applied to the base catalogue above.
# variant_of groups an exercise under its base movement; grip NULL = standard.
ENRICHMENT: dict[str, dict] = {
    "Pull-Up": {"grip": "Overhand"},
    "Chin-Up": {"grip": "Underhand", "variant_of": "Pull-Up"},
    "Barbell Row": {"grip": "Overhand"},
    "Pendlay Row": {"grip": "Overhand", "variant_of": "Barbell Row"},
    "T-Bar Row": {"grip": "Neutral"},
    "Seated Cable Row": {"grip": "Neutral"},
    "Hammer Curl": {"grip": "Neutral", "variant_of": "Bicep Curl"},
    "Close-Grip Bench Press": {"grip": "Close", "variant_of": "Bench Press"},
    "Incline Bench Press": {"variant_of": "Bench Press"},
    "Decline Bench Press": {"variant_of": "Bench Press"},
    "Incline Dumbbell Press": {"variant_of": "Dumbbell Bench Press"},
    "Decline Dumbbell Press": {"variant_of": "Dumbbell Bench Press"},
    "Front Squat": {"variant_of": "Back Squat"},
    "Goblet Squat": {"variant_of": "Back Squat"},
    "Sumo Deadlift": {"variant_of": "Deadlift"},
    "Trap Bar Deadlift": {"grip": "Neutral", "variant_of": "Deadlift"},
    "Push Press": {"variant_of": "Overhead Press"},
    "Arnold Press": {"variant_of": "Seated Dumbbell Press"},
    "EZ Bar Curl": {"variant_of": "Barbell Curl"},
    "Seated Calf Raise": {"variant_of": "Calf Raise"},
}

# New grip variations added to the catalogue.
# (name, muscle group, equipment, grip, variant_of)
VARIATIONS = [
    ("Lat Pulldown (Wide Grip)", "Back", "Cable", "Wide", "Lat Pulldown"),
    ("Lat Pulldown (Close Grip)", "Back", "Cable", "Close", "Lat Pulldown"),
    ("Lat Pulldown (Underhand)", "Back", "Cable", "Underhand", "Lat Pulldown"),
    ("Barbell Row (Underhand)", "Back", "Barbell", "Underhand", "Barbell Row"),
    ("Pull-Up (Wide Grip)", "Back", "Bodyweight", "Wide", "Pull-Up"),
    ("Pull-Up (Neutral Grip)", "Back", "Bodyweight", "Neutral", "Pull-Up"),
    ("Seated Cable Row (Wide Grip)", "Back", "Cable", "Wide", "Seated Cable Row"),
    ("Bench Press (Wide Grip)", "Chest", "Barbell", "Wide", "Bench Press"),
    ("Deadlift (Mixed Grip)", "Back", "Barbell", "Mixed", "Deadlift"),
    ("Snatch-Grip Deadlift", "Back", "Barbell", "Wide", "Deadlift"),
    ("Reverse Curl", "Arms", "Barbell", "Overhand", "Barbell Curl"),
]


def seed_exercises(db: Session) -> None:
    existing = set(
        db.execute(select(Exercise.name).where(Exercise.owner_id.is_(None))).scalars()
    )
    for name, muscle_group, equipment in EXERCISES:
        if name not in existing:
            db.add(Exercise(name=name, muscle_group=muscle_group, equipment=equipment))
    db.commit()

    by_name = {
        e.name: e
        for e in db.execute(select(Exercise).where(Exercise.owner_id.is_(None))).scalars()
    }

    for name, muscle_group, equipment, grip, variant_of in VARIATIONS:
        if name not in by_name:
            exercise = Exercise(
                name=name,
                muscle_group=muscle_group,
                equipment=equipment,
                grip=grip,
                variant_of_id=by_name[variant_of].id if variant_of in by_name else None,
            )
            db.add(exercise)
            by_name[name] = exercise

    for name, meta in ENRICHMENT.items():
        exercise = by_name.get(name)
        if exercise is None:
            continue
        grip = meta.get("grip")
        if grip and exercise.grip != grip:
            exercise.grip = grip
        base = by_name.get(meta.get("variant_of", ""))
        if base is not None and exercise.variant_of_id != base.id:
            exercise.variant_of_id = base.id
    db.commit()
