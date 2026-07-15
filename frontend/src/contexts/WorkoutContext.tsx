import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react'
import { api } from '../lib/api'
import type { FinishResult, SetEntry, Workout } from '../lib/types'

interface WorkoutContextValue {
  workout: Workout | null
  loading: boolean
  refresh: () => Promise<void>
  start: (routineId?: number) => Promise<Workout>
  rename: (name: string) => Promise<void>
  addExercise: (exerciseId: number) => Promise<void>
  removeExercise: (weId: number) => Promise<void>
  setExerciseRest: (weId: number, restSeconds: number | null) => Promise<void>
  addSet: (weId: number) => Promise<void>
  updateSet: (setId: number, patch: Partial<Pick<SetEntry, 'weight' | 'reps' | 'is_completed'>>) => Promise<SetEntry>
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

  const start = useCallback(async (routineId?: number) => {
    const w = await api<Workout>('/workouts', {
      method: 'POST',
      body: routineId != null ? { routine_id: routineId } : {},
    })
    setWorkout(w)
    return w
  }, [])

  const rename = useCallback(
    async (name: string) => {
      if (!workout) return
      const w = await api<Workout>(`/workouts/${workout.id}`, { method: 'PATCH', body: { name } })
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

  const addSet = useCallback(
    async (weId: number) => {
      if (!workout) return
      const w = await api<Workout>(`/workouts/${workout.id}/exercises/${weId}/sets`, { method: 'POST' })
      setWorkout(w)
    },
    [workout],
  )

  const updateSet = useCallback<WorkoutContextValue['updateSet']>(async (setId, patch) => {
    const updated = await api<SetEntry>(`/sets/${setId}`, { method: 'PATCH', body: patch })
    setWorkout((prev) =>
      prev
        ? {
            ...prev,
            exercises: prev.exercises.map((we) => ({
              ...we,
              sets: we.sets.map((s) => (s.id === setId ? updated : s)),
            })),
          }
        : prev,
    )
    return updated
  }, [])

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
        addExercise,
        removeExercise,
        setExerciseRest,
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
