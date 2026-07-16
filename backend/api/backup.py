"""Consistent SQLite backup download — the whole instance in one file."""
import os
import sqlite3
import tempfile

from fastapi import APIRouter, Depends
from fastapi.responses import FileResponse
from starlette.background import BackgroundTask

from backend.core.clock import utcnow
from backend.core.config import DATA_DIR
from backend.core.security import get_current_admin
from backend.models import User

router = APIRouter(prefix="/backup", tags=["backup"])


@router.get("")
def download_backup(admin: User = Depends(get_current_admin)):
    """Stream a consistent snapshot of the database (safe under WAL — uses
    SQLite's online backup API, not a raw file copy)."""
    source = sqlite3.connect(str(DATA_DIR / "forge.db"))
    fd, path = tempfile.mkstemp(suffix=".db")
    os.close(fd)
    try:
        destination = sqlite3.connect(path)
        with destination:
            source.backup(destination)
        destination.close()
    finally:
        source.close()
    stamp = utcnow().strftime("%Y-%m-%d-%H%M")
    return FileResponse(
        path,
        filename=f"forge-backup-{stamp}.db",
        media_type="application/octet-stream",
        background=BackgroundTask(os.remove, path),
    )
