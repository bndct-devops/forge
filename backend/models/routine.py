from datetime import datetime
from typing import List

from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from backend.core.clock import utcnow
from backend.core.database import Base


class Routine(Base):
    __tablename__ = "routines"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    owner_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    name: Mapped[str] = mapped_column(String(128))
    position: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=utcnow
    )

    exercises: Mapped[List["RoutineExercise"]] = relationship(
        cascade="all, delete-orphan", order_by="RoutineExercise.position"
    )


class RoutineExercise(Base):
    __tablename__ = "routine_exercises"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    routine_id: Mapped[int] = mapped_column(
        ForeignKey("routines.id", ondelete="CASCADE"), index=True
    )
    exercise_id: Mapped[int] = mapped_column(ForeignKey("exercises.id", ondelete="CASCADE"))
    position: Mapped[int] = mapped_column(Integer, default=0)
    set_count: Mapped[int] = mapped_column(Integer, default=3)
    rest_seconds: Mapped[int | None] = mapped_column(Integer, nullable=True)
    superset_with_next: Mapped[bool] = mapped_column(Boolean, default=False)
    # Optional double-progression rule: hit rep_max on all working sets ->
    # next session suggests +increment
    rep_min: Mapped[int | None] = mapped_column(Integer, nullable=True)
    rep_max: Mapped[int | None] = mapped_column(Integer, nullable=True)
    increment: Mapped[float | None] = mapped_column(Float, nullable=True)
