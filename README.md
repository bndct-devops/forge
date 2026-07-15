# Forge

Self-hosted workout tracking for weight training. A privacy-first alternative to
Strong: templates, set/rep/weight logging with previous-workout ghosts, rest
timers between sets, personal records, and progress charts — running entirely on
your own server. No cardio, by design.

Sibling app to [Tome](../tome): same design language (warm paper / charcoal
surfaces, OKLCH tokens, Onest + Bricolage Grotesque), its own ember accent.

## Features

- **Workout logging** — start empty or from a template; per-set weight × reps
  with the previous workout's numbers as tap-to-accept ghosts; swipe a set to
  delete it
- **Rest timer** — starts automatically when you check off a set, per-exercise
  override or account default, ±15s / skip, sound + vibration + notification
  when time's up; survives reloads
- **Templates (routines)** — exercises with target set counts and rest times
- **History** — every finished workout with duration, volume, and PRs
- **Records & progress** — per-exercise best weight, estimated 1RM (Epley),
  best set volume, and charts of 1RM / weight / volume over time
- **Exercise library** — ~90 seeded weight exercises + custom ones per user
- **Multi-user** — first-run setup creates the admin; admins manage users in
  Settings; JWT auth
- **PWA** — installable on the phone home screen, standalone display, dark
  (default), light, and true-black OLED themes

## Self-hosting

```bash
docker compose up -d --build
```

Then open http://localhost:8081 — the first visit walks you through creating
the admin account.

Environment variables:

| Variable | Default | Purpose |
|---|---|---|
| `FORGE_SECRET_KEY` | auto-generated, persisted in `/data/secret_key` | JWT signing secret |
| `FORGE_DATA_DIR` | `/data` | SQLite database + secret key |
| `FORGE_PORT` | `8081` | HTTP port (dev convenience; the container binds 8081) |

Single volume: `/data` (SQLite in WAL mode). Back it up, and you have everything.

## Development

```bash
./dev.sh   # backend :8081 (uvicorn --reload) + frontend :5174 (vite HMR)
```

Backend: Python 3.12, FastAPI, SQLAlchemy 2.0, SQLite. Frontend: React 19,
Vite, TypeScript strict, Tailwind CSS 4, Lucide icons, Recharts.

```
forge/
├── backend/
│   ├── api/          # auth, users, exercises, routines, workouts (+ sets)
│   ├── core/         # config, database, security, clock
│   ├── models/       # user, exercise, routine, workout
│   ├── schemas.py    # pydantic request/response models
│   ├── serializers.py# shared workout serialization + PR/1RM helpers
│   └── seed.py       # seeded exercise catalogue (weights only)
└── frontend/src/
    ├── components/   # AppShell, SetRow, RestTimerBar, ExercisePicker, Sheet, Segmented
    ├── pages/        # WorkoutHome, ActiveWorkout, RoutineEditor, History, WorkoutDetail, Exercises, ExerciseDetail, Settings, Login, Setup
    ├── contexts/     # AuthContext, WorkoutContext
    └── lib/          # api, timer (rest timer engine), theme, format, types
```
