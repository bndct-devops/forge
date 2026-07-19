"""Training statistics: totals, weekly streak, calendar, volume trend,
muscle-group split. Warm-up sets never count (same rule as workout totals)."""
import re
from collections import defaultdict
from datetime import date, timedelta

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from backend.core.clock import utcnow
from backend.core.database import get_db
from backend.core.security import get_current_user
from backend.models import Exercise, Measurement, SetEntry, User, Workout, WorkoutExercise
from backend.serializers import epley_1rm, workout_totals

router = APIRouter(prefix="/stats", tags=["stats"])

CALENDAR_WEEKS = 52  # a GitHub-style year, Monday-aligned
MUSCLE_TREND_WEEKS = 8
TREND_WEEKS = 12
SPLIT_DAYS = 30
# Gaps between set completions outside this band are drop-sets / interruptions,
# not rest, and would poison the averages
REST_MIN_SECONDS = 15
REST_MAX_SECONDS = 600
STALL_WINDOW_DAYS = 45
BLOCK_DAYS = 28
TIME_BUCKET_DAYS = 180
# Forecast guardrails: enough points to mean anything, near enough to believe
FORECAST_MIN_POINTS = 4
FORECAST_MAX_WEEKS = 26
# Form & fatigue: classic performance-management time constants (days)
FITNESS_TC = 42
FATIGUE_TC = 7
LOAD_CHART_DAYS = 90
# Detraining: a layoff starts at two weeks off a lift
DETRAIN_GAP_DAYS = 14

# Strength standards (barbell lifts only — machine numbers against barbell
# population standards would flatter): e1RM / bodyweight thresholds for
# Novice / Intermediate / Advanced / Elite, approximate and unisex.
STANDARD_LEVELS = ["Untrained", "Novice", "Intermediate", "Advanced", "Elite"]
STANDARDS = [
    ("Bench Press", r"bench|chest press", [0.50, 0.75, 1.00, 1.50, 2.00]),
    ("Squat", r"squat", [0.75, 1.00, 1.50, 2.00, 2.50]),
    ("Deadlift", r"deadlift", [1.00, 1.25, 1.75, 2.25, 2.75]),
    ("Overhead Press", r"overhead press|shoulder press|military|push press", [0.35, 0.55, 0.80, 1.05, 1.30]),
    ("Barbell Row", r"row", [0.50, 0.75, 1.00, 1.25, 1.50]),
]
STANDARD_EQUIPMENT = {"Barbell", "Trap Bar", "EZ Bar"}


def _week_start(d: date) -> date:
    return d - timedelta(days=d.weekday())


@router.get("/records")
def records(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """All-time bests per exercise, across everything ever logged."""
    rows = db.execute(
        select(SetEntry, Workout, WorkoutExercise.exercise_id)
        .join(WorkoutExercise, SetEntry.workout_exercise_id == WorkoutExercise.id)
        .join(Workout, WorkoutExercise.workout_id == Workout.id)
        .where(
            Workout.owner_id == user.id,
            Workout.finished_at.is_not(None),
            SetEntry.is_completed.is_(True),
            SetEntry.is_warmup.is_(False),
            SetEntry.reps.is_not(None),
        )
    ).all()
    exercises = {e.id: e for e in db.execute(select(Exercise)).scalars()}
    best: dict[int, dict] = {}
    for se, w, ex_id in rows:
        weight = se.weight or 0.0
        entry = best.setdefault(
            ex_id,
            {"best_weight": None, "best_1rm": None, "best_reps": None, "sessions": set()},
        )
        entry["sessions"].add(w.id)
        if weight > 0:
            if entry["best_weight"] is None or weight > entry["best_weight"]["weight"]:
                entry["best_weight"] = {"weight": weight, "reps": se.reps, "date": w.started_at}
            one_rm = round(epley_1rm(weight, se.reps), 1)
            if entry["best_1rm"] is None or one_rm > entry["best_1rm"]["value"]:
                entry["best_1rm"] = {"value": one_rm, "date": w.started_at}
        elif entry["best_reps"] is None or se.reps > entry["best_reps"]["reps"]:
            entry["best_reps"] = {"reps": se.reps, "date": w.started_at}
    result = []
    for ex_id, entry in best.items():
        exercise = exercises.get(ex_id)
        if exercise is None:
            continue
        result.append(
            {
                "exercise_id": ex_id,
                "name": exercise.name,
                "muscle_group": exercise.muscle_group,
                "best_weight": entry["best_weight"],
                "best_1rm": entry["best_1rm"],
                "best_reps": entry["best_reps"],
                "sessions": len(entry["sessions"]),
            }
        )
    result.sort(key=lambda r: r["name"].lower())
    return result


@router.get("")
def stats(
    tz_offset: int = 0,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    workouts = (
        db.execute(
            select(Workout)
            .where(Workout.owner_id == user.id, Workout.finished_at.is_not(None))
            .order_by(Workout.started_at)
        )
        .scalars()
        .all()
    )
    exercises = {e.id: e for e in db.execute(select(Exercise)).scalars()}

    today = utcnow().date()
    total_volume = 0.0
    total_sets = 0
    total_prs = 0
    by_day: dict[str, int] = defaultdict(int)
    volume_by_day: dict[date, float] = defaultdict(float)
    volume_by_week: dict[date, float] = defaultdict(float)
    workouts_by_week: dict[date, int] = defaultdict(int)
    trained_weeks: set[date] = set()
    split: dict[str, int] = defaultdict(int)
    split_since = today - timedelta(days=SPLIT_DAYS)
    last_by_group: dict[str, date] = {}
    total_time = 0
    weekday_counts: dict[int, int] = defaultdict(int)
    sessions_by_exercise: dict[int, int] = defaultdict(int)
    volume_by_month: dict[str, float] = defaultdict(float)
    rep_buckets: dict[str, int] = {"1–5": 0, "6–10": 0, "11–15": 0, "16+": 0}
    prs_by_month: dict[str, int] = defaultdict(int)
    # weekly max estimated 1RM per exercise, last 12 weeks
    e1rm_weeks: dict[int, dict[date, float]] = defaultdict(dict)
    e1rm_since = _week_start(today) - timedelta(weeks=TREND_WEEKS - 1)
    muscle_weeks: dict[str, dict] = defaultdict(lambda: defaultdict(int))
    trend_since = _week_start(today) - timedelta(weeks=MUSCLE_TREND_WEEKS - 1)
    rpe_by_week: dict[date, list[float]] = defaultdict(list)
    rest_by_week: dict[date, list[float]] = defaultdict(list)
    density_by_week: dict[date, list[float]] = defaultdict(list)
    # Chronological per-exercise session summaries, for stall detection
    stall_sessions: dict[int, list[dict]] = defaultdict(list)
    # Block comparison: last 28 days vs the 28 before
    block_since = today - timedelta(days=BLOCK_DAYS - 1)
    prev_block_since = block_since - timedelta(days=BLOCK_DAYS)
    block_group_sets: dict[str, list[int]] = defaultdict(lambda: [0, 0])  # [current, prev]
    block_totals = {"current": [0.0, 0], "previous": [0.0, 0]}  # volume, workouts
    block_lift_e1rm: dict[int, list[float]] = defaultdict(lambda: [0.0, 0.0])
    # Time-of-day: session e1RMs normalized per exercise, bucketed by local hour
    time_since = today - timedelta(days=TIME_BUCKET_DAYS)
    time_counts: dict[str, int] = defaultdict(int)
    time_volume: dict[str, float] = defaultdict(float)
    time_session_e1rm: list[tuple[int, str, float]] = []  # (exercise_id, bucket, e1rm)
    # Year in review
    year = today.year
    year_data = {
        "workouts": 0, "volume": 0.0, "sets": 0, "prs": 0,
        "month_volume": defaultdict(float), "sessions_by_exercise": defaultdict(int),
        "biggest_pr": None, "weeks": set(),
    }

    for w in workouts:
        totals = workout_totals(w)
        total_volume += totals["total_volume"]
        total_sets += totals["total_sets"]
        total_prs += totals["pr_count"]

        day = w.started_at.date()
        by_day[day.isoformat()] += 1
        volume_by_day[day] += totals["total_volume"]
        week = _week_start(day)
        trained_weeks.add(week)
        volume_by_week[week] += totals["total_volume"]
        workouts_by_week[week] += 1
        duration = int((w.finished_at - w.started_at).total_seconds())
        total_time += duration
        weekday_counts[day.weekday()] += 1
        if week >= e1rm_since and duration >= 60 and totals["total_volume"] > 0:
            density_by_week[week].append(totals["total_volume"] / (duration / 60))

        block_idx = 0 if day >= block_since else 1 if day >= prev_block_since else None
        if block_idx is not None:
            key = "current" if block_idx == 0 else "previous"
            block_totals[key][0] += totals["total_volume"]
            block_totals[key][1] += 1
        time_bucket = None
        if day >= time_since:
            local_hour = (w.started_at + timedelta(minutes=tz_offset)).hour
            time_bucket = (
                "Morning" if local_hour < 12 else "Afternoon" if local_hour < 17 else "Evening"
            )
            time_counts[time_bucket] += 1
            time_volume[time_bucket] += totals["total_volume"]
        if day.year == year:
            year_data["workouts"] += 1
            year_data["volume"] += totals["total_volume"]
            year_data["sets"] += totals["total_sets"]
            year_data["prs"] += totals["pr_count"]
            year_data["month_volume"][day.month] += totals["total_volume"]
            year_data["weeks"].add(week)
        volume_by_month[day.strftime("%Y-%m")] += totals["total_volume"]
        month_key = day.strftime("%Y-%m")
        for we in w.exercises:
            working = [s for s in we.sets if s.is_completed and not s.is_warmup]
            if working:
                sessions_by_exercise[we.exercise_id] += 1
            for st in working:
                if st.is_pr:
                    prs_by_month[month_key] += 1
                    if day.year == year and (st.weight or 0) > 0:
                        best = year_data["biggest_pr"]
                        if best is None or st.weight > best["weight"]:
                            year_data["biggest_pr"] = {
                                "exercise_id": we.exercise_id,
                                "weight": st.weight,
                                "reps": st.reps,
                            }
                if st.rpe is not None and week >= e1rm_since:
                    rpe_by_week[week].append(st.rpe)
                if day >= split_since and st.reps:
                    reps = st.reps
                    bucket = (
                        "1–5" if reps <= 5 else "6–10" if reps <= 10
                        else "11–15" if reps <= 15 else "16+"
                    )
                    rep_buckets[bucket] += 1
            if week >= e1rm_since and working:
                stamps = sorted(s.completed_at for s in working if s.completed_at is not None)
                for a, b in zip(stamps, stamps[1:]):
                    gap = (b - a).total_seconds()
                    if REST_MIN_SECONDS <= gap <= REST_MAX_SECONDS:
                        rest_by_week[week].append(gap)
            if working:
                top = max((s.weight or 0.0) for s in working)
                best_e1rm = max(
                    (epley_1rm(s.weight or 0, s.reps or 0) for s in working), default=0.0
                )
                if day.year == year:
                    year_data["sessions_by_exercise"][we.exercise_id] += 1
                if best_e1rm > 0:
                    if block_idx is not None:
                        cur = block_lift_e1rm[we.exercise_id]
                        cur[block_idx] = max(cur[block_idx], best_e1rm)
                    if time_bucket is not None:
                        time_session_e1rm.append((we.exercise_id, time_bucket, best_e1rm))
                stall_sessions[we.exercise_id].append(
                    {
                        "day": day,
                        "top": top,
                        "best": best_e1rm,
                        "has_target": bool(we.rep_max),
                        "hit": bool(we.rep_max)
                        and all((s.reps or 0) >= we.rep_max for s in working),
                    }
                )
            if week >= e1rm_since and working:
                best = max(
                    (epley_1rm(st.weight or 0, st.reps or 0) for st in working),
                    default=0.0,
                )
                if best > 0:
                    prev = e1rm_weeks[we.exercise_id].get(week, 0.0)
                    e1rm_weeks[we.exercise_id][week] = max(prev, best)

        for we in w.exercises:
            exercise = exercises.get(we.exercise_id)
            if exercise is None:
                continue
            working_sets = sum(1 for s in we.sets if s.is_completed and not s.is_warmup)
            if working_sets == 0:
                continue
            prev = last_by_group.get(exercise.muscle_group)
            if prev is None or day > prev:
                last_by_group[exercise.muscle_group] = day
            if day >= split_since:
                split[exercise.muscle_group] += working_sets
            if week >= trend_since:
                muscle_weeks[exercise.muscle_group][week] += working_sets
            if block_idx is not None:
                block_group_sets[exercise.muscle_group][block_idx] += working_sets

    # Streak: consecutive trained weeks ending at the current week — or the
    # previous one, so the streak isn't "broken" before this week's session
    this_week = _week_start(today)
    streak = 0
    cursor = this_week if this_week in trained_weeks else this_week - timedelta(weeks=1)
    while cursor in trained_weeks:
        streak += 1
        cursor -= timedelta(weeks=1)

    # Start on a Monday so heatmap columns are true calendar weeks
    calendar_start = _week_start(today) - timedelta(weeks=CALENDAR_WEEKS)
    calendar_days = (today - calendar_start).days + 1
    calendar = [
        {"date": (calendar_start + timedelta(days=i)).isoformat(),
         "workouts": by_day.get((calendar_start + timedelta(days=i)).isoformat(), 0)}
        for i in range(calendar_days)
    ]

    weeks = []
    for i in range(TREND_WEEKS - 1, -1, -1):
        week = this_week - timedelta(weeks=i)
        rpes = rpe_by_week.get(week)
        weeks.append(
            {
                "week_start": week.isoformat(),
                "volume": round(volume_by_week.get(week, 0.0), 1),
                "workouts": workouts_by_week.get(week, 0),
                "avg_rpe": round(sum(rpes) / len(rpes), 1) if rpes else None,
            }
        )

    # Gap nudges: groups in the user's actual rotation (trained in the last
    # 60 days) that have gone quiet for 9+ days. Silent when the user hasn't
    # trained at all recently — the streak UI covers absence.
    nudges = []
    if user.gap_nudges and last_by_group:
        most_recent = max(last_by_group.values())
        if (today - most_recent).days <= 14:
            for group, last in last_by_group.items():
                if group == "Other":  # catch-all bucket, not a body part to balance
                    continue
                days = (today - last).days
                if 9 <= days and last >= today - timedelta(days=60):
                    nudges.append({"group": group, "days": days})
            nudges.sort(key=lambda n: -n["days"])
            nudges = nudges[:2]

    # Longest streak ever (consecutive trained weeks)
    longest = run = 0
    prev_week = None
    for wk in sorted(trained_weeks):
        run = run + 1 if prev_week is not None and wk - prev_week == timedelta(weeks=1) else 1
        longest = max(longest, run)
        prev_week = wk

    extras = None
    if workouts:
        first_week = _week_start(workouts[0].started_at.date())
        weeks_active = max(1, (this_week - first_week).days // 7 + 1)
        top_eid = max(sessions_by_exercise, key=sessions_by_exercise.get, default=None)
        top_exercise = exercises.get(top_eid) if top_eid else None
        busiest = max(weekday_counts, key=weekday_counts.get, default=None)
        weekday_names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        this_month = today.strftime("%Y-%m")
        prev_month_date = (today.replace(day=1) - timedelta(days=1))
        extras = {
            "avg_per_week": round(len(workouts) / weeks_active, 1),
            "avg_duration_seconds": total_time // len(workouts),
            "avg_volume": round(total_volume / len(workouts), 1),
            "total_time_seconds": total_time,
            "longest_streak_weeks": longest,
            "top_exercise": {
                "name": top_exercise.name,
                "sessions": sessions_by_exercise[top_eid],
            }
            if top_exercise
            else None,
            "busiest_weekday": weekday_names[busiest] if busiest is not None else None,
            "month_volume": round(volume_by_month.get(this_month, 0.0), 1),
            "prev_month_volume": round(
                volume_by_month.get(prev_month_date.strftime("%Y-%m"), 0.0), 1
            ),
        }

    # Trend payloads
    weekday_names_short = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
    weekday_distribution = [
        {"day": weekday_names_short[i], "workouts": weekday_counts.get(i, 0)} for i in range(7)
    ]
    months = []
    cursor_month = today.replace(day=1)
    for _ in range(6):
        months.append(cursor_month)
        cursor_month = (cursor_month - timedelta(days=1)).replace(day=1)
    prs_monthly = [
        {
            "month": m.strftime("%b"),
            "prs": prs_by_month.get(m.strftime("%Y-%m"), 0),
        }
        for m in reversed(months)
    ]
    top_ids = sorted(sessions_by_exercise, key=sessions_by_exercise.get, reverse=True)[:3]
    top_ids = [eid for eid in top_ids if e1rm_weeks.get(eid)]
    top_names = [exercises[eid].name for eid in top_ids if eid in exercises]
    top_lift_weeks = []
    for i in range(TREND_WEEKS - 1, -1, -1):
        wk = this_week - timedelta(weeks=i)
        row: dict = {"week_start": wk.isoformat()}
        for eid in top_ids:
            if eid in exercises:
                value = e1rm_weeks[eid].get(wk)
                row[exercises[eid].name] = round(value, 1) if value else None
        top_lift_weeks.append(row)

    # Pacing: measured rest between sets (completed_at deltas) and volume/min
    pacing = None
    if rest_by_week or density_by_week:
        pacing_weeks = []
        for i in range(TREND_WEEKS - 1, -1, -1):
            wk = this_week - timedelta(weeks=i)
            rests = rest_by_week.get(wk)
            dens = density_by_week.get(wk)
            pacing_weeks.append(
                {
                    "week_start": wk.isoformat(),
                    "avg_rest_seconds": round(sum(rests) / len(rests)) if rests else None,
                    "density": round(sum(dens) / len(dens), 1) if dens else None,
                }
            )
        all_rests = [g for v in rest_by_week.values() for g in v]
        all_dens = [d for v in density_by_week.values() for d in v]
        pacing = {
            "weeks": pacing_weeks,
            "avg_rest_seconds": round(sum(all_rests) / len(all_rests)) if all_rests else None,
            "avg_density": round(sum(all_dens) / len(all_dens), 1) if all_dens else None,
        }

    bodyweights = (
        db.execute(
            select(Measurement)
            .where(Measurement.user_id == user.id, Measurement.kind == "Weight")
            .order_by(Measurement.measured_at)
        )
        .scalars()
        .all()
    )

    # Relative strength: top-lift e1RM over bodyweight at that week's end,
    # carrying the latest measurement forward between weigh-ins
    relative = None
    if top_ids:
        if bodyweights:
            def bw_at(d: date) -> float:
                value = bodyweights[0].value
                for m in bodyweights:
                    if m.measured_at.date() <= d:
                        value = m.value
                    else:
                        break
                return value

            rel_weeks = []
            for i in range(TREND_WEEKS - 1, -1, -1):
                wk = this_week - timedelta(weeks=i)
                row = {"week_start": wk.isoformat()}
                bw = bw_at(wk + timedelta(days=6))
                for eid in top_ids:
                    if eid in exercises:
                        value = e1rm_weeks[eid].get(wk)
                        row[exercises[eid].name] = (
                            round(value / bw, 2) if value and bw > 0 else None
                        )
                rel_weeks.append(row)
            relative = {"names": top_names, "weeks": rel_weeks}

    # Stalled lifts: same top weight three sessions running without hitting the
    # rep target (or, with no target, without the estimated 1RM moving)
    stalls = []
    if user.deload_hints:
        for eid, sess in stall_sessions.items():
            exercise = exercises.get(eid)
            if exercise is None or len(sess) < 3:
                continue
            if (today - sess[-1]["day"]).days > STALL_WINDOW_DAYS:
                continue
            last3 = sess[-3:]
            top = last3[-1]["top"]
            if top <= 0 or any(abs(s["top"] - top) > 0.01 for s in last3):
                continue
            if any(s["hit"] for s in last3):
                continue
            if not any(s["has_target"] for s in last3) and last3[-1]["best"] > last3[0]["best"] + 0.01:
                continue
            run = 0
            for s in reversed(sess):
                if abs(s["top"] - top) > 0.01:
                    break
                run += 1
            stalls.append(
                {
                    "exercise_id": eid,
                    "name": exercise.name,
                    "weight": top,
                    "sessions": run,
                    "last_day": sess[-1]["day"].isoformat(),
                }
            )
        stalls.sort(key=lambda s: -s["sessions"])
        stalls = stalls[:5]

    # Block comparison: needs both windows trained, else there is no "vs"
    blocks = None
    if block_totals["current"][1] > 0 and block_totals["previous"][1] > 0:
        groups_cmp = [
            {"group": g, "current": v[0], "previous": v[1]}
            for g, v in block_group_sets.items()
            if v[0] or v[1]
        ]
        groups_cmp.sort(key=lambda x: -(x["current"] + x["previous"]))
        lifts_cmp = []
        for eid in top_ids:
            cur, prev = block_lift_e1rm.get(eid, [0.0, 0.0])
            if eid in exercises and cur > 0 and prev > 0:
                lifts_cmp.append(
                    {"name": exercises[eid].name, "current": round(cur, 1), "previous": round(prev, 1)}
                )
        blocks = {
            "days": BLOCK_DAYS,
            "current": {
                "volume": round(block_totals["current"][0], 1),
                "workouts": block_totals["current"][1],
            },
            "previous": {
                "volume": round(block_totals["previous"][0], 1),
                "workouts": block_totals["previous"][1],
            },
            "groups": groups_cmp[:8],
            "lifts": lifts_cmp,
        }

    # Time of day: each lift's session e1RM normalized against its own mean,
    # so "index 103" means you lift 3% above your average in that slot
    times = None
    if len([b for b in ("Morning", "Afternoon", "Evening") if time_counts.get(b)]) >= 2:
        by_ex: dict[int, list[tuple[str, float]]] = defaultdict(list)
        for eid, bucket, v in time_session_e1rm:
            by_ex[eid].append((bucket, v))
        norm_by_bucket: dict[str, list[float]] = defaultdict(list)
        for eid, entries in by_ex.items():
            if len({b for b, _ in entries}) < 2:
                continue  # a lift trained in only one slot says nothing comparative
            ex_mean = sum(v for _, v in entries) / len(entries)
            for b, v in entries:
                norm_by_bucket[b].append(v / ex_mean)
        times = [
            {
                "bucket": b,
                "workouts": time_counts[b],
                "avg_volume": round(time_volume[b] / time_counts[b], 1),
                "index": (
                    round(100 * sum(norm_by_bucket[b]) / len(norm_by_bucket[b]))
                    if len(norm_by_bucket.get(b, [])) >= 3
                    else None
                ),
            }
            for b in ("Morning", "Afternoon", "Evening")
            if time_counts.get(b)
        ]

    # Trajectory: least-squares slope over the weekly e1RM points; next
    # round-number milestone only when it lands inside a believable horizon
    forecast = []
    for eid in top_ids:
        if eid not in exercises:
            continue
        pts = sorted(e1rm_weeks.get(eid, {}).items())
        if len(pts) < FORECAST_MIN_POINTS:
            continue
        xs = [(d - pts[0][0]).days / 7 for d, _ in pts]
        ys = [v for _, v in pts]
        if xs[-1] - xs[0] < 4:
            continue
        n = len(xs)
        mx, my = sum(xs) / n, sum(ys) / n
        denom = sum((x - mx) ** 2 for x in xs)
        if denom == 0:
            continue
        slope = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / denom
        current = max(ys)
        entry = {
            "name": exercises[eid].name,
            "current": round(current, 1),
            "slope": round(slope, 2),
            "milestone": None,
            "eta": None,
        }
        if slope >= 0.05:
            milestone = (int(current // 10) + 1) * 10
            weeks_to = (milestone - current) / slope
            if weeks_to <= FORECAST_MAX_WEEKS:
                entry["milestone"] = milestone
                entry["eta"] = (today + timedelta(weeks=weeks_to)).isoformat()
        forecast.append(entry)

    # Form & fatigue: exponentially-weighted daily volume — fitness (42d),
    # fatigue (7d), form = the gap. The lifting version of a PMC chart.
    load = None
    if workouts and (today - workouts[0].started_at.date()).days >= 14:
        ctl = atl = 0.0
        chart_since = today - timedelta(days=LOAD_CHART_DAYS - 1)
        load_days = []
        d = workouts[0].started_at.date()
        while d <= today:
            v = volume_by_day.get(d, 0.0)
            ctl += (v - ctl) / FITNESS_TC
            atl += (v - atl) / FATIGUE_TC
            if d >= chart_since:
                load_days.append(
                    {
                        "date": d.isoformat(),
                        "fitness": round(ctl, 1),
                        "fatigue": round(atl, 1),
                        "form": round(ctl - atl, 1),
                    }
                )
            d += timedelta(days=1)
        form_pct = (ctl - atl) / ctl if ctl > 0 else 0.0
        load = {
            "days": load_days,
            "status": (
                "fresh" if form_pct > 0.10 else "overreaching" if form_pct < -0.30 else "productive"
            ),
        }

    # Recovery sweet spot: session e1RM vs that lift's recent baseline,
    # bucketed by how many rest days preceded it
    recovery = None
    rec_samples: dict[str, list[float]] = defaultdict(list)
    for eid, sess in stall_sessions.items():
        if len(sess) < 4:
            continue
        for i in range(3, len(sess)):
            cur = sess[i]
            prev3 = [s["best"] for s in sess[i - 3 : i] if s["best"] > 0]
            if len(prev3) < 3 or cur["best"] <= 0:
                continue
            gap = (cur["day"] - sess[i - 1]["day"]).days
            if not 1 <= gap <= 10:
                continue
            bucket = str(gap) if gap <= 3 else "4+"
            rec_samples[bucket].append(cur["best"] / (sum(prev3) / 3))
    solid = {b: v for b, v in rec_samples.items() if len(v) >= 3}
    if len(solid) >= 2 and sum(len(v) for v in solid.values()) >= 12:
        recovery = [
            {
                "bucket": b,
                "pct": round((sum(v) / len(v) - 1) * 100, 1),
                "n": len(v),
            }
            for b, v in sorted(solid.items(), key=lambda x: (len(x[0]), x[0]))
        ]

    # Detraining: every layoff is a natural experiment — e1RM lost per week
    # away, averaged over gaps of two weeks or more
    detraining = None
    detrain_events = []
    for eid, sess in stall_sessions.items():
        for i in range(1, len(sess)):
            gap_days = (sess[i]["day"] - sess[i - 1]["day"]).days
            if gap_days < DETRAIN_GAP_DAYS:
                continue
            before, after = sess[i - 1]["best"], sess[i]["best"]
            if before <= 0 or after <= 0:
                continue
            per_week = (1 - after / before) * 100 / (gap_days / 7)
            if -10 <= per_week <= 10:  # outliers are form/exercise changes, not detraining
                detrain_events.append(per_week)
    if len(detrain_events) >= 3:
        detraining = {
            "pct_per_week": round(sum(detrain_events) / len(detrain_events), 1),
            "events": len(detrain_events),
        }

    # Strength standards: all-time best e1RM per barbell lift family over
    # current bodyweight, scored against population thresholds
    standards = None
    if bodyweights:
        bw = bodyweights[-1].value
        best_by_ex: dict[int, float] = {}
        for eid, sess in stall_sessions.items():
            best_by_ex[eid] = max(s["best"] for s in sess)
        rows_std = []
        for lift, pattern, thresholds in STANDARDS:
            rx = re.compile(pattern, re.I)
            best = 0.0
            for eid, val in best_by_ex.items():
                ex = exercises.get(eid)
                if ex and ex.equipment in STANDARD_EQUIPMENT and rx.search(ex.name):
                    best = max(best, val)
            if best <= 0 or bw <= 0:
                continue
            ratio = best / bw
            if ratio < thresholds[0]:
                score = ratio / thresholds[0]
            elif ratio >= thresholds[-1]:
                score = 5.0
            else:
                score = next(
                    i + 1 + (ratio - thresholds[i]) / (thresholds[i + 1] - thresholds[i])
                    for i in range(len(thresholds) - 1)
                    if thresholds[i] <= ratio < thresholds[i + 1]
                )
            rows_std.append(
                {
                    "lift": lift,
                    "ratio": round(ratio, 2),
                    "score": round(score, 2),
                    "level": STANDARD_LEVELS[max(0, min(4, int(score) - 1))] if score < 5 else "Elite",
                }
            )
        if rows_std:
            standards = rows_std

    year_review = None
    if year_data["workouts"]:
        top_eid = max(
            year_data["sessions_by_exercise"],
            key=year_data["sessions_by_exercise"].get,
            default=None,
        )
        longest_year = run = 0
        prev_week = None
        for wk in sorted(year_data["weeks"]):
            run = run + 1 if prev_week is not None and wk - prev_week == timedelta(weeks=1) else 1
            longest_year = max(longest_year, run)
            prev_week = wk
        busiest = max(year_data["month_volume"], key=year_data["month_volume"].get)
        bp = year_data["biggest_pr"]
        pr_ex = exercises.get(bp["exercise_id"]) if bp else None
        year_review = {
            "year": year,
            "workouts": year_data["workouts"],
            "volume": round(year_data["volume"], 1),
            "sets": year_data["sets"],
            "prs": year_data["prs"],
            "longest_streak_weeks": longest_year,
            "top_exercise": (
                {
                    "name": exercises[top_eid].name,
                    "sessions": year_data["sessions_by_exercise"][top_eid],
                }
                if top_eid and top_eid in exercises
                else None
            ),
            "busiest_month": {
                "name": date(year, busiest, 1).strftime("%B"),
                "volume": round(year_data["month_volume"][busiest], 1),
            },
            "months": [
                {
                    "month": date(year, m, 1).strftime("%b"),
                    "volume": round(year_data["month_volume"].get(m, 0.0), 1),
                }
                for m in range(1, today.month + 1)
            ],
            "biggest_pr": (
                {"name": pr_ex.name, "weight": bp["weight"], "reps": bp["reps"]}
                if bp and pr_ex
                else None
            ),
        }

    return {
        "stalls": stalls,
        "year": year_review,
        "nudges": nudges,
        "extras": extras,
        "trends": {
            "weekdays": weekday_distribution,
            "rep_ranges": [{"range": k, "sets": v} for k, v in rep_buckets.items()],
            "prs_by_month": prs_monthly,
            "top_lifts": {"names": top_names, "weeks": top_lift_weeks},
            "pacing": pacing,
            "relative": relative,
            "blocks": blocks,
            "times": times,
            "forecast": forecast,
            "load": load,
            "recovery": recovery,
            "detraining": detraining,
            "standards": standards,
        },
        "totals": {
            "workouts": len(workouts),
            "volume": round(total_volume, 1),
            "sets": total_sets,
            "prs": total_prs,
            "since": workouts[0].started_at if workouts else None,
        },
        "streak_weeks": streak,
        "calendar": calendar,
        "weeks": weeks,
        "muscle_trend": {
            group: [
                {
                    "week_start": (this_week - timedelta(weeks=i)).isoformat(),
                    "sets": weeks_map.get(this_week - timedelta(weeks=i), 0),
                }
                for i in range(MUSCLE_TREND_WEEKS - 1, -1, -1)
            ]
            for group, weeks_map in muscle_weeks.items()
        },
        "muscle_groups": sorted(
            ({"group": g, "sets": n} for g, n in split.items() if n > 0),
            key=lambda x: -x["sets"],
        ),
        "split_days": SPLIT_DAYS,
    }
