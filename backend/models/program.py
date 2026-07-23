from datetime import datetime
from typing import List

from sqlalchemy import DateTime, Float, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from backend.core.clock import utcnow
from backend.core.database import Base


class Program(Base):
    """A running periodization program: a scheme cycling over ordered lifts.

    State machine: `lift_pointer` indexes the next lift to train; finishing a
    program workout advances it. When the pointer wraps, `current_week`
    advances; when the week wraps past the scheme's cycle, `cycle_number`
    advances and every lift's training max increases by its increment.
    """

    __tablename__ = "programs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    owner_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    name: Mapped[str] = mapped_column(String(128))
    scheme: Mapped[str] = mapped_column(String(16))  # key into program_schemes.SCHEMES
    rounding: Mapped[float] = mapped_column(Float, default=2.5)  # plate step
    current_week: Mapped[int] = mapped_column(Integer, default=1)  # 1-based
    cycle_number: Mapped[int] = mapped_column(Integer, default=1)
    lift_pointer: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)

    lifts: Mapped[List["ProgramLift"]] = relationship(
        cascade="all, delete-orphan", order_by="ProgramLift.position"
    )


class ProgramLift(Base):
    __tablename__ = "program_lifts"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    program_id: Mapped[int] = mapped_column(
        ForeignKey("programs.id", ondelete="CASCADE"), index=True
    )
    exercise_id: Mapped[int] = mapped_column(ForeignKey("exercises.id", ondelete="CASCADE"))
    position: Mapped[int] = mapped_column(Integer, default=0)
    training_max: Mapped[float] = mapped_column(Float)
    # Added to the training max at the end of every full cycle
    increment: Mapped[float] = mapped_column(Float, default=2.5)
    # Optional accessory template: starting this lift's session appends the
    # routine's exercises after the prescribed main-lift sets
    routine_id: Mapped[int | None] = mapped_column(
        ForeignKey("routines.id", ondelete="SET NULL"), nullable=True
    )
