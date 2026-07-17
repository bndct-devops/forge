from datetime import datetime
from typing import List

from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from backend.core.clock import utcnow
from backend.core.database import Base


class Workout(Base):
    __tablename__ = "workouts"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    owner_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    name: Mapped[str] = mapped_column(String(128), default="Workout")
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    started_at: Mapped[datetime] = mapped_column(
        DateTime, default=utcnow, index=True
    )
    finished_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True, index=True)

    exercises: Mapped[List["WorkoutExercise"]] = relationship(
        cascade="all, delete-orphan", order_by="WorkoutExercise.position"
    )


class WorkoutExercise(Base):
    __tablename__ = "workout_exercises"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    workout_id: Mapped[int] = mapped_column(
        ForeignKey("workouts.id", ondelete="CASCADE"), index=True
    )
    exercise_id: Mapped[int] = mapped_column(
        ForeignKey("exercises.id", ondelete="CASCADE"), index=True
    )
    position: Mapped[int] = mapped_column(Integer, default=0)
    rest_seconds: Mapped[int | None] = mapped_column(Integer, nullable=True)
    # Chains this exercise with the following one into a superset
    superset_with_next: Mapped[bool] = mapped_column(Boolean, default=False)
    # Copied from the template at start; suggested_weight is the progression
    # suggestion computed against the previous session
    rep_min: Mapped[int | None] = mapped_column(Integer, nullable=True)
    rep_max: Mapped[int | None] = mapped_column(Integer, nullable=True)
    suggested_weight: Mapped[float | None] = mapped_column(Float, nullable=True)

    sets: Mapped[List["SetEntry"]] = relationship(
        cascade="all, delete-orphan", order_by="SetEntry.position"
    )


class SetEntry(Base):
    __tablename__ = "set_entries"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    workout_exercise_id: Mapped[int] = mapped_column(
        ForeignKey("workout_exercises.id", ondelete="CASCADE"), index=True
    )
    position: Mapped[int] = mapped_column(Integer, default=0)
    weight: Mapped[float | None] = mapped_column(Float, nullable=True)
    reps: Mapped[int | None] = mapped_column(Integer, nullable=True)
    is_completed: Mapped[bool] = mapped_column(Boolean, default=False)
    is_warmup: Mapped[bool] = mapped_column(Boolean, default=False)
    # 'drop' | 'failure' | NULL — markers only; both still count toward stats
    set_type: Mapped[str | None] = mapped_column(String(16), nullable=True)
    is_pr: Mapped[bool] = mapped_column(Boolean, default=False)
    rpe: Mapped[float | None] = mapped_column(Float, nullable=True)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
