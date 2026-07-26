/** Client-side mirror of the program engine, for offline sessions.
 *
 *  The server is the source of truth (backend/program_schemes.py and
 *  advance_program); these helpers reproduce just enough of it to start a
 *  prescribed session and keep the cached program card truthful while the
 *  finish waits in the sync queue. Scheme tables come from the cached
 *  /programs/schemes response, never hardcoded.
 */
import { getCached, setCached } from './dataCache'
import { localExercise, newClientId, relabelSupersets, utcStamp } from './localWorkout'
import type { Exercise, Routine, Workout } from './types'

export interface ProgramSet {
  pct: number
  weight: number
  reps: number
  amrap: boolean
}

export interface CachedProgram {
  id: number
  name: string
  scheme: string
  rounding: number
  current_week: number
  cycle_length: number
  cycle_number: number
  lift_pointer: number
  lifts: {
    id?: number
    exercise_id: number
    name: string
    training_max: number
    increment: number
    routine_id: number | null
    routine_name?: string | null
  }[]
  next: {
    lift_id?: number
    exercise_id?: number
    exercise_name: string
    week: number
    sets: ProgramSet[]
    routine_name?: string | null
  } | null
}

export interface SchemeWeeks {
  weeks: { pct: number; reps: number; amrap: boolean }[][]
}

/** Python's round() rounds half to even — mirror it so offline prescriptions
 *  match the server's to the gram. */
function roundHalfEven(x: number): number {
  const floor = Math.floor(x)
  return x - floor === 0.5 ? (floor % 2 === 0 ? floor : floor + 1) : Math.round(x)
}

function roundToStep(weight: number, step: number): number {
  if (step <= 0) return Math.round(weight * 10) / 10
  return Math.round(roundHalfEven(weight / step) * step * 100) / 100
}

export function prescription(
  scheme: SchemeWeeks,
  week: number,
  trainingMax: number,
  step: number,
): ProgramSet[] {
  const plan = scheme.weeks[(week - 1) % scheme.weeks.length]
  return plan.map(({ pct, reps, amrap }) => ({
    pct,
    weight: Math.max(step, roundToStep(trainingMax * pct, step)),
    reps,
    amrap,
  }))
}

/** The session the program would start right now, built entirely from cached
 *  data. Throws a user-facing Error when a required cache is missing. */
export function buildLocalProgramWorkout(programId: number): Workout {
  const program = getCached<CachedProgram[]>('programs')?.find((p) => p.id === programId)
  const schemes = getCached<Record<string, SchemeWeeks>>('programSchemes')
  const scheme = schemes?.[program?.scheme ?? '']
  if (!program || !scheme || program.lifts.length === 0) {
    throw new Error('This program is not available offline')
  }
  const lift = program.lifts[program.lift_pointer % program.lifts.length]
  const sets = prescription(scheme, program.current_week, lift.training_max, program.rounding)
  const catalog = getCached<Exercise[]>('exercises') ?? []
  const ref = catalog.find((e) => e.id === lift.exercise_id)

  let temp = -1
  const workout: Workout = {
    id: temp--,
    name: `${program.name} — ${lift.name} (W${program.current_week})`,
    notes: null,
    started_at: utcStamp(),
    finished_at: null,
    client_id: newClientId(),
    program_id: program.id,
    program_lift_id: lift.id ?? null,
    exercises: [],
  }
  const mainSetIds = sets.map(() => temp--)
  const main = localExercise(
    temp--,
    mainSetIds,
    {
      exercise_id: lift.exercise_id,
      name: ref?.name ?? lift.name,
      muscle_group: ref?.muscle_group ?? '',
      equipment: ref?.equipment ?? '',
    },
    { position: 0 },
  )
  // Prescribed sets arrive prefilled, exactly like the server start
  main.sets = main.sets.map((s, i) => ({ ...s, weight: sets[i].weight, reps: sets[i].reps }))
  workout.exercises = [main]

  const routine = lift.routine_id
    ? getCached<Routine[]>('routines')?.find((r) => r.id === lift.routine_id)
    : undefined
  if (routine) {
    workout.exercises.push(
      ...routine.exercises
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
              position: 1 + i,
              restSeconds: re.rest_seconds,
              supersetWithNext: re.superset_with_next,
              repMin: re.rep_min,
              repMax: re.rep_max,
            },
          )
        }),
    )
    workout.exercises = relabelSupersets(workout.exercises)
  }
  return workout
}

export interface LocalPreviewSession {
  offset: number
  week: number
  cycle_number: number
  exercise_id: number
  exercise_name: string
  training_max: number
  sets: ProgramSet[]
  routine_name: string | null
  accessories: { name: string; set_count: number; rep_min: number | null; rep_max: number | null }[]
}

/** Offline fallback for GET /programs/{id}/preview — the same simulated walk
 *  over cached state. Returns null when the caches can't support it. */
export function localProgramPreview(
  programId: number,
  count: number,
): LocalPreviewSession[] | null {
  const program = getCached<CachedProgram[]>('programs')?.find((p) => p.id === programId)
  const scheme = getCached<Record<string, SchemeWeeks>>('programSchemes')?.[program?.scheme ?? '']
  if (!program || !scheme || program.lifts.length === 0) return null
  const routines = getCached<Routine[]>('routines') ?? []

  let { lift_pointer, current_week, cycle_number } = program
  const tms = new Map(program.lifts.map((l, i) => [l.id ?? -i, l.training_max]))
  const sessions: LocalPreviewSession[] = []
  for (let offset = 0; offset < count; offset++) {
    const idx = lift_pointer % program.lifts.length
    const lift = program.lifts[idx]
    const key = lift.id ?? -idx
    const routine = lift.routine_id ? routines.find((r) => r.id === lift.routine_id) : undefined
    sessions.push({
      offset,
      week: current_week,
      cycle_number,
      exercise_id: lift.exercise_id,
      exercise_name: lift.name,
      training_max: tms.get(key) ?? lift.training_max,
      sets: prescription(scheme, current_week, tms.get(key) ?? lift.training_max, program.rounding),
      routine_name: routine?.name ?? lift.routine_name ?? null,
      accessories: (routine?.exercises ?? []).map((re) => ({
        name: re.name,
        set_count: re.set_count,
        rep_min: re.rep_min,
        rep_max: re.rep_max,
      })),
    })
    lift_pointer += 1
    if (lift_pointer >= program.lifts.length) {
      lift_pointer = 0
      current_week += 1
      if (current_week > program.cycle_length) {
        current_week = 1
        cycle_number += 1
        program.lifts.forEach((l, i) => {
          const k = l.id ?? -i
          tms.set(k, Math.round(((tms.get(k) ?? l.training_max) + l.increment) * 100) / 100)
        })
      }
    }
  }
  return sessions
}

/** Mirror of the server's advance_program, applied to one cached program:
 *  pointer → week → cycle with TM bumps, plus a rebuilt `next` so the card
 *  stays truthful offline. The next real fetch overwrites all of it. */
export function advanceCachedProgram(programId: number): void {
  const programs = getCached<CachedProgram[]>('programs')
  const schemes = getCached<Record<string, SchemeWeeks>>('programSchemes')
  if (!programs) return
  const updated = programs.map((p) => {
    if (p.id !== programId || p.lifts.length === 0) return p
    const scheme = schemes?.[p.scheme]
    let { lift_pointer, current_week, cycle_number } = p
    let lifts = p.lifts
    lift_pointer += 1
    if (lift_pointer >= lifts.length) {
      lift_pointer = 0
      current_week += 1
      if (current_week > p.cycle_length) {
        current_week = 1
        cycle_number += 1
        lifts = lifts.map((l) => ({
          ...l,
          training_max: Math.round((l.training_max + l.increment) * 100) / 100,
        }))
      }
    }
    const lift = lifts[lift_pointer % lifts.length]
    return {
      ...p,
      lift_pointer,
      current_week,
      cycle_number,
      lifts,
      next: scheme
        ? {
            lift_id: lift.id,
            exercise_id: lift.exercise_id,
            exercise_name: lift.name,
            week: current_week,
            sets: prescription(scheme, current_week, lift.training_max, p.rounding),
            routine_name: lift.routine_name ?? null,
          }
        : p.next,
    }
  })
  setCached('programs', updated)
}
