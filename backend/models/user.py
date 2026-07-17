from datetime import datetime

from sqlalchemy import Boolean, DateTime, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from backend.core.clock import utcnow
from backend.core.database import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    username: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    hashed_password: Mapped[str] = mapped_column(String(128))
    is_admin: Mapped[bool] = mapped_column(Boolean, default=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    unit: Mapped[str] = mapped_column(String(4), default="kg")  # kg | lb
    default_rest_seconds: Mapped[int] = mapped_column(Integer, default=120)
    weekly_goal: Mapped[int] = mapped_column(Integer, default=3)
    # Insight toggles — on by default, individually switchable
    gap_nudges: Mapped[bool] = mapped_column(Boolean, default=True)
    deload_hints: Mapped[bool] = mapped_column(Boolean, default=True)
    # JSON blob for the plate calculator: {"bar": kg, "plates": [...]}; NULL =
    # plates-only math on the tracked weight (bar 0, standard plates)
    plate_config: Mapped[str | None] = mapped_column(Text, nullable=True)
    # SSO: 'local' accounts keep password login as break-glass even when
    # linked; 'oidc' accounts were provisioned by the IdP
    auth_source: Mapped[str] = mapped_column(String(8), default="local")
    # Outbound webhook fired when a workout is finished (optional)
    webhook_url: Mapped[str | None] = mapped_column(String(512), nullable=True)
    webhook_secret: Mapped[str | None] = mapped_column(String(128), nullable=True)
    oidc_sub: Mapped[str | None] = mapped_column(String(255), nullable=True, index=True)
    oidc_issuer: Mapped[str | None] = mapped_column(String(255), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=utcnow
    )

    @property
    def oidc_linked(self) -> bool:
        return self.oidc_sub is not None
