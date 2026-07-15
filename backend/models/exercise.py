from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from backend.core.clock import utcnow
from backend.core.database import Base


class Exercise(Base):
    __tablename__ = "exercises"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(128), index=True)
    muscle_group: Mapped[str] = mapped_column(String(32), index=True)
    equipment: Mapped[str] = mapped_column(String(32), default="Other")
    # Overhand / Underhand / Neutral / Mixed / Wide / Close — NULL = standard
    grip: Mapped[str | None] = mapped_column(String(24), nullable=True)
    # Groups grip/style variations under a base exercise (NULL = base itself)
    variant_of_id: Mapped[int | None] = mapped_column(
        ForeignKey("exercises.id"), nullable=True
    )
    # NULL owner = global seed exercise, visible to everyone
    owner_id: Mapped[int | None] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=True, index=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=utcnow
    )
