# Native app ↔ PWA parity ledger

Target: **full PWA parity** (user decision, 2026-07-27). The PWA is the design
reference — screens are ported, not reinterpreted. Status: ✅ done · 🟡 partial ·
❌ missing · — not applicable natively.

| PWA page / feature | Status | Notes |
|---|---|---|
| **WorkoutHomePage** | 🟡 | title/hero/programs-first/templates ✅ · template create/edit/delete via menu ✅ · Log-weight quick row ✅ · Plans library ❌ (PWA) · template drag-reorder ❌ |
| **ActiveWorkoutPage** | 🟡 | table, prev column, ghosts, hints, trophy, types, RPE, rest bar, LA timer ✅ · plate calculator ✅ (per-side diagram, warm-up ramp, bar/plate config synced) · exercise reorder ✅ (move up/down) · per-exercise rest editing ✅ (tap the rest chip) · superset toggle with next ✅ (rest deferred to pair end) · set swipe-delete ✅ (left swipe, menu also works) · two-stage superset picker ❌ · swap exercise ✅ (keeps sets, refreshes ghosts) · add-warm-up-sets shortcut ✅ · exercise note editing in menu ✅ · recent-sessions peek from menu ✅ |
| Session notes | ✅ | free-text note on the active workout, lands on the workout (distinct from the pinned exercise note) |
| — draft persistence | ✅ | draft snapshots to disk (debounced) and restores on launch; cleared on finish/discard |
| **Program preview/detail** | 🟡 | cycle click-through + start ✅ · program editing ✅ (name, rounding, TMs, increments, accessory routine, add/remove lifts via pencil) · program creation ❌ (PWA) |
| **ExercisesPage** | 🟡 | grouped searchable list ✅ · create custom exercise ✅ (+ button, form sheet) · variant grouping under parents ✅ (count chip expands family) |
| **ExerciseDetailPage** | ✅ | muscle map, variation chips (+family toggle), pinned note, record tiles incl. best-set-volume, 1RM/weight/volume chart with 3M/1Y/ALL, training %, history ✅ · custom-exercise edit/delete ✅ (pencil on custom exercises) · avg-RPE overlay on 1RM chart ✅ (RPE mapped onto the metric scale, dashed) |
| **HistoryPage** | ✅ | list + calendar views, load-more |
| **WorkoutDetailPage** | ✅ | view, rename, delete, exercise links ✅ · Edit sets mode: inline weight/reps PATCH, warm-up toggle, delete set, add set, remove exercise ✅ |
| **StatsPage** | 🟡 | Overview (streak+goal, nudges, stalls, tiles, highlights, calendar heatmap, year review) ✅ · Trends core (weekly volume, training days, rep ranges, PRs/month, muscle split w/ per-group trend, push/pull) ✅ · deep trends ✅ (block-vs-last, form&fatigue, top lifts, TM headroom, cycles, cycle report, velocity, relative, standards, trajectory, recovery, detraining, pacing, time-of-day) · RPE overlay on weekly volume ✅ |
| **RecordsPage** | ✅ | searchable records page pushed from Stats overview |
| **MeasurePage** | ✅ | kinds list, trend tiles, logged-vs-trend chart, add/delete entries (Stats overview + Home log-weight row) |
| **RoutineEditorPage** | ✅ | name, sets stepper, rest, rep range, increment, superset toggle, move up/down, dirty guard |
| **SettingsPage** | ✅ | native scope: unit, default rest, weekly goal, insight toggles, weigh-in reminder, server info, unpair (token now in Keychain) · server admin (users/backups/tokens/OIDC/re-categorize) stays in the PWA by design |
| **LoginPage / SetupPage / OIDC** | — | native pairs via PAT instead |
| App icon | ✅ | PWA ember dumbbell via asset catalog |
| Haptics / set-flash feedback | ✅ | impact on set done, success on finish, set-flash ember pulse, press feedback on cards, sliding-pill segmented controls, animated set/exercise mutations, finish-screen pop |

## Suggested build order (adjust freely)

1. History tab (list + calendar) + WorkoutDetail — the biggest missing surface
2. ExerciseDetail parity: variations, muscle map, pinned note, charts
3. Stats parity: muscle split, trends, calendar
4. Draft persistence + app icon + haptics
5. Measure (weight logging) — also feeds Loom
6. Editors: routines, programs; Settings
