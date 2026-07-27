# Native app ↔ PWA parity ledger

Target: **full PWA parity** (user decision, 2026-07-27). The PWA is the design
reference — screens are ported, not reinterpreted. Status: ✅ done · 🟡 partial ·
❌ missing · — not applicable natively.

| PWA page / feature | Status | Notes |
|---|---|---|
| **WorkoutHomePage** | 🟡 | title/hero/templates/programs ✅ · Log-weight row ❌ · Plans ❌ · template create/reorder/menu ❌ |
| **ActiveWorkoutPage** | 🟡 | table, prev column, ghosts, hints, trophy, types, RPE, rest bar, LA timer ✅ · plate calculator ❌ · exercise reorder ❌ · per-exercise rest editing ❌ · set swipe-delete (menu instead) 🟡 · superset creation ❌ |
| — draft persistence | ❌ | in-memory only; app kill mid-workout loses unsynced sets |
| **Program preview/detail** | 🟡 | cycle click-through + start ✅ · program editing (TMs, lifts, scheme) ❌ |
| **ExercisesPage** | 🟡 | grouped searchable list ✅ · create custom exercise ❌ · variant grouping under parents ❌ |
| **ExerciseDetailPage** | ✅ | muscle map, variation chips (+family toggle), pinned note, record tiles incl. best-set-volume, 1RM/weight/volume chart with 3M/1Y/ALL, training %, history ✅ · avg-RPE overlay on 1RM chart ❌ (needs dual axis) · custom-exercise edit/delete ❌ |
| **HistoryPage** | ✅ | list + calendar views, load-more |
| **WorkoutDetailPage** | 🟡 | view, rename, delete ✅ · set editing ❌ |
| **StatsPage** | 🟡 | tiles + weekly volume + records ✅ · muscle split/map ❌ · trends ❌ · calendar heatmap ❌ · stalls/nudges ❌ · year view ❌ |
| **RecordsPage** | 🟡 | records list in Stats ✅ · dedicated searchable page ❌ |
| **MeasurePage** | ❌ | weight/body-fat/height logging + trends (the Home log-weight row feeds this) |
| **RoutineEditorPage** | ❌ | template create/edit |
| **SettingsPage** | 🟡 | unpair ✅ · units, insight toggles, tokens, backups, re-categorize ❌ |
| **LoginPage / SetupPage / OIDC** | — | native pairs via PAT instead |
| App icon | ❌ | placeholder grid icon |
| Haptics / set-flash feedback | ❌ | PWA has touch feedback + set flash |

## Suggested build order (adjust freely)

1. History tab (list + calendar) + WorkoutDetail — the biggest missing surface
2. ExerciseDetail parity: variations, muscle map, pinned note, charts
3. Stats parity: muscle split, trends, calendar
4. Draft persistence + app icon + haptics
5. Measure (weight logging) — also feeds Loom
6. Editors: routines, programs; Settings
