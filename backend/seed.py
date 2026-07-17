"""Seed the database with a curated set of weight-training exercises.

Strength work only by design — Forge tracks iron, not cardio.

The catalog below is the source of truth for global exercises: rows are
inserted when missing and their metadata (group, equipment, modifiers,
family links) is re-synced on every startup, so catalog fixes reach
existing installs automatically. User-created exercises are never touched.

Modifier model:
- equipment:  what loads the movement — 'Machine' means a stack machine;
  'Plate-Loaded' and 'Smith Machine' are deliberately separate because they
  feel and load differently.
- grip:       hand orientation (Overhand / Underhand / Neutral / Mixed)
- grip_width: Close / Wide (NULL = standard width)
- attachment: cable-station attachment (Rope / Straight Bar / V-Bar / ...)
- base:       variant_of link — groups a variant under its parent exercise
"""
from sqlalchemy import select
from sqlalchemy.orm import Session

from backend.models.exercise import Exercise

# (name, muscle_group, equipment, {grip, width, attachment, base})
CATALOG: list[tuple[str, str, str, dict]] = [
    # Schema: a PARENT is movement + loading + setup (angle/stance/machine) —
    # what you'd tell a friend you did. CHILDREN are what you changed with
    # your hands at that station: grip orientation, width, attachment,
    # unilateral. Anything else is its own exercise.
    #
    # ── Chest: barbell benches ───────────────────────────────────────────────
    ("Bench Press", "Chest", "Barbell", {}),
    ("Close-Grip Bench Press", "Arms", "Barbell", {"width": "Close", "base": "Bench Press"}),
    ("Bench Press (Wide Grip)", "Chest", "Barbell", {"width": "Wide", "base": "Bench Press"}),
    ("Paused Bench Press", "Chest", "Barbell", {"base": "Bench Press"}),
    ("Incline Bench Press", "Chest", "Barbell", {}),
    (
        "Incline Bench Press (Close Grip)",
        "Chest",
        "Barbell",
        {"width": "Close", "base": "Incline Bench Press"},
    ),
    (
        "Incline Bench Press (Wide Grip)",
        "Chest",
        "Barbell",
        {"width": "Wide", "base": "Incline Bench Press"},
    ),
    ("Decline Bench Press", "Chest", "Barbell", {}),
    (
        "Decline Bench Press (Close Grip)",
        "Chest",
        "Barbell",
        {"width": "Close", "base": "Decline Bench Press"},
    ),
    (
        "Decline Bench Press (Wide Grip)",
        "Chest",
        "Barbell",
        {"width": "Wide", "base": "Decline Bench Press"},
    ),
    # ── Chest: smith benches ─────────────────────────────────────────────────
    ("Smith Machine Bench Press", "Chest", "Smith Machine", {}),
    (
        "Smith Machine Bench Press (Close Grip)",
        "Chest",
        "Smith Machine",
        {"width": "Close", "base": "Smith Machine Bench Press"},
    ),
    (
        "Smith Machine Bench Press (Wide Grip)",
        "Chest",
        "Smith Machine",
        {"width": "Wide", "base": "Smith Machine Bench Press"},
    ),
    ("Smith Machine Incline Press", "Chest", "Smith Machine", {}),
    (
        "Smith Machine Incline Press (Close Grip)",
        "Chest",
        "Smith Machine",
        {"width": "Close", "base": "Smith Machine Incline Press"},
    ),
    (
        "Smith Machine Incline Press (Wide Grip)",
        "Chest",
        "Smith Machine",
        {"width": "Wide", "base": "Smith Machine Incline Press"},
    ),
    ("Smith Machine Decline Press", "Chest", "Smith Machine", {}),
    (
        "Smith Machine Decline Press (Close Grip)",
        "Chest",
        "Smith Machine",
        {"width": "Close", "base": "Smith Machine Decline Press"},
    ),
    (
        "Smith Machine Decline Press (Wide Grip)",
        "Chest",
        "Smith Machine",
        {"width": "Wide", "base": "Smith Machine Decline Press"},
    ),
    # ── Chest: dumbbell presses ──────────────────────────────────────────────
    ("Dumbbell Bench Press", "Chest", "Dumbbell", {}),
    (
        "Dumbbell Bench Press (Neutral Grip)",
        "Chest",
        "Dumbbell",
        {"grip": "Neutral", "base": "Dumbbell Bench Press"},
    ),
    ("Incline Dumbbell Press", "Chest", "Dumbbell", {}),
    (
        "Incline Dumbbell Press (Neutral Grip)",
        "Chest",
        "Dumbbell",
        {"grip": "Neutral", "base": "Incline Dumbbell Press"},
    ),
    ("Decline Dumbbell Press", "Chest", "Dumbbell", {}),
    # ── Chest: machine presses (stack vs plate-loaded are different machines) ─
    ("Machine Chest Press", "Chest", "Machine", {}),
    (
        "Machine Chest Press (Neutral Grip)",
        "Chest",
        "Machine",
        {"grip": "Neutral", "base": "Machine Chest Press"},
    ),
    ("Incline Machine Chest Press", "Chest", "Machine", {}),
    ("Decline Machine Chest Press", "Chest", "Machine", {}),
    ("Plate-Loaded Chest Press", "Chest", "Plate-Loaded", {}),
    (
        "Plate-Loaded Chest Press (Neutral Grip)",
        "Chest",
        "Plate-Loaded",
        {"grip": "Neutral", "base": "Plate-Loaded Chest Press"},
    ),
    ("Plate-Loaded Incline Chest Press", "Chest", "Plate-Loaded", {}),
    ("Plate-Loaded Decline Chest Press", "Chest", "Plate-Loaded", {}),
    # ── Chest: flys, push-ups, dips ──────────────────────────────────────────
    ("Chest Fly", "Chest", "Dumbbell", {}),
    ("Incline Chest Fly", "Chest", "Dumbbell", {}),
    ("Cable Fly", "Chest", "Cable", {}),
    ("Low-to-High Cable Fly", "Chest", "Cable", {"base": "Cable Fly"}),
    ("Incline Cable Fly", "Chest", "Cable", {}),
    ("Pec Deck", "Chest", "Machine", {}),
    ("Push-Up", "Chest", "Bodyweight", {}),
    ("Close-Grip Push-Up", "Chest", "Bodyweight", {"width": "Close", "base": "Push-Up"}),
    ("Dip", "Chest", "Bodyweight", {}),
    ("Weighted Dip", "Chest", "Bodyweight", {"base": "Dip"}),
    ("Bench Dip", "Arms", "Bodyweight", {}),
    ("Machine Dip", "Arms", "Machine", {}),
    # ── Back: deadlifts ──────────────────────────────────────────────────────
    ("Deadlift", "Back", "Barbell", {}),
    ("Deadlift (Mixed Grip)", "Back", "Barbell", {"grip": "Mixed", "base": "Deadlift"}),
    ("Snatch-Grip Deadlift", "Back", "Barbell", {"width": "Wide", "base": "Deadlift"}),
    ("Deficit Deadlift", "Back", "Barbell", {"base": "Deadlift"}),
    ("Sumo Deadlift", "Legs", "Barbell", {}),
    ("Trap Bar Deadlift", "Legs", "Trap Bar", {"grip": "Neutral"}),
    ("Rack Pull", "Back", "Barbell", {}),
    # ── Back: rows ───────────────────────────────────────────────────────────
    ("Barbell Row", "Back", "Barbell", {"grip": "Overhand"}),
    ("Barbell Row (Underhand)", "Back", "Barbell", {"grip": "Underhand", "base": "Barbell Row"}),
    (
        "Barbell Row (Close Grip)",
        "Back",
        "Barbell",
        {"grip": "Overhand", "width": "Close", "base": "Barbell Row"},
    ),
    (
        "Barbell Row (Wide Grip)",
        "Back",
        "Barbell",
        {"grip": "Overhand", "width": "Wide", "base": "Barbell Row"},
    ),
    ("Pendlay Row", "Back", "Barbell", {"grip": "Overhand"}),
    ("Smith Machine Row", "Back", "Smith Machine", {}),
    (
        "Smith Machine Row (Underhand)",
        "Back",
        "Smith Machine",
        {"grip": "Underhand", "base": "Smith Machine Row"},
    ),
    ("Landmine Row", "Back", "Barbell", {"grip": "Neutral"}),
    ("Dumbbell Row", "Back", "Dumbbell", {"grip": "Neutral"}),
    ("T-Bar Row", "Back", "Plate-Loaded", {"grip": "Neutral"}),
    (
        "T-Bar Row (Wide Grip)",
        "Back",
        "Plate-Loaded",
        {"grip": "Overhand", "width": "Wide", "base": "T-Bar Row"},
    ),
    ("Chest Supported Row", "Back", "Machine", {}),
    ("Chest-Supported Dumbbell Row", "Back", "Dumbbell", {"grip": "Neutral"}),
    ("Machine Row", "Back", "Machine", {}),
    (
        "Machine Row (Wide Grip)",
        "Back",
        "Machine",
        {"grip": "Overhand", "width": "Wide", "base": "Machine Row"},
    ),
    ("Plate-Loaded Row", "Back", "Plate-Loaded", {}),
    (
        "Plate-Loaded Row (Wide Grip)",
        "Back",
        "Plate-Loaded",
        {"grip": "Overhand", "width": "Wide", "base": "Plate-Loaded Row"},
    ),
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
        "Seated Cable Row (Underhand)",
        "Back",
        "Cable",
        {"grip": "Underhand", "attachment": "Straight Bar", "base": "Seated Cable Row"},
    ),
    (
        "Single-Arm Cable Row",
        "Back",
        "Cable",
        {"grip": "Neutral", "attachment": "Single Handle", "base": "Seated Cable Row"},
    ),
    # ── Back: pulldowns & pull-ups ───────────────────────────────────────────
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
    ("Machine Lat Pulldown", "Back", "Machine", {}),
    (
        "Machine Lat Pulldown (Neutral Grip)",
        "Back",
        "Machine",
        {"grip": "Neutral", "base": "Machine Lat Pulldown"},
    ),
    ("Plate-Loaded Lat Pulldown", "Back", "Plate-Loaded", {}),
    (
        "Plate-Loaded Lat Pulldown (Neutral Grip)",
        "Back",
        "Plate-Loaded",
        {"grip": "Neutral", "base": "Plate-Loaded Lat Pulldown"},
    ),
    ("Straight-Arm Pulldown", "Back", "Cable", {"attachment": "Straight Bar"}),
    (
        "Straight-Arm Pulldown (Rope)",
        "Back",
        "Cable",
        {"attachment": "Rope", "base": "Straight-Arm Pulldown"},
    ),
    ("Pull-Up", "Back", "Bodyweight", {"grip": "Overhand"}),
    ("Pull-Up (Wide Grip)", "Back", "Bodyweight", {"grip": "Overhand", "width": "Wide", "base": "Pull-Up"}),
    ("Pull-Up (Neutral Grip)", "Back", "Bodyweight", {"grip": "Neutral", "base": "Pull-Up"}),
    ("Chin-Up", "Back", "Bodyweight", {"grip": "Underhand", "base": "Pull-Up"}),
    ("Weighted Pull-Up", "Back", "Bodyweight", {"grip": "Overhand", "base": "Pull-Up"}),
    ("Assisted Pull-Up", "Back", "Machine", {"grip": "Overhand"}),
    ("Inverted Row", "Back", "Bodyweight", {"grip": "Overhand"}),
    ("Pullover", "Back", "Dumbbell", {}),
    ("Cable Pullover", "Back", "Cable", {"attachment": "Rope"}),
    ("Back Extension", "Back", "Bodyweight", {}),
    ("Good Morning", "Back", "Barbell", {}),
    # ── Shoulders ────────────────────────────────────────────────────────────
    ("Overhead Press", "Shoulders", "Barbell", {}),
    ("Push Press", "Shoulders", "Barbell", {}),
    ("Seated Barbell Press", "Shoulders", "Barbell", {}),
    ("Smith Machine Shoulder Press", "Shoulders", "Smith Machine", {}),
    ("Landmine Press", "Shoulders", "Barbell", {"grip": "Neutral"}),
    ("Seated Dumbbell Press", "Shoulders", "Dumbbell", {}),
    (
        "Seated Dumbbell Press (Neutral Grip)",
        "Shoulders",
        "Dumbbell",
        {"grip": "Neutral", "base": "Seated Dumbbell Press"},
    ),
    ("Arnold Press", "Shoulders", "Dumbbell", {"base": "Seated Dumbbell Press"}),
    ("Machine Shoulder Press", "Shoulders", "Machine", {}),
    (
        "Machine Shoulder Press (Neutral Grip)",
        "Shoulders",
        "Machine",
        {"grip": "Neutral", "base": "Machine Shoulder Press"},
    ),
    ("Plate-Loaded Shoulder Press", "Shoulders", "Plate-Loaded", {}),
    (
        "Plate-Loaded Shoulder Press (Neutral Grip)",
        "Shoulders",
        "Plate-Loaded",
        {"grip": "Neutral", "base": "Plate-Loaded Shoulder Press"},
    ),
    ("Lateral Raise", "Shoulders", "Dumbbell", {}),
    ("Cable Lateral Raise", "Shoulders", "Cable", {"attachment": "Single Handle"}),
    ("Machine Lateral Raise", "Shoulders", "Machine", {}),
    ("Front Raise", "Shoulders", "Dumbbell", {}),
    ("Cable Front Raise", "Shoulders", "Cable", {"attachment": "Straight Bar"}),
    ("Rear Delt Fly", "Shoulders", "Dumbbell", {}),
    ("Cable Reverse Fly", "Shoulders", "Cable", {}),
    ("Reverse Pec Deck", "Shoulders", "Machine", {}),
    ("Face Pull", "Shoulders", "Cable", {"attachment": "Rope"}),
    ("Barbell Shrug", "Shoulders", "Barbell", {}),
    ("Dumbbell Shrug", "Shoulders", "Dumbbell", {}),
    ("Upright Row", "Shoulders", "Barbell", {}),
    (
        "Upright Row (Wide Grip)",
        "Shoulders",
        "Barbell",
        {"width": "Wide", "base": "Upright Row"},
    ),
    ("Cable Upright Row", "Shoulders", "Cable", {"attachment": "Straight Bar"}),
    # ── Arms: biceps / forearms ──────────────────────────────────────────────
    ("Barbell Curl", "Arms", "Barbell", {"grip": "Underhand"}),
    ("Reverse Curl", "Arms", "Barbell", {"grip": "Overhand", "base": "Barbell Curl"}),
    (
        "Barbell Curl (Close Grip)",
        "Arms",
        "Barbell",
        {"grip": "Underhand", "width": "Close", "base": "Barbell Curl"},
    ),
    (
        "Barbell Curl (Wide Grip)",
        "Arms",
        "Barbell",
        {"grip": "Underhand", "width": "Wide", "base": "Barbell Curl"},
    ),
    ("EZ Bar Curl", "Arms", "EZ Bar", {}),
    ("Bicep Curl", "Arms", "Dumbbell", {"grip": "Underhand"}),
    ("Hammer Curl", "Arms", "Dumbbell", {"grip": "Neutral", "base": "Bicep Curl"}),
    ("Incline Dumbbell Curl", "Arms", "Dumbbell", {}),
    ("Concentration Curl", "Arms", "Dumbbell", {}),
    ("Spider Curl", "Arms", "Dumbbell", {}),
    ("Preacher Curl", "Arms", "EZ Bar", {}),
    ("Dumbbell Preacher Curl", "Arms", "Dumbbell", {}),
    ("Machine Preacher Curl", "Arms", "Machine", {}),
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
    ("Overhead Cable Extension", "Arms", "Cable", {"attachment": "Rope"}),
    ("Tricep Extension", "Arms", "Dumbbell", {}),
    ("Machine Tricep Extension", "Arms", "Machine", {}),
    # ── Legs: squats ─────────────────────────────────────────────────────────
    ("Back Squat", "Legs", "Barbell", {}),
    ("Box Squat", "Legs", "Barbell", {"base": "Back Squat"}),
    ("Front Squat", "Legs", "Barbell", {}),
    ("Zercher Squat", "Legs", "Barbell", {}),
    ("Smith Machine Squat", "Legs", "Smith Machine", {}),
    ("Belt Squat", "Legs", "Plate-Loaded", {}),
    ("Goblet Squat", "Legs", "Dumbbell", {}),
    ("Pistol Squat", "Legs", "Bodyweight", {}),
    ("Hack Squat", "Legs", "Plate-Loaded", {}),
    ("Pendulum Squat", "Legs", "Plate-Loaded", {}),
    ("Leg Press", "Legs", "Plate-Loaded", {}),
    ("Single-Leg Leg Press", "Legs", "Plate-Loaded", {"base": "Leg Press"}),
    ("Seated Leg Press", "Legs", "Machine", {}),
    (
        "Single-Leg Seated Leg Press",
        "Legs",
        "Machine",
        {"base": "Seated Leg Press"},
    ),
    # ── Legs: hinges ─────────────────────────────────────────────────────────
    ("Romanian Deadlift", "Legs", "Barbell", {}),
    ("Dumbbell Romanian Deadlift", "Legs", "Dumbbell", {}),
    ("Stiff-Leg Deadlift", "Legs", "Barbell", {}),
    ("Single-Leg Deadlift", "Legs", "Dumbbell", {}),
    ("Hip Thrust", "Legs", "Barbell", {}),
    ("Machine Hip Thrust", "Legs", "Machine", {}),
    ("Glute Bridge", "Legs", "Bodyweight", {}),
    ("Cable Kickback", "Legs", "Cable", {"attachment": "Ankle Strap"}),
    # ── Legs: single-leg work ────────────────────────────────────────────────
    ("Bulgarian Split Squat", "Legs", "Dumbbell", {}),
    ("Walking Lunge", "Legs", "Dumbbell", {}),
    ("Reverse Lunge", "Legs", "Dumbbell", {}),
    ("Barbell Lunge", "Legs", "Barbell", {}),
    ("Static Lunge", "Legs", "Bodyweight", {}),
    ("Step-Up", "Legs", "Dumbbell", {}),
    # ── Legs: machines & calves ──────────────────────────────────────────────
    ("Leg Extension", "Legs", "Machine", {}),
    ("Single-Leg Extension", "Legs", "Machine", {"base": "Leg Extension"}),
    ("Leg Curl", "Legs", "Machine", {}),
    ("Seated Leg Curl", "Legs", "Machine", {}),
    ("Standing Leg Curl", "Legs", "Machine", {}),
    ("Glute Ham Raise", "Legs", "Machine", {}),
    ("Nordic Hamstring Curl", "Legs", "Bodyweight", {}),
    ("Hip Abduction", "Legs", "Machine", {}),
    ("Hip Adduction", "Legs", "Machine", {}),
    ("Calf Raise", "Legs", "Bodyweight", {}),
    ("Standing Calf Raise", "Legs", "Machine", {}),
    ("Seated Calf Raise", "Legs", "Machine", {}),
    ("Calf Press", "Legs", "Plate-Loaded", {}),
    # ── Core ─────────────────────────────────────────────────────────────────
    ("Plank", "Core", "Bodyweight", {}),
    ("Side Plank", "Core", "Bodyweight", {}),
    ("Hanging Leg Raise", "Core", "Bodyweight", {}),
    ("Hanging Knee Raise", "Core", "Bodyweight", {"base": "Hanging Leg Raise"}),
    ("Cable Crunch", "Core", "Cable", {"attachment": "Rope"}),
    ("Machine Crunch", "Core", "Machine", {}),
    ("Cable Woodchop", "Core", "Cable", {"attachment": "Single Handle"}),
    ("Russian Twist", "Core", "Bodyweight", {}),
    ("Ab Wheel Rollout", "Core", "Other", {}),
    ("Weighted Sit-Up", "Core", "Bodyweight", {}),
    ("Decline Sit-Up", "Core", "Bodyweight", {}),
    ("Dead Bug", "Core", "Bodyweight", {}),
    # ── Olympic / full body ──────────────────────────────────────────────────
    ("Clean and Jerk", "Full Body", "Barbell", {}),
    ("Power Clean", "Full Body", "Barbell", {}),
    ("Snatch", "Full Body", "Barbell", {}),
    ("Thruster", "Full Body", "Barbell", {}),
    ("Kettlebell Swing", "Full Body", "Kettlebell", {}),
    ("Farmer's Walk", "Full Body", "Dumbbell", {}),
    # ── Systematic variant fill (review round 2) ─────────────────────────────
    # Chest
    (
        "Decline Dumbbell Press (Neutral Grip)",
        "Chest",
        "Dumbbell",
        {"grip": "Neutral", "base": "Decline Dumbbell Press"},
    ),
    (
        "Incline Machine Chest Press (Neutral Grip)",
        "Chest",
        "Machine",
        {"grip": "Neutral", "base": "Incline Machine Chest Press"},
    ),
    (
        "Decline Machine Chest Press (Neutral Grip)",
        "Chest",
        "Machine",
        {"grip": "Neutral", "base": "Decline Machine Chest Press"},
    ),
    (
        "Plate-Loaded Incline Chest Press (Neutral Grip)",
        "Chest",
        "Plate-Loaded",
        {"grip": "Neutral", "base": "Plate-Loaded Incline Chest Press"},
    ),
    (
        "Plate-Loaded Decline Chest Press (Neutral Grip)",
        "Chest",
        "Plate-Loaded",
        {"grip": "Neutral", "base": "Plate-Loaded Decline Chest Press"},
    ),
    ("High-to-Low Cable Fly", "Chest", "Cable", {"base": "Cable Fly"}),
    (
        "Single-Arm Cable Fly",
        "Chest",
        "Cable",
        {"attachment": "Single Handle", "base": "Cable Fly"},
    ),
    ("Push-Up (Wide Grip)", "Chest", "Bodyweight", {"width": "Wide", "base": "Push-Up"}),
    ("Incline Push-Up", "Chest", "Bodyweight", {}),
    ("Decline Push-Up", "Chest", "Bodyweight", {}),
    # Back
    (
        "Pendlay Row (Wide Grip)",
        "Back",
        "Barbell",
        {"grip": "Overhand", "width": "Wide", "base": "Pendlay Row"},
    ),
    (
        "Smith Machine Row (Close Grip)",
        "Back",
        "Smith Machine",
        {"width": "Close", "base": "Smith Machine Row"},
    ),
    (
        "Smith Machine Row (Wide Grip)",
        "Back",
        "Smith Machine",
        {"width": "Wide", "base": "Smith Machine Row"},
    ),
    (
        "Chest Supported Row (Neutral Grip)",
        "Back",
        "Machine",
        {"grip": "Neutral", "base": "Chest Supported Row"},
    ),
    (
        "Chest Supported Row (Wide Grip)",
        "Back",
        "Machine",
        {"grip": "Overhand", "width": "Wide", "base": "Chest Supported Row"},
    ),
    (
        "Machine Row (Neutral Grip)",
        "Back",
        "Machine",
        {"grip": "Neutral", "base": "Machine Row"},
    ),
    (
        "Plate-Loaded Row (Neutral Grip)",
        "Back",
        "Plate-Loaded",
        {"grip": "Neutral", "base": "Plate-Loaded Row"},
    ),
    (
        "Seated Cable Row (Rope)",
        "Back",
        "Cable",
        {"grip": "Neutral", "attachment": "Rope", "base": "Seated Cable Row"},
    ),
    (
        "Lat Pulldown (Rope)",
        "Back",
        "Cable",
        {"grip": "Neutral", "attachment": "Rope", "base": "Lat Pulldown"},
    ),
    (
        "Machine Lat Pulldown (Wide Grip)",
        "Back",
        "Machine",
        {"grip": "Overhand", "width": "Wide", "base": "Machine Lat Pulldown"},
    ),
    (
        "Plate-Loaded Lat Pulldown (Wide Grip)",
        "Back",
        "Plate-Loaded",
        {"grip": "Overhand", "width": "Wide", "base": "Plate-Loaded Lat Pulldown"},
    ),
    (
        "Cable Pullover (Straight Bar)",
        "Back",
        "Cable",
        {"attachment": "Straight Bar", "base": "Cable Pullover"},
    ),
    # Shoulders
    (
        "Machine Shoulder Press (Wide Grip)",
        "Shoulders",
        "Machine",
        {"grip": "Overhand", "width": "Wide", "base": "Machine Shoulder Press"},
    ),
    (
        "Plate-Loaded Shoulder Press (Wide Grip)",
        "Shoulders",
        "Plate-Loaded",
        {"grip": "Overhand", "width": "Wide", "base": "Plate-Loaded Shoulder Press"},
    ),
    (
        "Smith Machine Shoulder Press (Wide Grip)",
        "Shoulders",
        "Smith Machine",
        {"width": "Wide", "base": "Smith Machine Shoulder Press"},
    ),
    ("Upright Row (Close Grip)", "Shoulders", "Barbell", {"width": "Close", "base": "Upright Row"}),
    (
        "Cable Upright Row (Rope)",
        "Shoulders",
        "Cable",
        {"attachment": "Rope", "base": "Cable Upright Row"},
    ),
    # Arms
    ("EZ Bar Curl (Close Grip)", "Arms", "EZ Bar", {"width": "Close", "base": "EZ Bar Curl"}),
    ("EZ Bar Curl (Wide Grip)", "Arms", "EZ Bar", {"width": "Wide", "base": "EZ Bar Curl"}),
    ("Reverse EZ Bar Curl", "Arms", "EZ Bar", {"grip": "Overhand", "base": "EZ Bar Curl"}),
    ("Preacher Curl (Close Grip)", "Arms", "EZ Bar", {"width": "Close", "base": "Preacher Curl"}),
    ("Preacher Curl (Wide Grip)", "Arms", "EZ Bar", {"width": "Wide", "base": "Preacher Curl"}),
    (
        "Cable Curl (EZ Bar)",
        "Arms",
        "Cable",
        {"grip": "Underhand", "attachment": "EZ Bar", "base": "Cable Curl"},
    ),
    (
        "Reverse Cable Curl",
        "Arms",
        "Cable",
        {"grip": "Overhand", "attachment": "Straight Bar", "base": "Cable Curl"},
    ),
    ("Reverse Wrist Curl", "Arms", "Dumbbell", {"grip": "Overhand", "base": "Wrist Curl"}),
    (
        "Overhead Cable Extension (Straight Bar)",
        "Arms",
        "Cable",
        {"attachment": "Straight Bar", "base": "Overhead Cable Extension"},
    ),
    # Legs — stance is the hand-equivalent for lower body
    ("Back Squat (Wide Stance)", "Legs", "Barbell", {"base": "Back Squat"}),
    ("Back Squat (Narrow Stance)", "Legs", "Barbell", {"base": "Back Squat"}),
    (
        "Smith Machine Squat (Wide Stance)",
        "Legs",
        "Smith Machine",
        {"base": "Smith Machine Squat"},
    ),
    ("Leg Press (Wide Stance)", "Legs", "Plate-Loaded", {"base": "Leg Press"}),
    ("Leg Press (Narrow Stance)", "Legs", "Plate-Loaded", {"base": "Leg Press"}),
    ("Leg Press (High Feet)", "Legs", "Plate-Loaded", {"base": "Leg Press"}),
    ("Hack Squat (Wide Stance)", "Legs", "Plate-Loaded", {"base": "Hack Squat"}),
    ("Single-Leg Calf Raise", "Legs", "Bodyweight", {"base": "Calf Raise"}),
    ("Leg Curl (Single-Leg)", "Legs", "Machine", {"base": "Leg Curl"}),
    ("Seated Leg Curl (Single-Leg)", "Legs", "Machine", {"base": "Seated Leg Curl"}),
    ("Single-Leg Hip Thrust", "Legs", "Bodyweight", {"base": "Hip Thrust"}),
    ("Barbell Bulgarian Split Squat", "Legs", "Barbell", {}),
    # Core
    (
        "Cable Woodchop (High-to-Low)",
        "Core",
        "Cable",
        {"attachment": "Single Handle", "base": "Cable Woodchop"},
    ),
    (
        "Cable Woodchop (Low-to-High)",
        "Core",
        "Cable",
        {"attachment": "Single Handle", "base": "Cable Woodchop"},
    ),
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
