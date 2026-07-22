import { createContext, useCallback, useContext, useEffect, useRef, useState, type ReactNode } from 'react'
import { api, ApiError } from '../lib/api'
import { delCached, getCached, setCached } from '../lib/dataCache'
import { getCachedExercises } from '../lib/exerciseCache'
import {
  buildLocalWorkout,
  blankSet,
  countCompletedSets,
  localExercise,
  localFinishSummary,
  newClientId,
  nextTempId,
  relabelSupersets,
  syncPayload,
  utcStamp,
} from '../lib/localWorkout'
import { isNetworkError, outbox } from '../lib/outbox'
import { syncQueue } from '../lib/syncQueue'
import { toast } from '../lib/toast'
import type { FinishResult, Routine, SetEntry, Workout } from '../lib/types'

interface WorkoutContextValue {
  workout: Workout | null
  loading: boolean
  /** Local changes not yet on the server — the workout is in offline mode */
  dirty: boolean
  refresh: () => Promise<void>
  start: (from?: { routineId?: number; workoutId?: number; name?: string }) => Promise<Workout>
  rename: (name: string) => Promise<void>
  updateNotes: (notes: string) => Promise<void>
  addExercise: (exerciseId: number) => Promise<number | undefined>
  removeExercise: (weId: number) => Promise<void>
  setExerciseRest: (weId: number, restSeconds: number | null) => Promise<void>
  setSupersetLink: (weId: number, withNext: boolean) => Promise<void>
  swapExercise: (weId: number, exerciseId: number) => Promise<void>
  reorderExercises: (weIds: number[]) => Promise<void>
  addSet: (weId: number) => Promise<void>
  addWarmupSets: (
    weId: number,
    sets: { position: number; weight: number | null; reps: number | null }[],
  ) => Promise<void>
  updateSet: (
    setId: number,
    patch: Partial<Pick<SetEntry, 'weight' | 'reps' | 'is_completed' | 'is_warmup' | 'set_type' | 'rpe'>>,
  ) => Promise<SetEntry>
  deleteSet: (weId: number, setId: number) => Promise<void>
  finish: () => Promise<FinishResult>
  discard: () => Promise<void>
}

const WorkoutContext = createContext<WorkoutContextValue | null>(null)

export function WorkoutProvider({ children }: { children: ReactNode }) {
  // Start from the cached workout so an offline reload resumes mid-session
  const [workout, setWorkout] = useState<Workout | null>(() => getCached<Workout>('activeWorkout'))
  const [loading, setLoading] = useState(() => getCached<Workout>('activeWorkout') == null)
  const [dirty, setDirty] = useState<boolean>(() => getCached<boolean>('activeWorkoutDirty') ?? false)

  // Refs for async flows that must see the latest state, and an epoch that
  // guards against a stale sync response clobbering newer local edits
  const workoutRef = useRef(workout)
  workoutRef.current = workout
  const dirtyRef = useRef(dirty)
  dirtyRef.current = dirty
  const epochRef = useRef(0)
  const syncErrorToastAt = useRef(0)

  // Single write-through point for every setWorkout call site
  useEffect(() => {
    if (workout) setCached('activeWorkout', workout)
    else delCached('activeWorkout')
  }, [workout])

  useEffect(() => {
    if (dirty) setCached('activeWorkoutDirty', true)
    else delCached('activeWorkoutDirty')
  }, [dirty])

  /** Adopt a server document, keeping the client_id every doc must carry */
  const adopt = useCallback((w: Workout | null) => {
    setWorkout((prev) => {
      if (!w) return null
      const kept = prev && prev.id === w.id ? prev.client_id : null
      return { ...w, client_id: w.client_id ?? kept ?? newClientId() }
    })
  }, [])

  /** Apply a mutation to the local document and flag it for sync */
  const applyLocal = useCallback((mutate: (w: Workout) => Workout) => {
    epochRef.current++
    setWorkout((prev) => (prev ? mutate(prev) : prev))
    setDirty(true)
  }, [])

  /** Server-first with a local fallback: the shape of every simple mutation */
  const mutateWorkout = useCallback(
    async (call: () => Promise<Workout>, local: (w: Workout) => Workout) => {
      if (!dirtyRef.current) {
        try {
          adopt(await call())
          return
        } catch (e) {
          if (!isNetworkError(e)) throw e
        }
      }
      applyLocal(local)
    },
    [adopt, applyLocal],
  )

  /** Push everything pending: queued offline finishes first (ordering), then
   *  the dirty active document. Safe to call any time; no-op when clean. */
  const sync = useCallback(async () => {
    const drained = await syncQueue.flush()
    if (!drained || !dirtyRef.current) return
    const doc = workoutRef.current
    if (!doc) {
      setDirty(false)
      return
    }
    const epoch = epochRef.current
    try {
      const res = await api<{ workout: Workout | null; finish: FinishResult | null }>(
        '/workouts/sync',
        { method: 'PUT', body: syncPayload(doc) },
      )
      if (epochRef.current !== epoch) return // edited mid-flight — next tick pushes again
      if (res.workout) adopt(res.workout)
      else setWorkout(null) // finished or removed on the server side
      setDirty(false)
    } catch (e) {
      if (isNetworkError(e)) return // still offline — retry later
      if (e instanceof ApiError && Date.now() - syncErrorToastAt.current > 300_000) {
        syncErrorToastAt.current = Date.now()
        toast('Could not sync your workout — will keep trying')
      }
    }
  }, [adopt])

  const refresh = useCallback(async () => {
    // With local changes pending, pulling server state would clobber them —
    // push instead; the sync response is the fresh state.
    if (dirtyRef.current || syncQueue.size() > 0) {
      await sync()
      return
    }
    const active = await api<Workout | null>('/workouts/active')
    adopt(active)
  }, [adopt, sync])

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

  // Replay offline work whenever connectivity may have returned. The legacy
  // per-set outbox (pre-sync app versions) drains first, then document sync.
  useEffect(() => {
    const trySync = () => {
      if (outbox.size() > 0) {
        outbox.flush().then((done) => {
          if (done) refresh().catch(() => {})
        })
        return
      }
      sync().catch(() => {})
    }
    window.addEventListener('online', trySync)
    const interval = setInterval(trySync, 15000)
    trySync()
    return () => {
      window.removeEventListener('online', trySync)
      clearInterval(interval)
    }
  }, [refresh, sync])

  const start = useCallback(
    async (from?: { routineId?: number; workoutId?: number; name?: string }) => {
      try {
        const w = await api<Workout>('/workouts', {
          method: 'POST',
          body: {
            routine_id: from?.routineId ?? null,
            workout_id: from?.workoutId ?? null,
            name: from?.name ?? null,
          },
        })
        const withCid = { ...w, client_id: w.client_id ?? newClientId() }
        setWorkout(withCid)
        return withCid
      } catch (e) {
        if (!isNetworkError(e)) throw e
        // Offline start — build the document locally and sync it later
        if (from?.workoutId != null) {
          throw new Error('Repeating a past workout needs a connection')
        }
        let local: Workout
        if (from?.routineId != null) {
          const routine = getCached<Routine[]>('routines')?.find((r) => r.id === from.routineId)
          if (!routine) throw new Error('This template is not available offline')
          local = buildLocalWorkout({ routine })
        } else {
          local = buildLocalWorkout({ name: from?.name })
        }
        epochRef.current++
        setWorkout(local)
        setDirty(true)
        return local
      }
    },
    [],
  )

  const rename = useCallback(
    async (name: string) => {
      if (!workout) return
      await mutateWorkout(
        () => api<Workout>(`/workouts/${workout.id}`, { method: 'PATCH', body: { name } }),
        (w) => ({ ...w, name }),
      )
    },
    [workout, mutateWorkout],
  )

  const updateNotes = useCallback(
    async (notes: string) => {
      if (!workout) return
      await mutateWorkout(
        () => api<Workout>(`/workouts/${workout.id}`, { method: 'PATCH', body: { notes } }),
        (w) => ({ ...w, notes }),
      )
    },
    [workout, mutateWorkout],
  )

  const addExercise = useCallback(
    async (exerciseId: number) => {
      if (!workout) return
      if (!dirtyRef.current) {
        try {
          const w = await api<Workout>(`/workouts/${workout.id}/exercises`, {
            method: 'POST',
            body: { exercise_id: exerciseId },
          })
          adopt(w)
          // The new exercise's id, so callers can e.g. superset-link it
          return w.exercises[w.exercises.length - 1]?.id
        } catch (e) {
          if (!isNetworkError(e)) throw e
        }
      }
      const ex = getCachedExercises()?.find((x) => x.id === exerciseId)
      if (!ex) {
        toast('That exercise is not available offline')
        return
      }
      let newId: number | undefined
      applyLocal((w) => {
        const base = nextTempId(w)
        newId = base
        const we = localExercise(
          base,
          [base - 1],
          { exercise_id: ex.id, name: ex.name, muscle_group: ex.muscle_group, equipment: ex.equipment },
          { position: w.exercises.length },
        )
        return { ...w, exercises: [...w.exercises, we] }
      })
      return newId
    },
    [workout, adopt, applyLocal],
  )

  const removeExercise = useCallback(
    async (weId: number) => {
      if (!workout) return
      await mutateWorkout(
        () => api<Workout>(`/workouts/${workout.id}/exercises/${weId}`, { method: 'DELETE' }),
        (w) => ({
          ...w,
          exercises: relabelSupersets(
            w.exercises.filter((we) => we.id !== weId).map((we, i) => ({ ...we, position: i })),
          ),
        }),
      )
    },
    [workout, mutateWorkout],
  )

  const setExerciseRest = useCallback(
    async (weId: number, restSeconds: number | null) => {
      if (!workout) return
      await mutateWorkout(
        () =>
          api<Workout>(`/workouts/${workout.id}/exercises/${weId}`, {
            method: 'PATCH',
            body: { rest_seconds: restSeconds },
          }),
        (w) => ({
          ...w,
          exercises: w.exercises.map((we) =>
            we.id === weId ? { ...we, rest_seconds: restSeconds } : we,
          ),
        }),
      )
    },
    [workout, mutateWorkout],
  )

  const swapExercise = useCallback(
    async (weId: number, exerciseId: number) => {
      if (!workout) return
      const local = (w: Workout) => {
        const ex = getCachedExercises()?.find((x) => x.id === exerciseId)
        if (!ex) return w
        return {
          ...w,
          exercises: w.exercises.map((we) =>
            we.id === weId
              ? {
                  ...we,
                  exercise_id: ex.id,
                  name: ex.name,
                  muscle_group: ex.muscle_group,
                  equipment: ex.equipment,
                  note: '',
                  // Swapping clears template targets — mirrors the server
                  rep_min: null,
                  rep_max: null,
                  suggested_weight: null,
                  suggestion_kind: null,
                  previous_sets: [],
                }
              : we,
          ),
        }
      }
      if (!dirtyRef.current) {
        try {
          adopt(
            await api<Workout>(`/workouts/${workout.id}/exercises/${weId}`, {
              method: 'PATCH',
              body: { exercise_id: exerciseId },
            }),
          )
          return
        } catch (e) {
          if (!isNetworkError(e)) throw e
        }
      }
      if (!getCachedExercises()?.some((x) => x.id === exerciseId)) {
        throw new Error('That exercise is not available offline')
      }
      applyLocal(local)
    },
    [workout, adopt, applyLocal],
  )

  const setSupersetLink = useCallback(
    async (weId: number, withNext: boolean) => {
      if (!workout) return
      await mutateWorkout(
        () =>
          api<Workout>(`/workouts/${workout.id}/exercises/${weId}`, {
            method: 'PATCH',
            body: { superset_with_next: withNext },
          }),
        (w) => ({
          ...w,
          exercises: relabelSupersets(
            w.exercises.map((we) => (we.id === weId ? { ...we, superset_with_next: withNext } : we)),
          ),
        }),
      )
    },
    [workout, mutateWorkout],
  )

  const reorderExercises = useCallback(
    async (weIds: number[]) => {
      if (!workout) return
      const reorder = (w: Workout) => ({
        ...w,
        exercises: relabelSupersets(
          weIds
            .map((id) => w.exercises.find((we) => we.id === id))
            .filter((we): we is NonNullable<typeof we> => we != null)
            .map((we, i) => ({ ...we, position: i })),
        ),
      })
      if (dirtyRef.current) {
        applyLocal(reorder)
        return
      }
      // Optimistic — the drag already showed the new order
      setWorkout((prev) => (prev ? reorder(prev) : prev))
      try {
        adopt(
          await api<Workout>(`/workouts/${workout.id}/exercise-order`, {
            method: 'PUT',
            body: { exercise_ids: weIds },
          }),
        )
      } catch (e) {
        if (!isNetworkError(e)) throw e
        epochRef.current++
        setDirty(true) // keep the optimistic order, sync later
      }
    },
    [workout, adopt, applyLocal],
  )

  const addSet = useCallback(
    async (weId: number) => {
      if (!workout) return
      await mutateWorkout(
        () =>
          api<Workout>(`/workouts/${workout.id}/exercises/${weId}/sets`, { method: 'POST' }),
        (w) => ({
          ...w,
          exercises: w.exercises.map((we) =>
            we.id === weId
              ? { ...we, sets: [...we.sets, blankSet(nextTempId(w), we.sets.length)] }
              : we,
          ),
        }),
      )
    },
    [workout, mutateWorkout],
  )

  const addWarmupSets = useCallback<WorkoutContextValue['addWarmupSets']>(
    async (weId, sets) => {
      if (!workout) return
      if (!dirtyRef.current) {
        try {
          for (const s of sets) {
            await api(`/workouts/${workout.id}/exercises/${weId}/sets`, {
              method: 'POST',
              body: { position: s.position, weight: s.weight, reps: s.reps, is_warmup: true },
            })
          }
          const active = await api<Workout | null>('/workouts/active')
          adopt(active)
          return
        } catch (e) {
          if (!isNetworkError(e)) throw e
        }
      }
      applyLocal((w) => ({
        ...w,
        exercises: w.exercises.map((we) => {
          if (we.id !== weId) return we
          const merged = [...we.sets]
          let temp = nextTempId(w)
          for (const s of [...sets].sort((a, b) => a.position - b.position)) {
            merged.splice(Math.min(s.position, merged.length), 0, {
              ...blankSet(temp--, s.position),
              weight: s.weight,
              reps: s.reps,
              is_warmup: true,
            })
          }
          return { ...we, sets: merged.map((x, i) => ({ ...x, position: i })) }
        }),
      }))
    },
    [workout, adopt, applyLocal],
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
      // Stamp completion time client-side so offline rest analytics hold up
      const stamped: typeof patch & { completed_at?: string | null } = { ...patch }
      if (patch.is_completed === true) stamped.completed_at = utcStamp()
      if (patch.is_completed === false) stamped.completed_at = null

      // Optimistic first — logging a set must feel instant, connection or not
      let optimistic: SetEntry | null = null
      applySet(setId, (s) => {
        optimistic = { ...s, ...stamped }
        return optimistic
      })
      if (dirtyRef.current || setId < 0) {
        epochRef.current++
        setDirty(true)
        return optimistic!
      }
      try {
        const updated = await api<SetEntry>(`/sets/${setId}`, { method: 'PATCH', body: patch })
        applySet(setId, () => updated)
        return updated
      } catch (e) {
        if (isNetworkError(e) && optimistic) {
          // Gym dead zone: keep the optimistic state, sync the doc when back
          epochRef.current++
          setDirty(true)
          return optimistic
        }
        toast('Could not save the set — try again')
        throw e
      }
    },
    [applySet],
  )

  const deleteSet = useCallback(
    async (weId: number, setId: number) => {
      if (!workout) return
      const workoutId = workout.id
      const snapshot = workout.exercises
        .find((we) => we.id === weId)
        ?.sets.find((s) => s.id === setId)
      const removeLocal = (w: Workout) => ({
        ...w,
        exercises: w.exercises.map((we) =>
          we.id === weId
            ? {
                ...we,
                sets: we.sets
                  .filter((s) => s.id !== setId)
                  .map((s, i) => ({ ...s, position: i })),
              }
            : we,
        ),
      })
      let offline = dirtyRef.current || setId < 0
      if (!offline) {
        try {
          await api(`/sets/${setId}`, { method: 'DELETE' })
        } catch (e) {
          if (!isNetworkError(e)) throw e
          offline = true
        }
      }
      if (offline) applyLocal(removeLocal)
      else setWorkout((prev) => (prev ? removeLocal(prev) : prev))

      if (snapshot) {
        const restoreLocal = (w: Workout) => ({
          ...w,
          exercises: w.exercises.map((we) => {
            if (we.id !== weId) return we
            const sets = [...we.sets]
            sets.splice(Math.min(snapshot.position, sets.length), 0, {
              ...snapshot,
              id: nextTempId(w),
            })
            return { ...we, sets: sets.map((s, i) => ({ ...s, position: i })) }
          }),
        })
        toast('Set deleted', {
          kind: 'info',
          duration: 5000,
          action: {
            label: 'Undo',
            run: async () => {
              if (dirtyRef.current) {
                applyLocal(restoreLocal)
                return
              }
              try {
                const w = await api<Workout>(`/workouts/${workoutId}/exercises/${weId}/sets`, {
                  method: 'POST',
                  body: {
                    position: snapshot.position,
                    weight: snapshot.weight,
                    reps: snapshot.reps,
                    is_completed: snapshot.is_completed,
                    is_warmup: snapshot.is_warmup,
                    rpe: snapshot.rpe,
                  },
                })
                adopt(w)
              } catch (e) {
                if (isNetworkError(e)) applyLocal(restoreLocal)
                else toast('Could not restore the set')
              }
            },
          },
        })
      }
    },
    [workout, adopt, applyLocal],
  )

  const finish = useCallback(async () => {
    const w = workoutRef.current
    if (!w) throw new Error('No active workout')
    // The sync path deletes an all-incomplete workout, /finish 400s on it —
    // guard here so every path behaves like the online one
    if (countCompletedSets(w) === 0) {
      throw new Error('Complete at least one set before finishing')
    }
    const finishedAt = utcStamp()

    if (!dirtyRef.current && w.id > 0) {
      // Clean server-backed workout: classic finish (legacy outbox first)
      const flushed = await outbox.flush()
      if (flushed) {
        try {
          const result = await api<FinishResult>(`/workouts/${w.id}/finish`, { method: 'POST' })
          setWorkout(null)
          return result
        } catch (e) {
          if (!isNetworkError(e)) throw e
        }
      }
    } else {
      // Dirty or local-only: one-shot sync that also finishes — when the
      // connection is up this still returns the full PR summary
      try {
        const res = await api<{ workout: Workout | null; finish: FinishResult | null }>(
          '/workouts/sync',
          { method: 'PUT', body: syncPayload(w, finishedAt) },
        )
        setWorkout(null)
        setDirty(false)
        return res.finish ?? localFinishSummary(w, finishedAt)
      } catch (e) {
        if (!isNetworkError(e)) throw e
      }
    }

    // Offline: queue the finished document, summarize locally; PRs follow
    syncQueue.enqueueFinish(syncPayload(w, finishedAt), w.name)
    setWorkout(null)
    setDirty(false)
    return localFinishSummary(w, finishedAt)
  }, [])

  const discard = useCallback(async () => {
    const w = workoutRef.current
    if (!w) return
    if (w.id > 0) {
      try {
        await api(`/workouts/${w.id}`, { method: 'DELETE' })
      } catch (e) {
        if (!isNetworkError(e)) throw e
        syncQueue.enqueueDiscard(w.id)
      }
    }
    setWorkout(null)
    setDirty(false)
  }, [])

  return (
    <WorkoutContext.Provider
      value={{
        workout,
        loading,
        dirty,
        refresh,
        start,
        rename,
        updateNotes,
        addExercise,
        removeExercise,
        setExerciseRest,
        setSupersetLink,
        swapExercise,
        reorderExercises,
        addSet,
        addWarmupSets,
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
