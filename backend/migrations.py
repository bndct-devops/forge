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
