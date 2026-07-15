"""Strong CSV import + Strong-compatible export.

Strong's export: comma CSV with Date (%Y-%m-%d %H:%M:%S), Workout Name,
Duration ("1h 10m"), Exercise Name, Set Order, Weight, Reps, Distance,
Seconds, Notes, Workout Notes, RPE. Rows group into workouts by
(Date, Workout Name); cardio rows carry Distance/Seconds but no Reps and
are skipped (Forge tracks iron only).
"""
import csv
import io
import re
from collections import OrderedDict
from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from fastapi.responses import StreamingResponse
from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from backend.core.database import get_db
from backend.core.security import get_current_user
from backend.models import Exercise, SetEntry, User, Workout, WorkoutExercise
from backend.serializers import recompute_prs

router = APIRouter(tags=["import-export"])

MAX_UPLOAD = 10 * 1024 * 1024  # 10 MB

# Exercise name -> muscle group, carried over from the lifty importer.
_STRONG_MUSCLE_GROUP = {
    # Chest
    "bench press - close grip (barbell)": "Chest",
    "bench press (barbell)": "Chest",
    "bench press (dumbbell)": "Chest",
    "chest dip": "Chest",
    "chest fly": "Chest",
    "chest fly (band)": "Chest",
    "chest fly (single)": "Chest",
    "chest fly (under)": "Chest",
    "chest press (machine)": "Chest",
    "incline bench press (dumbbell)": "Chest",
    "incline bench press (smith machine)": "Chest",
    "incline chest press (machine)": "Chest",
    "iso-lateral chest press (machine)": "Chest",
    # Back
    "bent over one arm row (dumbbell)": "Back",
    "bent over row (barbell)": "Back",
    "iso-lateral row (machine)": "Back",
    "lat pulldown - underhand (band)": "Back",
    "lat pulldown - wide grip (cable)": "Back",
    "lat pulldown (cable)": "Back",
    "lat pulldown (close grip)": "Back",
    "lat pulldown (machine)": "Back",
    "lat pulldown (single arm)": "Back",
    "pull up (assisted)": "Back",
    "pullover (dumbbell)": "Back",
    "pullover (machine)": "Back",
    "seated row (cable)": "Back",
    "t bar row": "Back",
    # Shoulders
    "face pull (cable)": "Shoulders",
    "front raise (band)": "Shoulders",
    "front raise (cable)": "Shoulders",
    "front raise (dumbbell)": "Shoulders",
    "front raise (plate)": "Shoulders",
    "lateral raise (cable)": "Shoulders",
    "lateral raise (dumbbell)": "Shoulders",
    "lateral raise (machine)": "Shoulders",
    "overhead press (barbell)": "Shoulders",
    "overhead press (smith machine)": "Shoulders",
    "reverse fly (cable)": "Shoulders",
    "reverse fly (machine)": "Shoulders",
    "seated overhead press (dumbbell)": "Shoulders",
    "shoulder press (plate loaded)": "Shoulders",
    "shrug (dumbbell)": "Shoulders",
    "shrug (smith machine)": "Shoulders",
    # Arms
    "bench dip": "Arms",
    "bicep curl (barbell)": "Arms",
    "bicep curl (cable)": "Arms",
    "bicep curl (dumbbell)": "Arms",
    "bicep curl (machine)": "Arms",
    "cable kickback": "Arms",
    "dip machine": "Arms",
    "hammer curl (cable)": "Arms",
    "hammer curl (dumbbell)": "Arms",
    "incline curl (dumbbell)": "Arms",
    "preacher curl (barbell)": "Arms",
    "preacher curl (dumbbell)": "Arms",
    "preacher curl (machine)": "Arms",
    "reverse curl (barbell)": "Arms",
    "reverse curl (cable)": "Arms",
    "reverse curl (dumbbell)": "Arms",
    "single biceps curl (cable)": "Arms",
    "single triceps extension (cable)": "Arms",
    "skullcrusher (barbell)": "Arms",
    "skullcrusher (dumbbell)": "Arms",
    "triceps dip (assisted)": "Arms",
    "triceps extension": "Arms",
    "triceps extension (cable)": "Arms",
    "triceps extension (dumbbell)": "Arms",
    "triceps extension (machine)": "Arms",
    "triceps pushdown (cable - straight bar)": "Arms",
    # Legs
    "bulgarian split squat  (leg press)": "Legs",
    "hack squat": "Legs",
    "leg extension (machine)": "Legs",
    "leg press": "Legs",
    "lying leg curl (machine)": "Legs",
    "romanian deadlift (barbell)": "Legs",
    "seated leg press (machine)": "Legs",
    "squat (barbell)": "Legs",
    "standing calf raise (machine)": "Legs",
    "standing leg curl (machine)": "Legs",
    # Other
    "stretching": "Other",
}

_EQUIPMENT_KEYWORDS = {
    "barbell": "Barbell",
    "dumbbell": "Dumbbell",
    "cable": "Cable",
    "machine": "Machine",
    "smith machine": "Machine",
    "assisted": "Machine",
    "ez bar": "EZ Bar",
    "trap bar": "Trap Bar",
    "kettlebell": "Kettlebell",
    "bodyweight": "Bodyweight",
    "weighted": "Bodyweight",
}

_BODYWEIGHT_NAMES = re.compile(
    r"pull.?up|chin.?up|push.?up|\bdip\b|plank|sit.?up|leg raise|crunch|muscle.?up", re.I
)


def _guess_equipment(name: str) -> str:
    low = name.lower()
    for keyword, equipment in _EQUIPMENT_KEYWORDS.items():
        if keyword in low:
            return equipment
    if _BODYWEIGHT_NAMES.search(low):
        return "Bodyweight"
    return "Other"


def _parse_duration_seconds(value: str | None) -> int:
    hours = re.search(r"(\d+)h", value or "")
    minutes = re.search(r"(\d+)m", value or "")
    return (int(hours.group(1)) * 3600 if hours else 0) + (
        int(minutes.group(1)) * 60 if minutes else 0
    )


_EQUIPMENT_SUFFIX = re.compile(
    r"\s*\((barbell|dumbbell|cable|machine|smith machine|bodyweight|band|kettlebell|"
    r"plate|ez bar|trap bar|assisted)\)$"
)


def _match_exercise(cache: dict, name: str) -> Exercise | None:
    """Strong suffixes names with equipment — 'Bench Press (Barbell)'. Match the
    exact name first, then retry with the suffix stripped so imported history
    merges into the seeded exercise instead of forking a duplicate."""
    key = name.lower()
    if key in cache:
        return cache[key]
    stripped = _EQUIPMENT_SUFFIX.sub("", key).strip()
    return cache.get(stripped)


def _parse_date(value: str) -> datetime | None:
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%d.%m.%Y %H:%M", "%Y-%m-%d"):
        try:
            return datetime.strptime(value, fmt)
        except ValueError:
            continue
    return None


@router.post("/import/strong")
def import_strong(
    file: UploadFile = File(...),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    contents = file.file.read(MAX_UPLOAD + 1)
    if len(contents) > MAX_UPLOAD:
        raise HTTPException(status_code=413, detail="File too large (max 10 MB)")
    try:
        text = contents.decode("utf-8-sig")
    except UnicodeDecodeError:
        raise HTTPException(status_code=400, detail="File is not UTF-8 text")

    # Strong has shipped both comma- and semicolon-delimited exports
    delimiter = ";" if text.splitlines()[0].count(";") > text.splitlines()[0].count(",") else ","
    reader = csv.DictReader(io.StringIO(text), delimiter=delimiter)
    if reader.fieldnames is None or "Date" not in reader.fieldnames:
        raise HTTPException(status_code=400, detail="Not a Strong export (no Date column)")

    groups: OrderedDict[tuple[str, str], list[dict]] = OrderedDict()
    for row in reader:
        date = (row.get("Date") or "").strip()
        name = (row.get("Workout Name") or "").strip()
        if date:
            groups.setdefault((date, name or "Workout"), []).append(row)

    # Exercise cache + duplicate-workout guard (start time, second resolution)
    exercise_cache = {
        e.name.lower(): e
        for e in db.execute(
            select(Exercise).where(or_(Exercise.owner_id.is_(None), Exercise.owner_id == user.id))
        ).scalars()
    }
    existing_starts = {
        w.started_at.isoformat()[:19]
        for w in db.execute(select(Workout).where(Workout.owner_id == user.id)).scalars()
    }

    imported = skipped = created_exercises = imported_sets = 0

    for (date_str, workout_name), rows in groups.items():
        started_at = _parse_date(date_str)
        if started_at is None:
            skipped += 1
            continue
        if started_at.isoformat()[:19] in existing_starts:
            skipped += 1
            continue

        duration = _parse_duration_seconds(rows[0].get("Duration"))
        workout = Workout(
            owner_id=user.id,
            name=workout_name,
            started_at=started_at,
            finished_at=started_at + timedelta(seconds=duration or 1),
        )

        # Preserve exercise order of first appearance
        per_exercise: OrderedDict[str, list[dict]] = OrderedDict()
        for row in rows:
            exercise_name = (row.get("Exercise Name") or "").strip()
            if exercise_name:
                per_exercise.setdefault(exercise_name, []).append(row)

        position = 0
        for exercise_name, exercise_rows in per_exercise.items():
            sets: list[SetEntry] = []
            for row in exercise_rows:
                try:
                    reps = int(float(row.get("Reps") or 0))
                except (ValueError, TypeError):
                    reps = 0
                if reps <= 0:
                    continue  # cardio / duration rows have no reps
                try:
                    weight = float(row.get("Weight") or 0)
                except (ValueError, TypeError):
                    weight = 0.0
                sets.append(
                    SetEntry(
                        position=len(sets),
                        weight=weight,
                        reps=reps,
                        is_completed=True,
                        completed_at=started_at,
                    )
                )
            if not sets:
                continue

            key = exercise_name.lower()
            exercise = _match_exercise(exercise_cache, exercise_name)
            if exercise is None:
                exercise = Exercise(
                    name=exercise_name,
                    muscle_group=_STRONG_MUSCLE_GROUP.get(key, "Other"),
                    equipment=_guess_equipment(exercise_name),
                    owner_id=user.id,
                )
                db.add(exercise)
                db.flush()
                exercise_cache[key] = exercise
                created_exercises += 1

            we = WorkoutExercise(exercise_id=exercise.id, position=position)
            we.sets = sets
            workout.exercises.append(we)
            position += 1
            imported_sets += len(sets)

        if not workout.exercises:
            skipped += 1
            continue

        db.add(workout)
        existing_starts.add(started_at.isoformat()[:19])
        imported += 1

    db.commit()
    if imported:
        recompute_prs(db, user.id)

    return {
        "imported_workouts": imported,
        "skipped_workouts": skipped,
        "created_exercises": created_exercises,
        "imported_sets": imported_sets,
    }


@router.get("/export/strong")
def export_strong(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    workouts = (
        db.execute(
            select(Workout)
            .where(Workout.owner_id == user.id, Workout.finished_at.is_not(None))
            .order_by(Workout.started_at)
        )
        .scalars()
        .all()
    )
    exercises = {
        e.id: e
        for e in db.execute(
            select(Exercise).where(or_(Exercise.owner_id.is_(None), Exercise.owner_id == user.id))
        ).scalars()
    }

    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(
        ["Date", "Workout Name", "Duration", "Exercise Name", "Set Order", "Weight",
         "Reps", "Distance", "Seconds", "Notes", "Workout Notes", "RPE"]
    )
    for w in workouts:
        date = w.started_at.strftime("%Y-%m-%d %H:%M:%S")
        total = int((w.finished_at - w.started_at).total_seconds())
        duration = f"{total // 3600}h {total % 3600 // 60}m" if total >= 3600 else f"{max(1, total // 60)}m"
        for we in w.exercises:
            exercise = exercises.get(we.exercise_id)
            order = 0
            for s in we.sets:
                if not s.is_completed:
                    continue
                order += 1
                writer.writerow(
                    [date, w.name, duration, exercise.name if exercise else "Unknown",
                     order, s.weight if s.weight is not None else 0, s.reps or 0,
                     "", "", "", w.notes or "", ""]
                )

    output.seek(0)
    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition": "attachment; filename=forge_export.csv"},
    )
