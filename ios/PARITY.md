# Native app ↔ PWA parity ledger

Target: **full PWA parity** (user decision, 2026-07-27). The PWA is the design
reference — screens are ported, not reinterpreted. Status: ✅ done · 🟡 partial ·
❌ missing · — not applicable natively.

| PWA page / feature | Status | Notes |
|---|---|---|
| **WorkoutHomePage** | 🟡 | title/hero/templates/programs ✅ · Log-weight row ❌ · Plans ❌ · template create/reorder/menu ❌ |
| **ActiveWorkoutPage** | 🟡 | table, prev column, ghosts, hints, trophy, types, RPE, rest bar, LA timer ✅ · plate calculator ✅ (per-side diagram, warm-up ramp, bar/plate config synced) · exercise reorder ✅ (move up/down) · per-exercise rest editing ✅ (tap the rest chip) · superset toggle with next ✅ (rest deferred to pair end) · set swipe-delete (menu instead) 🟡 · two-stage superset picker ❌ · swap exercise ✅ (keeps sets, refreshes ghosts) · add-warm-up-sets shortcut ✅ · exercise note editing in menu ✅ · chart/peek of recent sessions from menu ❌ |
| — draft persistence | ✅ | draft snapshots to disk (debounced) and restores on launch; cleared on finish/discard |
| **Program preview/detail** | 🟡 | cycle click-through + start ✅ · program editing (TMs, lifts, scheme) ❌ |
| **ExercisesPage** | 🟡 | grouped searchable list ✅ · create custom exercise ❌ · variant grouping under parents ❌ |
| **ExerciseDetailPage** | ✅ | muscle map, variation chips (+family toggle), pinned note, record tiles incl. best-set-volume, 1RM/weight/volume chart with 3M/1Y/ALL, training %, history ✅ · avg-RPE overlay on 1RM chart ❌ (needs dual axis) · custom-exercise edit/delete ❌ |
| **HistoryPage** | ✅ | list + calendar views, load-more |
| **WorkoutDetailPage** | 🟡 | view, rename, delete ✅ · set editing ❌ |
| **StatsPage** | 🟡 | Overview (streak+goal, nudges, stalls, tiles, highlights, calendar heatmap, year review) ✅ · Trends core (weekly volume, training days, rep ranges, PRs/month, muscle split w/ per-group trend, push/pull) ✅ · deep trends ✅ (block-vs-last, form&fatigue, top lifts, TM headroom, cycles, cycle report, velocity, relative, standards, trajectory, recovery, detraining, pacing, time-of-day) · RPE overlay on weekly volume ❌ |
| **RecordsPage** | ✅ | searchable records page pushed from Stats overview |
| **MeasurePage** | ✅ | kinds list, trend tiles, logged-vs-trend chart, add/delete entries (reached from Stats overview) · Home log-weight shortcut row ❌ |
| **RoutineEditorPage** | ❌ | template create/edit |
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
