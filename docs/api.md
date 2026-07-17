# Forge API

Everything the app does goes through the JSON API under `/api` — and you can
use it too. Interactive OpenAPI docs live at **`/api/docs`** on your
instance; this page is the practical quickstart.

## Authentication

Create a token in **Settings → API → Create API token**. Two scopes:

- **Full access** — everything your account can do
- **Read-only** — GETs only (workouts, stats, exports, metrics); safe for dashboards

Send it as a bearer header:

```bash
export FORGE=https://forge.example.com
export TOKEN=forge_pat_...

curl -H "Authorization: Bearer $TOKEN" $FORGE/api/workouts
```

Tokens are shown once at creation and can be revoked any time in Settings.

## Log a workout in one call

`POST /api/workouts/log` creates a complete, finished workout. Exercises
resolve by `exercise_id` or by `name` (names match the built-in library
including `(Barbell)`-style suffixes; unknown names create a custom
exercise). PRs are recomputed chronologically, so backdating works.

```bash
curl -X POST $FORGE/api/workouts/log \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{
    "name": "Push Day",
    "started_at": "2026-07-17T17:30:00Z",
    "duration_seconds": 3600,
    "exercises": [
      {
        "name": "Bench Press",
        "sets": [
          {"weight": 60, "reps": 10, "is_warmup": true},
          {"weight": 80, "reps": 8},
          {"weight": 80, "reps": 7, "set_type": "failure", "rpe": 9}
        ]
      },
      {"name": "Lateral Raise", "sets": [{"weight": 10, "reps": 12}]}
    ]
  }'
```

Set fields: `weight` (your unit; omit or 0 for bodyweight), `reps`,
`is_warmup`, `set_type` (`"drop"` / `"failure"`), `rpe` (1–10).

## Edit or delete workouts

- `GET /api/workouts` — list (paginated: `limit`, `offset`, or `month=YYYY-MM`)
- `GET /api/workouts/{id}` — full detail with sets
- `PUT /api/workouts/{id}` — full replace, same payload shape as `/log`
- `PATCH /api/workouts/{id}` — rename / notes / start time only
- `DELETE /api/workouts/{id}`

## Exercises

- `GET /api/exercises` — library incl. your custom ones (`is_custom`)
- `POST /api/exercises` — create (`name`, `muscle_group`, `equipment`, `grip`)
- `PATCH /api/exercises/{id}` — edit a custom exercise
- `DELETE /api/exercises/{id}` — custom only; refuses with 409 while logged
  workouts reference it
- `GET /api/exercises/{id}/stats` — history, PRs, estimated 1RM trend

## Stats & export

- `GET /api/stats` — streak, calendar, weekly volume, muscle split/trends
- `GET /api/stats/records` — all-time bests per exercise
- `GET /api/export/json` — **everything** (workouts, sets, exercises,
  routines, measurements) as one structured JSON document
- `GET /api/export/strong` — Strong-compatible CSV

## Prometheus metrics

`GET /api/metrics` emits text exposition (lifetime workout/set/volume/PR
counters, streak, current-week gauges, last-workout timestamp). Scrape with
a read-only token:

```yaml
scrape_configs:
  - job_name: forge
    metrics_path: /api/metrics
    scheme: https
    authorization:
      credentials: forge_pat_...
    static_configs:
      - targets: ["forge.example.com"]
```

## Webhooks

Set a URL (and optional signing secret) in **Settings → API**. When a
workout is finished — in the app or via `/log` — Forge POSTs:

```json
{
  "event": "workout.finished",
  "source": "app",
  "workout": {
    "id": 123,
    "name": "Push Day",
    "started_at": "2026-07-17T17:30:00Z",
    "finished_at": "2026-07-17T18:35:00Z",
    "duration_seconds": 3900,
    "total_volume": 5480.0,
    "total_sets": 18,
    "pr_count": 1
  }
}
```

With a secret set, the request carries
`X-Forge-Signature: sha256=<HMAC-SHA256 of the raw body>` for verification.
