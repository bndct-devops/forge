import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react'
import { api } from '../lib/api'
import { isNetworkError, outbox } from '../lib/outbox'
import { toast } from '../lib/toast'
import type { FinishResult, SetEntry, Workout } from '../lib/types'

interface WorkoutContextValue {
  workout: Workout | null
  loading: boolean
  refresh: () => Promise<void>
  start: (from?: { routineId?: number; workoutId?: number; name?: string }) => Promise<Workout>
  rename: (name: string) => Promise<void>
  updateNotes: (notes: string) => Promise<void>
  addExercise: (exerciseId: number) => Promise<void>
  removeExercise: (weId: number) => Promise<void>
  setExerciseRest: (weId: number, restSeconds: number | null) => Promise<void>
  setSupersetLink: (weId: number, withNext: boolean) => Promise<void>
  reorderExercises: (weIds: number[]) => Promise<void>
  addSet: (weId: number) => Promise<void>
  updateSet: (
    setId: number,
    patch: Partial<Pick<SetEntry, 'weight' | 'reps' | 'is_completed' | 'is_warmup' | 'rpe'>>,
  ) => Promise<SetEntry>
  deleteSet: (weId: number, setId: number) => Promise<void>
  finish: () => Promise<FinishResult>
  discard: () => Promise<void>
}

const WorkoutContext = createContext<WorkoutContextValue | null>(null)

export function WorkoutProvider({ children }: { children: ReactNode }) {
  const [workout, setWorkout] = useState<Workout | null>(null)
  const [loading, setLoading] = useState(true)

  const refresh = useCallback(async () => {
    const active = await api<Workout | null>('/workouts/active')
    setWorkout(active)
  }, [])

  useEffect(() => {
    refresh()
      .catch(() => {})
      .finally(() => setLoading(false))
  }, [refresh])

  // Coming back to a suspended PWA: resync the active workout
  useEffect(() => {
    const onVisible = () => {
      if (!document.hidden) refresh().catch(() => {})
    }
    document.addEventListener('visibilitychange', onVisible)
    return () => document.removeEventListener('visibilitychange', onVisible)
  }, [refresh])

  // Replay offline-queued set updates whenever connectivity may have returned
  useEffect(() => {
    const tryFlush = () => {
      if (outbox.size() === 0) return
      outbox.flush().then((done) => {
        if (done) refresh().catch(() => {})
      })
    }
    window.addEventListener('online', tryFlush)
    const interval = setInterval(tryFlush, 15000)
    tryFlush()
    return () => {
      window.removeEventListener('online', tryFlush)
      clearInterval(interval)
    }
  }, [refresh])

  const start = useCallback(
    async (from?: { routineId?: number; workoutId?: number; name?: string }) => {
      const w = await api<Workout>('/workouts', {
        method: 'POST',
        body: {
          routine_id: from?.routineId ?? null,
          workout_id: from?.workoutId ?? null,
          name: from?.name ?? null,
        },
      })
      setWorkout(w)
      return w
    },
    [],
  )

  const rename = useCallback(
    async (name: string) => {
      if (!workout) return
      const w = await api<Workout>(`/workouts/${workout.id}`, { method: 'PATCH', body: { name } })
      setWorkout(w)
    },
    [workout],
  )

  const updateNotes = useCallback(
    async (notes: string) => {
      if (!workout) return
      const w = await api<Workout>(`/workouts/${workout.id}`, { method: 'PATCH', body: { notes } })
      setWorkout(w)
    },
    [workout],
  )

  const addExercise = useCallback(
    async (exerciseId: number) => {
      if (!workout) return
      const w = await api<Workout>(`/workouts/${workout.id}/exercises`, {
        method: 'POST',
        body: { exercise_id: exerciseId },
      })
      setWorkout(w)
    },
    [workout],
  )

  const removeExercise = useCallback(
    async (weId: number) => {
      if (!workout) return
      const w = await api<Workout>(`/workouts/${workout.id}/exercises/${weId}`, { method: 'DELETE' })
      setWorkout(w)
    },
    [workout],
  )

  const setExerciseRest = useCallback(
    async (weId: number, restSeconds: number | null) => {
      if (!workout) return
      const w = await api<Workout>(`/workouts/${workout.id}/exercises/${weId}`, {
        method: 'PATCH',
        body: { rest_seconds: restSeconds },
      })
      setWorkout(w)
    },
    [workout],
  )

  const setSupersetLink = useCallback(
    async (weId: number, withNext: boolean) => {
      if (!workout) return
      const w = await api<Workout>(`/workouts/${workout.id}/exercises/${weId}`, {
        method: 'PATCH',
        body: { superset_with_next: withNext },
      })
      setWorkout(w)
    },
    [workout],
  )

  const reorderExercises = useCallback(
    async (weIds: number[]) => {
      if (!workout) return
      // Optimistic — the drag already showed the new order
      setWorkout((prev) =>
        prev
          ? {
              ...prev,
              exercises: weIds
                .map((id) => prev.exercises.find((we) => we.id === id))
                .filter((we): we is NonNullable<typeof we> => we != null)
                .map((we, i) => ({ ...we, position: i })),
            }
          : prev,
      )
      const w = await api<Workout>(`/workouts/${workout.id}/exercise-order`, {
        method: 'PUT',
        body: { exercise_ids: weIds },
      })
      setWorkout(w)
    },
    [workout],
  )

  const addSet = useCallback(
    async (weId: number) => {
      if (!workout) return
      const w = await api<Workout>(`/workouts/${workout.id}/exercises/${weId}/sets`, { method: 'POST' })
      setWorkout(w)
    },
    [workout],
  )

  const applySet = useCallback((setId: number, apply: (s: SetEntry) => SetEntry) => {
    setWorkout((prev) =>
      prev
        ? {
            ...prev,
            exercises: prev.exercises.map((we) => ({
              ...we,
              sets: we.sets.map((s) => (s.id === setId ? apply(s) : s)),
            })),
          }
        : prev,
    )
  }, [])

  const updateSet = useCallback<WorkoutContextValue['updateSet']>(
    async (setId, patch) => {
      // Optimistic first — logging a set must feel instant, connection or not
      let optimistic: SetEntry | null = null
      applySet(setId, (s) => {
        optimistic = { ...s, ...patch }
        return optimistic
      })
      try {
        const updated = await api<SetEntry>(`/sets/${setId}`, { method: 'PATCH', body: patch })
        applySet(setId, () => updated)
        return updated
      } catch (e) {
        if (isNetworkError(e) && optimistic) {
          // Gym dead zone: keep the optimistic state, sync when back online
          outbox.add(setId, patch)
          return optimistic
        }
        toast('Could not save the set — try again')
        throw e
      }
    },
    [applySet],
  )

  const deleteSet = useCallback(async (weId: number, setId: number) => {
    await api(`/sets/${setId}`, { method: 'DELETE' })
    setWorkout((prev) =>
      prev
        ? {
            ...prev,
            exercises: prev.exercises.map((we) =>
              we.id === weId
                ? {
                    ...we,
                    sets: we.sets
                      .filter((s) => s.id !== setId)
                      .map((s, i) => ({ ...s, position: i })),
                  }
                : we,
            ),
          }
        : prev,
    )
  }, [])

  const finish = useCallback(async () => {
    if (!workout) throw new Error('No active workout')
    // Finish computes PRs server-side — every queued set must land first
    const flushed = await outbox.flush()
    if (!flushed) {
      throw new Error('You appear to be offline — your sets are saved; finish once you reconnect.')
    }
    const result = await api<FinishResult>(`/workouts/${workout.id}/finish`, { method: 'POST' })
    setWorkout(null)
    return result
  }, [workout])

  const discard = useCallback(async () => {
    if (!workout) return
    await api(`/workouts/${workout.id}`, { method: 'DELETE' })
    setWorkout(null)
  }, [workout])

  return (
    <WorkoutContext.Provider
      value={{
        workout,
        loading,
        refresh,
        start,
        rename,
        updateNotes,
        addExercise,
        removeExercise,
        setExerciseRest,
        setSupersetLink,
        reorderExercises,
        addSet,
        updateSet,
        deleteSet,
        finish,
        discard,
      }}
    >
      {children}
    </WorkoutContext.Provider>
  )
}

export function useWorkout(): WorkoutContextValue {
  const ctx = useContext(WorkoutContext)
  if (!ctx) throw new Error('useWorkout outside WorkoutProvider')
  return ctx
}
