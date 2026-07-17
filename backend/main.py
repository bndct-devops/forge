from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse

from backend.core.database import Base, SessionLocal, engine
from backend.api import (
    auth,
    oidc,
    backup,
    updates,
    exercises,
    import_export,
    measurements,
    plans,
    push,
    routines,
    stats,
    users,
    workouts,
)
from backend.migrations import run_migrations
from backend.seed import seed_exercises

import os

from starlette.middleware.sessions import SessionMiddleware

from backend.core.config import SECRET_KEY

_dev = bool(os.environ.get("FORGE_DEV"))
app = FastAPI(
    title="Forge",
    docs_url="/api/docs" if _dev else None,
    openapi_url="/api/openapi.json" if _dev else None,
)


# Transient cookie for the OIDC handshake state/PKCE only — app auth stays
# a bearer JWT
app.add_middleware(
    SessionMiddleware, secret_key=SECRET_KEY, max_age=600, same_site="lax"
)


@app.on_event("startup")
def startup():
    Base.metadata.create_all(engine)
    run_migrations()
    db = SessionLocal()
    try:
        seed_exercises(db)
    finally:
        db.close()
    backup.start_backup_scheduler()


@app.get("/api/health")
def health():
    return {"status": "ok", "version": os.environ.get("FORGE_VERSION", "dev")}


app.include_router(auth.router, prefix="/api")
app.include_router(oidc.router, prefix="/api")
app.include_router(users.router, prefix="/api")
app.include_router(exercises.router, prefix="/api")
app.include_router(routines.router, prefix="/api")
app.include_router(workouts.router, prefix="/api")
app.include_router(workouts.sets_router, prefix="/api")
app.include_router(import_export.router, prefix="/api")
app.include_router(stats.router, prefix="/api")
app.include_router(plans.router, prefix="/api")
app.include_router(push.router, prefix="/api")
app.include_router(measurements.router, prefix="/api")
app.include_router(backup.router, prefix="/api")
app.include_router(updates.router, prefix="/api")

# Serve the built frontend (production / Docker). In dev, Vite serves it instead.
_dist = Path(__file__).resolve().parent.parent / "frontend" / "dist"
if _dist.exists():

    @app.get("/{path:path}")
    def spa(path: str):
        # Unmatched API paths are 404s, never the app shell
        if path.startswith("api/") or path == "api":
            raise HTTPException(status_code=404, detail="Not found")
        file = _dist / path
        if path and file.is_file():
            # Hash-named assets are immutable; everything else must revalidate,
            # or iOS heuristically caches a stale index.html across deploys
            if path.startswith("assets/"):
                return FileResponse(
                    file, headers={"Cache-Control": "public, max-age=31536000, immutable"}
                )
            return FileResponse(file, headers={"Cache-Control": "no-cache"})
        return FileResponse(_dist / "index.html", headers={"Cache-Control": "no-cache"})
