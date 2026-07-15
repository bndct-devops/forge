from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from backend.core.database import Base, SessionLocal, engine
from backend.api import auth, exercises, import_export, routines, users, workouts
from backend.migrations import run_migrations
from backend.seed import seed_exercises

app = FastAPI(title="Forge", docs_url="/api/docs", openapi_url="/api/openapi.json")


@app.on_event("startup")
def startup():
    Base.metadata.create_all(engine)
    run_migrations()
    db = SessionLocal()
    try:
        seed_exercises(db)
    finally:
        db.close()


@app.get("/api/health")
def health():
    return {"status": "ok"}


app.include_router(auth.router, prefix="/api")
app.include_router(users.router, prefix="/api")
app.include_router(exercises.router, prefix="/api")
app.include_router(routines.router, prefix="/api")
app.include_router(workouts.router, prefix="/api")
app.include_router(workouts.sets_router, prefix="/api")
app.include_router(import_export.router, prefix="/api")

# Serve the built frontend (production / Docker). In dev, Vite serves it instead.
_dist = Path(__file__).resolve().parent.parent / "frontend" / "dist"
if _dist.exists():
    app.mount("/assets", StaticFiles(directory=_dist / "assets"), name="assets")

    @app.get("/{path:path}")
    def spa(path: str):
        file = _dist / path
        if path and file.is_file():
            return FileResponse(file)
        return FileResponse(_dist / "index.html")
