"""Seed the database with a curated set of weight-training exercises.

Strength work only by design — Forge tracks iron, not cardio.

The CATALOG is the source of truth for global exercises: rows are inserted
when missing and their metadata (group, equipment, modifiers, family links)
is re-synced on every startup, so catalog fixes reach existing installs
automatically. User-created exercises are never touched.

Modifier model:
- equipment:  what loads the movement — 'Machine' means a stack machine;
  'Plate-Loaded' and 'Smith Machine' are deliberately separate because they
  feel and load differently.
- grip:       hand orientation (Overhand / Underhand / Neutral / Mixed)
- grip_width: Close / Wide (NULL = standard)
- attachment: cable-station attachment (Rope / Straight Bar / V-Bar / ...)
- base:       variant_of link — groups a variant under its base movement
"""
from sqlalchemy import select
from sqlalchemy.orm import Session

from backend.models.exercise import Exercise

# (name, muscle_group, equipment, {grip, width, attachment, base})
CATALOG: list[tuple[str, str, str, dict]] = [
    # ── Chest ────────────────────────────────────────────────────────────────
    ("Bench Press", "Chest", "Barbell", {}),
    ("Close-Grip Bench Press", "Arms", "Barbell", {"width": "Close", "base": "Bench Press"}),
    ("Bench Press (Wide Grip)", "Chest", "Barbell", {"width": "Wide", "base": "Bench Press"}),
    ("Paused Bench Press", "Chest", "Barbell", {"base": "Bench Press"}),
    ("Incline Bench Press", "Chest", "Barbell", {"base": "Bench Press"}),
    ("Decline Bench Press", "Chest", "Barbell", {"base": "Bench Press"}),
    ("Smith Machine Bench Press", "Chest", "Smith Machine", {"base": "Bench Press"}),
    ("Smith Machine Incline Press", "Chest", "Smith Machine", {"base": "Incline Bench Press"}),
    ("Smith Machine Decline Press", "Chest", "Smith Machine", {"base": "Decline Bench Press"}),
    ("Dumbbell Bench Press", "Chest", "Dumbbell", {}),
    ("Incline Dumbbell Press", "Chest", "Dumbbell", {"base": "Dumbbell Bench Press"}),
    ("Decline Dumbbell Press", "Chest", "Dumbbell", {"base": "Dumbbell Bench Press"}),
    ("Machine Chest Press", "Chest", "Machine", {}),
    ("Incline Machine Chest Press", "Chest", "Machine", {"base": "Machine Chest Press"}),
    ("Plate-Loaded Chest Press", "Chest", "Plate-Loaded", {"base": "Machine Chest Press"}),
    (
        "Plate-Loaded Incline Chest Press",
        "Chest",
        "Plate-Loaded",
        {"base": "Machine Chest Press"},
    ),
    ("Chest Fly", "Chest", "Dumbbell", {}),
    ("Incline Chest Fly", "Chest", "Dumbbell", {"base": "Chest Fly"}),
    ("Cable Fly", "Chest", "Cable", {}),
    ("Incline Cable Fly", "Chest", "Cable", {"base": "Cable Fly"}),
    ("Low-to-High Cable Fly", "Chest", "Cable", {"base": "Cable Fly"}),
    ("Pec Deck", "Chest", "Machine", {}),
    ("Push-Up", "Chest", "Bodyweight", {}),
    ("Close-Grip Push-Up", "Chest", "Bodyweight", {"width": "Close", "base": "Push-Up"}),
    ("Dip", "Chest", "Bodyweight", {}),
    ("Weighted Dip", "Chest", "Bodyweight", {"base": "Dip"}),
    ("Bench Dip", "Arms", "Bodyweight", {"base": "Dip"}),
    ("Machine Dip", "Arms", "Machine", {"base": "Dip"}),
    # ── Back ─────────────────────────────────────────────────────────────────
    ("Deadlift", "Back", "Barbell", {}),
    ("Deadlift (Mixed Grip)", "Back", "Barbell", {"grip": "Mixed", "base": "Deadlift"}),
    ("Snatch-Grip Deadlift", "Back", "Barbell", {"width": "Wide", "base": "Deadlift"}),
    ("Deficit Deadlift", "Back", "Barbell", {"base": "Deadlift"}),
    ("Sumo Deadlift", "Legs", "Barbell", {"base": "Deadlift"}),
    ("Trap Bar Deadlift", "Legs", "Trap Bar", {"grip": "Neutral", "base": "Deadlift"}),
    ("Rack Pull", "Back", "Barbell", {"base": "Deadlift"}),
    ("Barbell Row", "Back", "Barbell", {"grip": "Overhand"}),
    ("Barbell Row (Underhand)", "Back", "Barbell", {"grip": "Underhand", "base": "Barbell Row"}),
    ("Pendlay Row", "Back", "Barbell", {"grip": "Overhand", "base": "Barbell Row"}),
    ("Smith Machine Row", "Back", "Smith Machine", {"base": "Barbell Row"}),
    ("Landmine Row", "Back", "Barbell", {"grip": "Neutral", "base": "Barbell Row"}),
    ("Dumbbell Row", "Back", "Dumbbell", {"grip": "Neutral"}),
    ("T-Bar Row", "Back", "Plate-Loaded", {"grip": "Neutral"}),
    ("Chest Supported Row", "Back", "Machine", {}),
    (
        "Chest-Supported Dumbbell Row",
        "Back",
        "Dumbbell",
        {"grip": "Neutral", "base": "Chest Supported Row"},
    ),
    ("Machine Row", "Back", "Machine", {}),
    ("Plate-Loaded Row", "Back", "Plate-Loaded", {"base": "Machine Row"}),
    ("Seated Cable Row", "Back", "Cable", {"grip": "Neutral", "attachment": "V-Bar"}),
    (
        "Seated Cable Row (Wide Grip)",
        "Back",
        "Cable",
        {"grip": "Overhand", "width": "Wide", "attachment": "Straight Bar", "base": "Seated Cable Row"},
    ),
    (
        "Seated Cable Row (Straight Bar)",
        "Back",
        "Cable",
        {"grip": "Overhand", "attachment": "Straight Bar", "base": "Seated Cable Row"},
    ),
    (
        "Single-Arm Cable Row",
        "Back",
        "Cable",
        {"grip": "Neutral", "attachment": "Single Handle", "base": "Seated Cable Row"},
    ),
    ("Lat Pulldown", "Back", "Cable", {"grip": "Overhand", "attachment": "Straight Bar"}),
    (
        "Lat Pulldown (Wide Grip)",
        "Back",
        "Cable",
        {"grip": "Overhand", "width": "Wide", "attachment": "Straight Bar", "base": "Lat Pulldown"},
    ),
    (
        "Lat Pulldown (Close Grip)",
        "Back",
        "Cable",
        {"width": "Close", "attachment": "V-Bar", "base": "Lat Pulldown"},
    ),
    (
        "Lat Pulldown (Underhand)",
        "Back",
        "Cable",
        {"grip": "Underhand", "attachment": "Straight Bar", "base": "Lat Pulldown"},
    ),
    (
        "Lat Pulldown (Neutral Grip)",
        "Back",
        "Cable",
        {"grip": "Neutral", "attachment": "Neutral-Grip Bar", "base": "Lat Pulldown"},
    ),
    (
        "Single-Arm Lat Pulldown",
        "Back",
        "Cable",
        {"grip": "Neutral", "attachment": "Single Handle", "base": "Lat Pulldown"},
    ),
    ("Machine Lat Pulldown", "Back", "Machine", {"base": "Lat Pulldown"}),
    ("Plate-Loaded Lat Pulldown", "Back", "Plate-Loaded", {"base": "Lat Pulldown"}),
    ("Straight-Arm Pulldown", "Back", "Cable", {"attachment": "Straight Bar"}),
    ("Pull-Up", "Back", "Bodyweight", {"grip": "Overhand"}),
    ("Pull-Up (Wide Grip)", "Back", "Bodyweight", {"grip": "Overhand", "width": "Wide", "base": "Pull-Up"}),
    ("Pull-Up (Neutral Grip)", "Back", "Bodyweight", {"grip": "Neutral", "base": "Pull-Up"}),
    ("Chin-Up", "Back", "Bodyweight", {"grip": "Underhand", "base": "Pull-Up"}),
    ("Weighted Pull-Up", "Back", "Bodyweight", {"grip": "Overhand", "base": "Pull-Up"}),
    ("Assisted Pull-Up", "Back", "Machine", {"grip": "Overhand", "base": "Pull-Up"}),
    ("Inverted Row", "Back", "Bodyweight", {"grip": "Overhand"}),
    ("Pullover", "Back", "Dumbbell", {}),
    ("Cable Pullover", "Back", "Cable", {"attachment": "Rope", "base": "Pullover"}),
    ("Back Extension", "Back", "Bodyweight", {}),
    ("Good Morning", "Back", "Barbell", {}),
    # ── Shoulders ────────────────────────────────────────────────────────────
    ("Overhead Press", "Shoulders", "Barbell", {}),
    ("Push Press", "Shoulders", "Barbell", {"base": "Overhead Press"}),
    ("Seated Barbell Press", "Shoulders", "Barbell", {"base": "Overhead Press"}),
    ("Smith Machine Shoulder Press", "Shoulders", "Smith Machine", {"base": "Overhead Press"}),
    ("Landmine Press", "Shoulders", "Barbell", {"grip": "Neutral", "base": "Overhead Press"}),
    ("Seated Dumbbell Press", "Shoulders", "Dumbbell", {}),
    ("Arnold Press", "Shoulders", "Dumbbell", {"base": "Seated Dumbbell Press"}),
    ("Machine Shoulder Press", "Shoulders", "Machine", {}),
    (
        "Plate-Loaded Shoulder Press",
        "Shoulders",
        "Plate-Loaded",
        {"base": "Machine Shoulder Press"},
    ),
    ("Lateral Raise", "Shoulders", "Dumbbell", {}),
    ("Cable Lateral Raise", "Shoulders", "Cable", {"attachment": "Single Handle", "base": "Lateral Raise"}),
    ("Machine Lateral Raise", "Shoulders", "Machine", {"base": "Lateral Raise"}),
    ("Front Raise", "Shoulders", "Dumbbell", {}),
    ("Cable Front Raise", "Shoulders", "Cable", {"attachment": "Straight Bar", "base": "Front Raise"}),
    ("Rear Delt Fly", "Shoulders", "Dumbbell", {}),
    ("Cable Reverse Fly", "Shoulders", "Cable", {"base": "Rear Delt Fly"}),
    ("Reverse Pec Deck", "Shoulders", "Machine", {"base": "Rear Delt Fly"}),
    ("Face Pull", "Shoulders", "Cable", {"attachment": "Rope"}),
    ("Barbell Shrug", "Shoulders", "Barbell", {}),
    ("Dumbbell Shrug", "Shoulders", "Dumbbell", {"base": "Barbell Shrug"}),
    ("Upright Row", "Shoulders", "Barbell", {}),
    ("Cable Upright Row", "Shoulders", "Cable", {"attachment": "Straight Bar", "base": "Upright Row"}),
    # ── Arms: biceps / forearms ──────────────────────────────────────────────
    ("Barbell Curl", "Arms", "Barbell", {"grip": "Underhand"}),
    ("EZ Bar Curl", "Arms", "EZ Bar", {"base": "Barbell Curl"}),
    ("Reverse Curl", "Arms", "Barbell", {"grip": "Overhand", "base": "Barbell Curl"}),
    ("Bicep Curl", "Arms", "Dumbbell", {"grip": "Underhand"}),
    ("Hammer Curl", "Arms", "Dumbbell", {"grip": "Neutral", "base": "Bicep Curl"}),
    ("Incline Dumbbell Curl", "Arms", "Dumbbell", {"base": "Bicep Curl"}),
    ("Concentration Curl", "Arms", "Dumbbell", {"base": "Bicep Curl"}),
    ("Spider Curl", "Arms", "Dumbbell", {"base": "Bicep Curl"}),
    ("Preacher Curl", "Arms", "EZ Bar", {}),
    ("Dumbbell Preacher Curl", "Arms", "Dumbbell", {"base": "Preacher Curl"}),
    ("Machine Preacher Curl", "Arms", "Machine", {"base": "Preacher Curl"}),
    ("Machine Bicep Curl", "Arms", "Machine", {}),
    ("Cable Curl", "Arms", "Cable", {"grip": "Underhand", "attachment": "Straight Bar"}),
    (
        "Cable Hammer Curl",
        "Arms",
        "Cable",
        {"grip": "Neutral", "attachment": "Rope", "base": "Cable Curl"},
    ),
    (
        "Single-Arm Cable Curl",
        "Arms",
        "Cable",
        {"grip": "Underhand", "attachment": "Single Handle", "base": "Cable Curl"},
    ),
    ("Wrist Curl", "Arms", "Dumbbell", {}),
    # ── Arms: triceps ────────────────────────────────────────────────────────
    ("Skull Crusher", "Arms", "EZ Bar", {}),
    ("Tricep Pushdown", "Arms", "Cable", {"grip": "Overhand", "attachment": "Straight Bar"}),
    (
        "Tricep Pushdown (Rope)",
        "Arms",
        "Cable",
        {"grip": "Neutral", "attachment": "Rope", "base": "Tricep Pushdown"},
    ),
    (
        "Tricep Pushdown (V-Bar)",
        "Arms",
        "Cable",
        {"grip": "Overhand", "attachment": "V-Bar", "base": "Tricep Pushdown"},
    ),
    (
        "Tricep Pushdown (Underhand)",
        "Arms",
        "Cable",
        {"grip": "Underhand", "attachment": "Straight Bar", "base": "Tricep Pushdown"},
    ),
    (
        "Single-Arm Tricep Pushdown",
        "Arms",
        "Cable",
        {"attachment": "Single Handle", "base": "Tricep Pushdown"},
    ),
    ("Overhead Tricep Extension", "Arms", "Dumbbell", {}),
    (
        "Overhead Cable Extension",
        "Arms",
        "Cable",
        {"attachment": "Rope", "base": "Overhead Tricep Extension"},
    ),
    ("Tricep Extension", "Arms", "Dumbbell", {}),
    ("Machine Tricep Extension", "Arms", "Machine", {"base": "Tricep Extension"}),
    # ── Legs ─────────────────────────────────────────────────────────────────
    ("Back Squat", "Legs", "Barbell", {}),
    ("Front Squat", "Legs", "Barbell", {"base": "Back Squat"}),
    ("Box Squat", "Legs", "Barbell", {"base": "Back Squat"}),
    ("Zercher Squat", "Legs", "Barbell", {"base": "Back Squat"}),
    ("Smith Machine Squat", "Legs", "Smith Machine", {"base": "Back Squat"}),
    ("Belt Squat", "Legs", "Plate-Loaded", {"base": "Back Squat"}),
    ("Goblet Squat", "Legs", "Dumbbell", {"base": "Back Squat"}),
    ("Pistol Squat", "Legs", "Bodyweight", {"base": "Back Squat"}),
    ("Hack Squat", "Legs", "Plate-Loaded", {}),
    ("Pendulum Squat", "Legs", "Plate-Loaded", {"base": "Hack Squat"}),
    ("Leg Press", "Legs", "Plate-Loaded", {}),
    ("Seated Leg Press", "Legs", "Machine", {"base": "Leg Press"}),
    ("Single-Leg Leg Press", "Legs", "Plate-Loaded", {"base": "Leg Press"}),
    ("Romanian Deadlift", "Legs", "Barbell", {}),
    ("Dumbbell Romanian Deadlift", "Legs", "Dumbbell", {"base": "Romanian Deadlift"}),
    ("Stiff-Leg Deadlift", "Legs", "Barbell", {"base": "Romanian Deadlift"}),
    ("Single-Leg Deadlift", "Legs", "Dumbbell", {"base": "Romanian Deadlift"}),
    ("Hip Thrust", "Legs", "Barbell", {}),
    ("Machine Hip Thrust", "Legs", "Machine", {"base": "Hip Thrust"}),
    ("Glute Bridge", "Legs", "Bodyweight", {"base": "Hip Thrust"}),
    ("Cable Kickback", "Legs", "Cable", {"attachment": "Ankle Strap"}),
    ("Bulgarian Split Squat", "Legs", "Dumbbell", {}),
    ("Walking Lunge", "Legs", "Dumbbell", {}),
    ("Reverse Lunge", "Legs", "Dumbbell", {"base": "Walking Lunge"}),
    ("Barbell Lunge", "Legs", "Barbell", {"base": "Walking Lunge"}),
    ("Static Lunge", "Legs", "Bodyweight", {"base": "Walking Lunge"}),
    ("Step-Up", "Legs", "Dumbbell", {}),
    ("Leg Extension", "Legs", "Machine", {}),
    ("Leg Curl", "Legs", "Machine", {}),
    ("Seated Leg Curl", "Legs", "Machine", {"base": "Leg Curl"}),
    ("Standing Leg Curl", "Legs", "Machine", {"base": "Leg Curl"}),
    ("Glute Ham Raise", "Legs", "Machine", {}),
    ("Nordic Hamstring Curl", "Legs", "Bodyweight", {}),
    ("Hip Abduction", "Legs", "Machine", {}),
    ("Hip Adduction", "Legs", "Machine", {}),
    ("Calf Raise", "Legs", "Bodyweight", {}),
    ("Standing Calf Raise", "Legs", "Machine", {"base": "Calf Raise"}),
    ("Seated Calf Raise", "Legs", "Machine", {"base": "Calf Raise"}),
    ("Calf Press", "Legs", "Plate-Loaded", {"base": "Calf Raise"}),
    # ── Core ─────────────────────────────────────────────────────────────────
    ("Plank", "Core", "Bodyweight", {}),
    ("Side Plank", "Core", "Bodyweight", {"base": "Plank"}),
    ("Hanging Leg Raise", "Core", "Bodyweight", {}),
    ("Hanging Knee Raise", "Core", "Bodyweight", {"base": "Hanging Leg Raise"}),
    ("Cable Crunch", "Core", "Cable", {"attachment": "Rope"}),
    ("Machine Crunch", "Core", "Machine", {"base": "Cable Crunch"}),
    ("Cable Woodchop", "Core", "Cable", {"attachment": "Single Handle"}),
    ("Russian Twist", "Core", "Bodyweight", {}),
    ("Ab Wheel Rollout", "Core", "Other", {}),
    ("Weighted Sit-Up", "Core", "Bodyweight", {}),
    ("Decline Sit-Up", "Core", "Bodyweight", {"base": "Weighted Sit-Up"}),
    ("Dead Bug", "Core", "Bodyweight", {}),
    # ── Olympic / full body ──────────────────────────────────────────────────
    ("Clean and Jerk", "Full Body", "Barbell", {}),
    ("Power Clean", "Full Body", "Barbell", {"base": "Clean and Jerk"}),
    ("Snatch", "Full Body", "Barbell", {}),
    ("Thruster", "Full Body", "Barbell", {}),
    ("Kettlebell Swing", "Full Body", "Kettlebell", {}),
    ("Farmer's Walk", "Full Body", "Dumbbell", {}),
]


def seed_exercises(db: Session) -> None:
    existing = {
        e.name: e
        for e in db.execute(select(Exercise).where(Exercise.owner_id.is_(None))).scalars()
    }

    # Pass 1: insert missing rows (without family links — bases may not exist yet)
    for name, muscle_group, equipment, meta in CATALOG:
        if name not in existing:
            exercise = Exercise(
                name=name,
                muscle_group=muscle_group,
                equipment=equipment,
                grip=meta.get("grip"),
                grip_width=meta.get("width"),
                attachment=meta.get("attachment"),
            )
            db.add(exercise)
            existing[name] = exercise
    db.flush()

    # Pass 2: sync metadata + family links for every catalog row — this is
    # how catalog corrections reach databases seeded by older versions
    for name, muscle_group, equipment, meta in CATALOG:
        exercise = existing[name]
        base = existing.get(meta.get("base", ""))
        target = {
            "muscle_group": muscle_group,
            "equipment": equipment,
            "grip": meta.get("grip"),
            "grip_width": meta.get("width"),
            "attachment": meta.get("attachment"),
            "variant_of_id": base.id if base is not None else None,
        }
        for field, value in target.items():
            if getattr(exercise, field) != value:
                setattr(exercise, field, value)
    db.commit()
