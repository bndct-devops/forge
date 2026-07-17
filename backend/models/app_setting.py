from sqlalchemy import String, Text
from sqlalchemy.orm import Mapped, mapped_column

from backend.core.database import Base


class AppSetting(Base):
    """Server-wide key/value settings (admin-controlled), e.g. nightly backups."""

    __tablename__ = "app_settings"

    key: Mapped[str] = mapped_column(String(64), primary_key=True)
    value: Mapped[str] = mapped_column(Text)
