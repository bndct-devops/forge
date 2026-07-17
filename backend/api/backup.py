"""Consistent SQLite backups — on-demand download plus an optional nightly
snapshot to DATA_DIR/backups (admin setting, off by default)."""
import logging
import os
import sqlite3
import tempfile
import threading
import time

from fastapi import APIRouter, Depends
from fastapi.responses import FileResponse
from pydantic import BaseModel
from sqlalchemy.orm import Session
from starlette.background import BackgroundTask

from backend.core.clock import utcnow
from backend.core.config import DATA_DIR
from backend.core.database import SessionLocal, get_db
from backend.core.security import get_current_admin
from backend.models import AppSetting, User

router = APIRouter(prefix="/backup", tags=["backup"])
log = logging.getLogger("forge.backup")

BACKUP_DIR = DATA_DIR / "backups"
NIGHTLY_KEY = "nightly_backups"
KEEP = 14
# Earliest UTC hour for the nightly snapshot; the hourly tick after this
# takes it (also covers instances that were asleep/restarted at 03:00)
NIGHTLY_AFTER_HOUR = 3


def _snapshot(destination_path: str) -> None:
    """SQLite online-backup — consistent under WAL, unlike a raw file copy."""
    source = sqlite3.connect(str(DATA_DIR / "forge.db"))
    try:
        destination = sqlite3.connect(destination_path)
        with destination:
            source.backup(destination)
        destination.close()
    finally:
        source.close()


def _nightly_enabled(db: Session) -> bool:
    setting = db.get(AppSetting, NIGHTLY_KEY)
    return setting is not None and setting.value == "1"


def _run_nightly_if_due() -> None:
    with SessionLocal() as db:
        if not _nightly_enabled(db):
            return
    now = utcnow()
    if now.hour < NIGHTLY_AFTER_HOUR:
        return
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    today = now.strftime("%Y-%m-%d")
    existing = sorted(BACKUP_DIR.glob("forge-*.db"))
    if any(f.name.startswith(f"forge-{today}") for f in existing):
        return
    target = BACKUP_DIR / f"forge-{today}.db"
    _snapshot(str(target) + ".tmp")
    os.replace(str(target) + ".tmp", target)
    log.info("nightly backup written: %s", target.name)
    for stale in sorted(BACKUP_DIR.glob("forge-*.db"))[:-KEEP]:
        stale.unlink(missing_ok=True)


def start_backup_scheduler() -> None:
    def loop() -> None:
        while True:
            try:
                _run_nightly_if_due()
            except Exception:
                log.exception("nightly backup failed")
            time.sleep(3600)

    threading.Thread(target=loop, name="forge-backup", daemon=True).start()


@router.get("")
def download_backup(admin: User = Depends(get_current_admin)):
    """Stream a consistent snapshot of the database."""
    fd, path = tempfile.mkstemp(suffix=".db")
    os.close(fd)
    _snapshot(path)
    stamp = utcnow().strftime("%Y-%m-%d-%H%M")
    return FileResponse(
        path,
        filename=f"forge-backup-{stamp}.db",
        media_type="application/octet-stream",
        background=BackgroundTask(os.remove, path),
    )


class BackupSettings(BaseModel):
    nightly_enabled: bool


@router.get("/settings")
def backup_settings(
    admin: User = Depends(get_current_admin), db: Session = Depends(get_db)
):
    backups = sorted(BACKUP_DIR.glob("forge-*.db")) if BACKUP_DIR.exists() else []
    return {
        "nightly_enabled": _nightly_enabled(db),
        "keep": KEEP,
        "count": len(backups),
        "latest": backups[-1].name if backups else None,
    }


@router.put("/settings")
def update_backup_settings(
    body: BackupSettings,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    setting = db.get(AppSetting, NIGHTLY_KEY)
    if setting is None:
        setting = AppSetting(key=NIGHTLY_KEY, value="0")
        db.add(setting)
    setting.value = "1" if body.nightly_enabled else "0"
    db.commit()
    return {"nightly_enabled": body.nightly_enabled, "keep": KEEP}
