"""Tiny additive migrations for SQLite — create_all() only creates new tables,
so columns added to existing models are patched in here on startup."""
from sqlalchemy import text

from backend.core.database import engine


def _ensure_column(table: str, column: str, ddl: str) -> None:
    with engine.connect() as conn:
        cols = [row[1] for row in conn.execute(text(f"PRAGMA table_info({table})"))]
        if column not in cols:
            conn.execute(text(f"ALTER TABLE {table} ADD COLUMN {ddl}"))
            conn.commit()


def run_migrations() -> None:
    _ensure_column("workouts", "program_id", "program_id INTEGER REFERENCES programs(id)")
    _ensure_column("workouts", "program_lift_id", "program_lift_id INTEGER REFERENCES program_lifts(id)")
    _ensure_column("set_entries", "is_warmup", "is_warmup BOOLEAN NOT NULL DEFAULT 0")
    _ensure_column("exercises", "grip", "grip VARCHAR(24)")
    _ensure_column(
        "exercises", "variant_of_id", "variant_of_id INTEGER REFERENCES exercises(id)"
    )
    _ensure_column(
        "workout_exercises",
        "superset_with_next",
        "superset_with_next BOOLEAN NOT NULL DEFAULT 0",
    )
    _ensure_column(
        "routine_exercises",
        "superset_with_next",
        "superset_with_next BOOLEAN NOT NULL DEFAULT 0",
    )
    _ensure_column("set_entries", "rpe", "rpe FLOAT")
    _ensure_column("users", "weekly_goal", "weekly_goal INTEGER NOT NULL DEFAULT 3")
    _ensure_column("routine_exercises", "rep_min", "rep_min INTEGER")
    _ensure_column("routine_exercises", "rep_max", "rep_max INTEGER")
    _ensure_column("routine_exercises", "increment", "increment FLOAT")
    _ensure_column("workout_exercises", "rep_min", "rep_min INTEGER")
    _ensure_column("workout_exercises", "rep_max", "rep_max INTEGER")
    _ensure_column("workout_exercises", "suggested_weight", "suggested_weight FLOAT")
    # 'drop' | 'failure' | NULL (normal working set)
    _ensure_column("set_entries", "set_type", "set_type VARCHAR(16)")
    _ensure_column("users", "gap_nudges", "gap_nudges BOOLEAN NOT NULL DEFAULT 1")
    _ensure_column("users", "deload_hints", "deload_hints BOOLEAN NOT NULL DEFAULT 1")
    _ensure_column("users", "plate_config", "plate_config TEXT")
    _ensure_column(
        "workout_exercises", "suggestion_kind", "suggestion_kind VARCHAR(12)"
    )
    _ensure_column(
        "users", "auth_source", "auth_source VARCHAR(8) NOT NULL DEFAULT 'local'"
    )
    _ensure_column("users", "oidc_sub", "oidc_sub VARCHAR(255)")
    _ensure_column("users", "oidc_issuer", "oidc_issuer VARCHAR(255)")
    _ensure_column("users", "webhook_url", "webhook_url VARCHAR(512)")
    _ensure_column("users", "webhook_secret", "webhook_secret VARCHAR(128)")
    _ensure_column("exercises", "grip_width", "grip_width VARCHAR(16)")
    _ensure_column("exercises", "attachment", "attachment VARCHAR(24)")
