/** Pure helpers for the offline active-workout document.
 *
 *  While the connection is down the workout lives entirely client-side:
 *  new entities get negative temp ids (server ids are positive), every
 *  mutation is applied by these functions, and the whole document syncs
 *  through PUT /workouts/sync keyed by a client-generated UUID. */
import { parseUTC } from './format'
import type { FinishResult, Routine, SetEntry, Workout, WorkoutExercise } from './types'

export interface SyncPayload {
  client_id: string
  id: number | null
  name: string
  notes: string | null
  started_at: string
  finished_at: string | null
  exercises: {
    exercise_id: number
    position: number
    rest_seconds: number | null
    superset_with_next: boolean
    rep_min: number | null
    rep_max: number | null
    sets: {
      position: number
      weight: number | null
      reps: number | null
      is_completed: boolean
      is_warmup: boolean
      set_type: 'drop' | 'failure' | null
      rpe: number | null
      completed_at: string | null
    }[]
  }[]
}

export interface ExerciseRef {
  exercise_id: number
  name: string
  muscle_group: string
  equipment: string
}

export function newClientId(): string {
  return typeof crypto.randomUUID === 'function'
    ? crypto.randomUUID()
    : `local-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`
}

/** Naive-UTC second-precision stamp — the format the backend serializes */
export function utcStamp(): string {
  return new Date().toISOString().slice(0, 19)
}

/** Temp ids are negative and unique across the whole document */
export function nextTempId(w: Workout | null): number {
  let min = 0
  if (w) {
    min = Math.min(min, w.id)
    for (const we of w.exercises) {
      min = Math.min(min, we.id)
      for (const s of we.sets) min = Math.min(min, s.id)
    }
  }
  return min - 1
}

export function blankSet(id: number, position: number): SetEntry {
  return {
    id,
    position,
    weight: null,
    reps: null,
    is_completed: false,
    is_warmup: false,
    set_type: null,
    is_pr: false,
    rpe: null,
    completed_at: null,
  }
}

/** Superset group labels from the with-next chain — mirrors the server's
 *  superset_labels so offline docs render identically. */
export function relabelSupersets(exercises: WorkoutExercise[]): WorkoutExercise[] {
  const ordered = [...exercises].sort((a, b) => a.position - b.position)
  const groups: WorkoutExercise[][] = []
  let current: WorkoutExercise[] = []
  for (const we of ordered) {
    current.push(we)
    if (!we.superset_with_next) {
      groups.push(current)
      current = []
    }
  }
  if (current.length) groups.push(current)

  const labels = new Map<number, string>()
  const last = new Map<number, boolean>()
  let letter = 0
  for (const group of groups) {
    if (group.length < 2) continue
    for (const member of group) {
      labels.set(member.id, String.fromCharCode(65 + (letter % 26)))
      last.set(member.id, member === group[group.length - 1])
    }
    letter++
  }
  return ordered.map((we) => ({
    ...we,
    superset: labels.get(we.id) ?? null,
    superset_last: last.get(we.id) ?? true,
  }))
}

export function localExercise(
  id: number,
  setIds: number[],
  ref: ExerciseRef,
  opts: {
    position: number
    restSeconds?: number | null
    supersetWithNext?: boolean
    repMin?: number | null
    repMax?: number | null
  },
): WorkoutExercise {
  return {
    id,
    exercise_id: ref.exercise_id,
    name: ref.name,
    muscle_group: ref.muscle_group,
    equipment: ref.equipment,
    note: '',
    position: opts.position,
    rest_seconds: opts.restSeconds ?? null,
    superset_with_next: opts.supersetWithNext ?? false,
    superset: null,
    superset_last: true,
    rep_min: opts.repMin ?? null,
    rep_max: opts.repMax ?? null,
    suggested_weight: null,
    suggestion_kind: null,
    sets: setIds.map((sid, i) => blankSet(sid, i)),
    previous_sets: [],
  }
}

/** Build a workout entirely client-side — empty or from a cached routine.
 *  No ghosts or progression suggestions offline; they need the server. */
export function buildLocalWorkout(opts: { name?: string; routine?: Routine }): Workout {
  let temp = -1
  const workout: Workout = {
    id: temp--,
    name: opts.routine?.name ?? opts.name ?? 'Workout',
    notes: null,
    started_at: utcStamp(),
    finished_at: null,
    client_id: newClientId(),
    exercises: [],
  }
  if (opts.routine) {
    workout.exercises = opts.routine.exercises
      .slice()
      .sort((a, b) => a.position - b.position)
      .map((re, i) => {
        const setIds = Array.from({ length: Math.max(re.set_count, 1) }, () => temp--)
        return localExercise(
          temp--,
          setIds,
          {
            exercise_id: re.exercise_id,
            name: re.name,
            muscle_group: re.muscle_group,
            equipment: re.equipment,
          },
          {
            position: i,
            restSeconds: re.rest_seconds,
            supersetWithNext: re.superset_with_next,
            repMin: re.rep_min,
            repMax: re.rep_max,
          },
        )
      })
    workout.exercises = relabelSupersets(workout.exercises)
  }
  return workout
}

export function syncPayload(w: Workout, finishedAt?: string): SyncPayload {
  return {
    client_id: w.client_id ?? newClientId(),
    id: w.id > 0 ? w.id : null,
    name: w.name,
    notes: w.notes,
    started_at: w.started_at,
    finished_at: finishedAt ?? w.finished_at ?? null,
    exercises: w.exercises.map((we) => ({
      exercise_id: we.exercise_id,
      position: we.position,
      rest_seconds: we.rest_seconds,
      superset_with_next: we.superset_with_next,
      rep_min: we.rep_min,
      rep_max: we.rep_max,
      sets: we.sets.map((s) => ({
        position: s.position,
        weight: s.weight,
        reps: s.reps,
        is_completed: s.is_completed,
        is_warmup: s.is_warmup,
        set_type: s.set_type ?? null,
        rpe: s.rpe ?? null,
        completed_at: s.completed_at ?? null,
      })),
    })),
  }
}

export function countCompletedSets(w: Workout): number {
  return w.exercises.reduce((n, we) => n + we.sets.filter((s) => s.is_completed).length, 0)
}

/** Summary for the finish screen when the server can't be reached — totals
 *  computed the same way as workout_totals; PRs arrive once synced. */
export function localFinishSummary(w: Workout, finishedAt: string): FinishResult {
  let volume = 0
  let sets = 0
  for (const we of w.exercises) {
    for (const s of we.sets) {
      if (s.is_completed && !s.is_warmup && s.reps != null) {
        volume += (s.weight ?? 0) * s.reps
        sets += 1
      }
    }
  }
  return {
    id: w.id,
    name: w.name,
    duration_seconds: Math.round(
      (parseUTC(finishedAt).getTime() - parseUTC(w.started_at).getTime()) / 1000,
    ),
    total_volume: Math.round(volume * 10) / 10,
    total_sets: sets,
    prs: [],
    workout_number: 0,
    week_workouts: 0,
    comparison: null,
    pending: true,
  }
}
