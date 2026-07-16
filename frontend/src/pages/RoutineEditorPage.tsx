import { ChevronLeft, GripVertical, Link2, Minus, Plus, Trash2 } from 'lucide-react'
import { useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import ConfirmSheet from '../components/ConfirmSheet'
import ExercisePicker from '../components/ExercisePicker'
import Skeleton from '../components/Skeleton'
import { useAuth } from '../contexts/AuthContext'
import { api } from '../lib/api'
import type { Exercise, Routine } from '../lib/types'
import { restLabel } from '../lib/format'
import { moveItem, useDragReorder } from '../lib/useDragReorder'

interface DraftExercise {
  exercise_id: number
  name: string
  set_count: number
  rest_seconds: number | null
  superset_with_next: boolean
  rep_min: number | null
  rep_max: number | null
  increment: number | null
}

const REST_OPTIONS = [0, 30, 45, 60, 90, 120, 150, 180, 240, 300]

export default function RoutineEditorPage() {
  const { id } = useParams()
  const navigate = useNavigate()
  const { user } = useAuth()
  const editing = id != null
  const [name, setName] = useState('')
  const [loadingRoutine, setLoadingRoutine] = useState(editing)
  const [exercises, setExercises] = useState<DraftExercise[]>([])
  const [pickerOpen, setPickerOpen] = useState(false)
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const [dirty, setDirty] = useState(false)
  const [confirmLeave, setConfirmLeave] = useState(false)
  const { handleProps, itemProps } = useDragReorder(exercises.length, (from, to) =>
    setExercises((xs) => moveItem(xs, from, to)),
  )

  useEffect(() => {
    if (editing) {
      api<Routine>(`/routines/${id}`)
        .then((r) => {
          setName(r.name)
          setExercises(
            r.exercises.map((e) => ({
              exercise_id: e.exercise_id,
              name: e.name,
              set_count: e.set_count,
              rest_seconds: e.rest_seconds,
              superset_with_next: e.superset_with_next,
              rep_min: e.rep_min,
              rep_max: e.rep_max,
              increment: e.increment,
            })),
          )
        })
        .catch(() => navigate('/', { replace: true }))
        .finally(() => setLoadingRoutine(false))
    }
  }, [editing, id, navigate])

  if (loadingRoutine) {
    return (
      <div className="safe-top px-4 md:max-w-2xl">
        <div className="flex items-center gap-2 pt-4 pb-4">
          <Skeleton className="h-8 w-48" />
        </div>
        <Skeleton className="h-12 w-full" />
        <div className="mt-5 flex flex-col gap-3">
          {Array.from({ length: 3 }, (_, i) => (
            <Skeleton key={i} className="h-24 rounded-xl" />
          ))}
        </div>
      </div>
    )
  }

  const addExercise = (exercise: Exercise) => {
    setDirty(true)
    setExercises((xs) => [
      ...xs,
      {
        exercise_id: exercise.id,
        name: exercise.name,
        set_count: 3,
        rest_seconds: null,
        superset_with_next: false,
        rep_min: null,
        rep_max: null,
        increment: null,
      },
    ])
    setPickerOpen(false)
  }

  const update = (index: number, patch: Partial<DraftExercise>) => {
    setDirty(true)
    setExercises((xs) => xs.map((x, i) => (i === index ? { ...x, ...patch } : x)))
  }

  const save = async () => {
    setError('')
    setBusy(true)
    try {
      const body = {
        name,
        exercises: exercises.map((e, i) => ({
          exercise_id: e.exercise_id,
          set_count: e.set_count,
          rest_seconds: e.rest_seconds,
          superset_with_next: i < exercises.length - 1 && e.superset_with_next,
          rep_min: e.rep_min,
          rep_max: e.rep_max,
          increment: e.rep_max != null ? (e.increment ?? (user?.unit === 'lb' ? 5 : 2.5)) : null,
        })),
      }
      if (editing) await api(`/routines/${id}`, { method: 'PUT', body })
      else await api('/routines', { method: 'POST', body })
      navigate('/')
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to save')
    } finally {
      setBusy(false)
    }
  }

  const defaultRest = restLabel(user?.default_rest_seconds ?? 120)

  return (
    <div className="safe-top px-4 md:max-w-2xl">
      <header className="flex items-center gap-2 pt-4 pb-4">
        <button
          onClick={() => (dirty ? setConfirmLeave(true) : navigate(-1))}
          className="touch-feedback -ml-2 rounded-full p-2 text-muted-foreground"
          aria-label="Back"
        >
          <ChevronLeft size={24} />
        </button>
        <h1 className="text-2xl">{editing ? 'Edit template' : 'New template'}</h1>
      </header>

      <input
        value={name}
        onChange={(e) => {
          setDirty(true)
          setName(e.target.value)
        }}
        placeholder="Template name (e.g. Push Day)"
        className="h-12 w-full rounded-lg border border-input bg-card px-4 text-base outline-none focus:ring-2 focus:ring-ring"
      />

      <div className="mt-5 flex flex-col gap-3">
        {exercises.map((exercise, i) => (
          <div key={`${exercise.exercise_id}-${i}`} {...itemProps(i)} className="rounded-xl border bg-card p-3.5">
            <div className="flex items-center gap-2">
              <button
                {...handleProps(i)}
                aria-label={`Reorder ${exercise.name}`}
                className="-m-1 shrink-0 rounded p-1 text-muted-foreground/50"
              >
                <GripVertical size={16} />
              </button>
              <span className="min-w-0 flex-1 truncate font-medium">{exercise.name}</span>
              <button
                onClick={() => {
                  setDirty(true)
                  setExercises((xs) => xs.filter((_, j) => j !== i))
                }}
                className="touch-feedback rounded-full p-1.5 text-muted-foreground"
                aria-label="Remove exercise"
              >
                <Trash2 size={16} />
              </button>
            </div>
            <div className="mt-3 flex items-center justify-between gap-3">
              <div className="flex items-center gap-2">
                <span className="text-sm text-muted-foreground">Sets</span>
                <div className="flex items-center rounded-lg bg-secondary">
                  <button
                    onClick={() => update(i, { set_count: Math.max(1, exercise.set_count - 1) })}
                    className="touch-feedback p-2"
                    aria-label="Fewer sets"
                  >
                    <Minus size={14} />
                  </button>
                  <span className="tnum w-6 text-center font-semibold">{exercise.set_count}</span>
                  <button
                    onClick={() => update(i, { set_count: Math.min(20, exercise.set_count + 1) })}
                    className="touch-feedback p-2"
                    aria-label="More sets"
                  >
                    <Plus size={14} />
                  </button>
                </div>
              </div>
              <label className="flex items-center gap-2 text-sm text-muted-foreground">
                Rest
                <select
                  value={exercise.rest_seconds ?? 'default'}
                  onChange={(e) =>
                    update(i, {
                      rest_seconds: e.target.value === 'default' ? null : Number(e.target.value),
                    })
                  }
                  className="h-9 rounded-lg border border-input bg-card px-2 text-sm text-foreground outline-none"
                >
                  <option value="default">Default ({defaultRest})</option>
                  {REST_OPTIONS.map((s) => (
                    <option key={s} value={s}>
                      {restLabel(s)}
                    </option>
                  ))}
                </select>
              </label>
            </div>
            <div className="mt-2.5 flex items-center justify-between gap-3">
              <label className="flex items-center gap-2 text-sm text-muted-foreground">
                Reps
                <input
                  value={exercise.rep_min ?? ''}
                  onChange={(e) =>
                    update(i, { rep_min: e.target.value ? Number(e.target.value) : null })
                  }
                  inputMode="numeric"
                  placeholder="min"
                  className="tnum h-9 w-12 rounded-lg border border-input bg-card px-1 text-center text-sm text-foreground outline-none"
                />
                –
                <input
                  value={exercise.rep_max ?? ''}
                  onChange={(e) =>
                    update(i, { rep_max: e.target.value ? Number(e.target.value) : null })
                  }
                  inputMode="numeric"
                  placeholder="max"
                  className="tnum h-9 w-12 rounded-lg border border-input bg-card px-1 text-center text-sm text-foreground outline-none"
                />
              </label>
              {exercise.rep_max != null && (
                <label className="flex items-center gap-2 text-sm text-muted-foreground">
                  Progress
                  <select
                    value={exercise.increment ?? (user?.unit === 'lb' ? 5 : 2.5)}
                    onChange={(e) => update(i, { increment: Number(e.target.value) })}
                    className="h-9 rounded-lg border border-input bg-card px-2 text-sm text-foreground outline-none"
                  >
                    {(user?.unit === 'lb' ? [2.5, 5, 10] : [1.25, 2.5, 5]).map((inc) => (
                      <option key={inc} value={inc}>
                        +{inc} {user?.unit ?? 'kg'}
                      </option>
                    ))}
                  </select>
                </label>
              )}
            </div>
            {i < exercises.length - 1 && (
              <button
                onClick={() => update(i, { superset_with_next: !exercise.superset_with_next })}
                className={
                  exercise.superset_with_next
                    ? 'touch-feedback mt-2.5 flex items-center gap-1.5 rounded-lg bg-accent-soft px-2.5 py-1.5 text-xs font-semibold text-primary'
                    : 'touch-feedback mt-2.5 flex items-center gap-1.5 rounded-lg bg-secondary px-2.5 py-1.5 text-xs font-semibold text-muted-foreground'
                }
              >
                <Link2 size={13} />
                {exercise.superset_with_next ? 'Superset with next' : 'Superset with next?'}
              </button>
            )}
          </div>
        ))}
      </div>

      <button
        onClick={() => setPickerOpen(true)}
        className="touch-feedback mt-4 flex w-full items-center justify-center gap-2 rounded-xl border border-dashed py-3.5 font-semibold text-primary"
      >
        <Plus size={18} /> Add exercise
      </button>

      {error && <p className="mt-3 text-sm text-destructive">{error}</p>}

      <button
        onClick={save}
        disabled={busy || !name.trim() || exercises.length === 0}
        className="touch-feedback mt-5 h-12 w-full rounded-xl bg-primary text-base font-semibold text-primary-foreground disabled:opacity-50"
      >
        {busy ? 'Saving…' : 'Save template'}
      </button>

      <ConfirmSheet
        open={confirmLeave}
        onClose={() => setConfirmLeave(false)}
        title="Discard changes?"
        message="Your edits to this template haven't been saved."
        actionLabel="Discard changes"
        destructive
        onConfirm={() => {
          setConfirmLeave(false)
          navigate(-1)
        }}
      />

      <ExercisePicker open={pickerOpen} onClose={() => setPickerOpen(false)} onPick={addExercise} />
    </div>
  )
}
