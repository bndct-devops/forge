import { Check, ChevronLeft, Clock, Pencil, Plus, RotateCcw, Share, Trash2, Trophy, Weight, X } from 'lucide-react'
import { useEffect, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import ExercisePicker from '../components/ExercisePicker'
import Sheet from '../components/Sheet'
import { useAuth } from '../contexts/AuthContext'
import { useWorkout } from '../contexts/WorkoutContext'
import { api } from '../lib/api'
import {
  formatDuration,
  formatRelativeDate,
  formatSetWeight,
  formatTime,
  formatVolume,
  parseUTC,
  toDatetimeLocal,
} from '../lib/format'
import { shareWorkoutCard } from '../lib/shareCard'
import { toast } from '../lib/toast'
import type { SetEntry, Workout, WorkoutExercise } from '../lib/types'
import { cn } from '../lib/utils'
import Skeleton, { CardListSkeleton } from '../components/Skeleton'

function parseNum(value: string): number | null {
  const n = parseFloat(value.replace(',', '.'))
  return Number.isFinite(n) ? n : null
}

interface EditSetRowProps {
  set: SetEntry
  unit: string
  bodyweight: boolean
  onCommit: (patch: { weight: number | null; reps: number | null }) => void
  onToggleWarmup: () => void
  onDelete: () => void
}

/** Editable set line for finished workouts — commits on blur. A set missing
 *  its reps gets pruned when the edit session closes. */
function EditSetRow({ set, unit, bodyweight, onCommit, onToggleWarmup, onDelete }: EditSetRowProps) {
  const [weight, setWeight] = useState(set.weight != null && set.weight !== 0 ? String(set.weight) : '')
  const [reps, setReps] = useState(set.reps != null ? String(set.reps) : '')

  const commit = () => {
    const w = weight !== '' ? parseNum(weight) : bodyweight ? 0 : null
    const r = reps !== '' ? parseNum(reps) : null
    onCommit({ weight: w, reps: r })
  }

  return (
    <div className="grid grid-cols-[2rem_1fr_4.5rem_4rem_2.75rem] items-center gap-2 py-1.5">
      <button
        onClick={onToggleWarmup}
        aria-label={set.is_warmup ? 'Make working set' : 'Make warm-up set'}
        className="touch-feedback tnum rounded-md py-1 text-center text-sm font-semibold text-muted-foreground"
      >
        {set.is_warmup ? <span className="text-warning">W</span> : set.position + 1}
      </button>
      <span />
      <input
        value={weight}
        onChange={(e) => setWeight(e.target.value)}
        onBlur={commit}
        onFocus={(e) => e.target.select()}
        inputMode="decimal"
        placeholder={bodyweight ? 'BW' : unit}
        className="tnum h-9 rounded-md border border-input bg-background px-1 text-center text-base font-medium outline-none placeholder:text-muted-foreground/50 focus:ring-2 focus:ring-ring"
      />
      <input
        value={reps}
        onChange={(e) => setReps(e.target.value)}
        onBlur={commit}
        onFocus={(e) => e.target.select()}
        inputMode="numeric"
        placeholder="reps"
        className="tnum h-9 rounded-md border border-input bg-background px-1 text-center text-base font-medium outline-none placeholder:text-muted-foreground/50 focus:ring-2 focus:ring-ring"
      />
      <button
        onClick={onDelete}
        aria-label="Delete set"
        className="touch-feedback mx-auto flex h-9 w-9 items-center justify-center rounded-lg border border-input bg-secondary text-muted-foreground"
      >
        <X size={16} />
      </button>
    </div>
  )
}

export default function WorkoutDetailPage() {
  const { id } = useParams()
  const navigate = useNavigate()
  const { user } = useAuth()
  const { workout: activeWorkout, start } = useWorkout()
  const [workout, setWorkout] = useState<Workout | null>(null)
  const [editing, setEditing] = useState(false)
  const [repeatError, setRepeatError] = useState('')
  const [pickerOpen, setPickerOpen] = useState(false)
  const [confirmDelete, setConfirmDelete] = useState(false)
  const [saving, setSaving] = useState(false)
  const unit = user?.unit ?? 'kg'

  useEffect(() => {
    api<Workout>(`/workouts/${id}`)
      .then(setWorkout)
      .catch(() => navigate('/history', { replace: true }))
  }, [id, navigate])

  if (!workout) {
    return (
      <div className="safe-top px-4">
        <div className="flex items-center gap-2 pt-4 pb-3">
          <Skeleton className="h-8 w-56" />
        </div>
        <div className="mt-2 grid grid-cols-3 gap-2 md:max-w-md">
          {Array.from({ length: 3 }, (_, i) => (
            <Skeleton key={i} className="h-20 rounded-xl" />
          ))}
        </div>
        <CardListSkeleton count={2} className="mt-4 md:grid-cols-2" />
      </div>
    )
  }

  const remove = async () => {
    await api(`/workouts/${workout.id}`, { method: 'DELETE' })
    navigate('/history', { replace: true })
  }

  const replaceWorkout = (w: Workout) => setWorkout({ ...workout, ...w })

  const commitSet = async (setId: number, patch: { weight: number | null; reps: number | null }) => {
    const complete = patch.reps != null && patch.weight != null
    const updated = await api<SetEntry>(`/sets/${setId}`, {
      method: 'PATCH',
      body: {
        weight: patch.weight ?? undefined,
        reps: patch.reps ?? undefined,
        is_completed: complete,
      },
    })
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
  }

  const toggleWarmup = async (set: SetEntry) => {
    const updated = await api<SetEntry>(`/sets/${set.id}`, {
      method: 'PATCH',
      body: { is_warmup: !set.is_warmup },
    })
    setWorkout((prev) =>
      prev
        ? {
            ...prev,
            exercises: prev.exercises.map((we) => ({
              ...we,
              sets: we.sets.map((s) => (s.id === set.id ? updated : s)),
            })),
          }
        : prev,
    )
  }

  const deleteSet = async (weId: number, setId: number) => {
    await api(`/sets/${setId}`, { method: 'DELETE' })
    setWorkout((prev) =>
      prev
        ? {
            ...prev,
            exercises: prev.exercises.map((we) =>
              we.id === weId
                ? {
                    ...we,
                    sets: we.sets.filter((s) => s.id !== setId).map((s, i) => ({ ...s, position: i })),
                  }
                : we,
            ),
          }
        : prev,
    )
  }

  const addSet = async (weId: number) => {
    replaceWorkout(await api<Workout>(`/workouts/${workout.id}/exercises/${weId}/sets`, { method: 'POST' }))
  }

  const addExercise = async (exerciseId: number) => {
    setPickerOpen(false)
    replaceWorkout(
      await api<Workout>(`/workouts/${workout.id}/exercises`, {
        method: 'POST',
        body: { exercise_id: exerciseId },
      }),
    )
  }

  const removeExercise = async (we: WorkoutExercise) => {
    replaceWorkout(await api<Workout>(`/workouts/${workout.id}/exercises/${we.id}`, { method: 'DELETE' }))
  }

  const finishEditing = async () => {
    setSaving(true)
    try {
      const result = await api<Workout & { deleted?: boolean }>(
        `/workouts/${workout.id}/recompute`,
        { method: 'POST' },
      )
      if (result.deleted) {
        navigate('/history', { replace: true })
        return
      }
      setWorkout(result)
      setEditing(false)
    } finally {
      setSaving(false)
    }
  }

  const share = async () => {
    const prs = workout.exercises.flatMap((we) =>
      we.sets
        .filter((s) => s.is_pr)
        .map((s) => ({
          exercise_name: we.name,
          kind: 'weight',
          value: s.weight ?? 0,
          reps: s.reps ?? 0,
        })),
    )
    try {
      await shareWorkoutCard(
        {
          name: workout.name,
          duration_seconds: workout.duration_seconds ?? 0,
          total_volume: workout.total_volume ?? 0,
          total_sets: workout.total_sets ?? 0,
          prs,
          date: parseUTC(workout.started_at),
        },
        unit,
      )
    } catch {
      toast('Could not create the share image')
    }
  }

  return (
    <div className="safe-top w-full px-4 md:max-w-3xl">
      <header className="flex items-center gap-2 pt-4 pb-2">
        <button
          onClick={() => (editing ? finishEditing() : navigate(-1))}
          className="touch-feedback -ml-2 rounded-full p-2 text-muted-foreground"
          aria-label="Back"
        >
          <ChevronLeft size={24} />
        </button>
        <div className="min-w-0 flex-1">
          {editing ? (
            <input
              defaultValue={workout.name}
              onBlur={(e) => {
                const name = e.target.value.trim()
                if (name && name !== workout.name) {
                  api<Workout>(`/workouts/${workout.id}`, { method: 'PATCH', body: { name } }).then(replaceWorkout)
                }
              }}
              className="w-full truncate bg-transparent text-2xl font-semibold outline-none"
              style={{ fontFamily: "'Bricolage Grotesque', 'Onest', sans-serif" }}
            />
          ) : (
            <h1 className="truncate text-2xl">{workout.name}</h1>
          )}
          {editing ? (
            <input
              type="datetime-local"
              defaultValue={toDatetimeLocal(workout.started_at)}
              onBlur={(e) => {
                if (!e.target.value) return
                const iso = new Date(e.target.value).toISOString()
                if (iso !== parseUTC(workout.started_at).toISOString()) {
                  api<Workout>(`/workouts/${workout.id}`, {
                    method: 'PATCH',
                    body: { started_at: iso },
                  }).then(replaceWorkout)
                }
              }}
              className="rounded-md border border-input bg-card px-2 py-0.5 text-sm text-muted-foreground outline-none focus:ring-2 focus:ring-ring"
            />
          ) : (
            <p className="text-sm text-muted-foreground">
              {formatRelativeDate(workout.started_at)} at {formatTime(workout.started_at)}
            </p>
          )}
        </div>
        {editing ? (
          <button
            onClick={finishEditing}
            disabled={saving}
            className="touch-feedback flex items-center gap-1.5 rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-50"
          >
            <Check size={16} /> {saving ? 'Saving…' : 'Done'}
          </button>
        ) : (
          <>
            <button
              onClick={share}
              className="touch-feedback rounded-full p-2 text-muted-foreground"
              aria-label="Share workout"
            >
              <Share size={19} />
            </button>
            <button
              onClick={() => setEditing(true)}
              className="touch-feedback rounded-full p-2 text-muted-foreground"
              aria-label="Edit workout"
            >
              <Pencil size={19} />
            </button>
            <button
              onClick={() => setConfirmDelete(true)}
              className="touch-feedback rounded-full p-2 text-muted-foreground"
              aria-label="Delete workout"
            >
              <Trash2 size={19} />
            </button>
          </>
        )}
      </header>

      {!editing && (
        <>
          <button
            onClick={async () => {
              setRepeatError('')
              if (activeWorkout) {
                navigate('/workout', { viewTransition: true })
                return
              }
              try {
                await start({ workoutId: workout.id })
                navigate('/workout', { viewTransition: true })
              } catch (e) {
                setRepeatError(e instanceof Error ? e.message : 'Could not start workout')
              }
            }}
            className="touch-feedback mt-1 flex w-full items-center justify-center gap-2 rounded-xl bg-accent-soft py-3 font-semibold text-primary"
          >
            <RotateCcw size={17} />
            {activeWorkout ? 'Resume current workout' : 'Repeat this workout'}
          </button>
          {repeatError && <p className="mt-2 text-sm text-destructive">{repeatError}</p>}
        </>
      )}

      {!editing && (
        <div className="mt-3 grid grid-cols-3 gap-2">
          <div className="rounded-xl border bg-card p-3 text-center">
            <Clock size={16} className="mx-auto mb-1 text-muted-foreground" />
            <div className="tnum font-semibold">{formatDuration(workout.duration_seconds ?? 0)}</div>
          </div>
          <div className="rounded-xl border bg-card p-3 text-center">
            <Weight size={16} className="mx-auto mb-1 text-muted-foreground" />
            <div className="tnum font-semibold">{formatVolume(workout.total_volume ?? 0, unit)}</div>
          </div>
          <div className="rounded-xl border bg-card p-3 text-center">
            <Trophy size={16} className="mx-auto mb-1 text-muted-foreground" />
            <div className="tnum font-semibold">{workout.pr_count ?? 0} PRs</div>
          </div>
        </div>
      )}

      {editing ? (
        <textarea
          defaultValue={workout.notes ?? ''}
          onBlur={(e) =>
            api<Workout>(`/workouts/${workout.id}`, {
              method: 'PATCH',
              body: { notes: e.target.value },
            }).then(replaceWorkout)
          }
          placeholder="Notes"
          rows={2}
          className="mt-3 w-full rounded-xl border border-input bg-card px-3.5 py-2.5 text-sm outline-none focus:ring-2 focus:ring-ring"
        />
      ) : (
        workout.notes && (
          <p className="mt-3 rounded-xl border bg-card p-3.5 text-sm whitespace-pre-wrap text-muted-foreground">
            {workout.notes}
          </p>
        )
      )}

      <div className={cn('mt-4 grid gap-3 pb-8', !editing && 'md:grid-cols-2 md:items-start')}>
        {workout.exercises.map((we) => (
          <section key={we.id} className="animate-card-appear rounded-xl border bg-card p-4">
            <div className="flex items-center justify-between gap-2">
              {editing ? (
                <span className="font-semibold text-primary">{we.name}</span>
              ) : (
                <Link to={`/exercises/${we.exercise_id}`} className="font-semibold text-primary">
                  {we.name}
                </Link>
              )}
              {editing && (
                <button
                  onClick={() => removeExercise(we)}
                  className="touch-feedback rounded-full p-1.5 text-muted-foreground"
                  aria-label={`Remove ${we.name}`}
                >
                  <Trash2 size={16} />
                </button>
              )}
            </div>
            {editing ? (
              <>
                <div className="mt-2 grid grid-cols-[2rem_1fr_4.5rem_4rem_2.75rem] gap-2 pb-1 text-[11px] font-semibold tracking-wide text-muted-foreground uppercase">
                  <span className="text-center">Set</span>
                  <span />
                  <span className="text-center">{unit}</span>
                  <span className="text-center">Reps</span>
                  <span />
                </div>
                <div className="divide-y divide-border/60">
                  {we.sets.map((set) => (
                    <EditSetRow
                      key={set.id}
                      set={set}
                      unit={unit}
                      bodyweight={we.equipment === 'Bodyweight'}
                      onCommit={(patch) => commitSet(set.id, patch)}
                      onToggleWarmup={() => toggleWarmup(set)}
                      onDelete={() => deleteSet(we.id, set.id)}
                    />
                  ))}
                </div>
                <button
                  onClick={() => addSet(we.id)}
                  className="touch-feedback mt-2 flex w-full items-center justify-center gap-1.5 rounded-lg bg-secondary py-2 text-sm font-semibold text-secondary-foreground"
                >
                  <Plus size={16} /> Add set
                </button>
              </>
            ) : (
              <div className="mt-2 flex flex-col gap-1">
                {we.sets.map((set) => (
                  <div key={set.id} className="flex items-center gap-3 text-sm">
                    <span className="tnum w-5 text-center font-semibold text-muted-foreground">
                      {set.is_warmup ? <span className="text-warning">W</span> : set.position + 1}
                    </span>
                    <span className="tnum">
                      {formatSetWeight(set.weight, unit)} × {set.reps}
                      {set.rpe != null && (
                        <span className="text-muted-foreground"> @{set.rpe}</span>
                      )}
                    </span>
                    {set.is_pr && <Trophy size={14} className="text-record" />}
                  </div>
                ))}
              </div>
            )}
          </section>
        ))}

        {editing && (
          <button
            onClick={() => setPickerOpen(true)}
            className="touch-feedback flex w-full items-center justify-center gap-2 rounded-xl border border-dashed py-3.5 font-semibold text-primary"
          >
            <Plus size={18} /> Add exercise
          </button>
        )}
      </div>

      <ExercisePicker open={pickerOpen} onClose={() => setPickerOpen(false)} onPick={(e) => addExercise(e.id)} />

      <Sheet open={confirmDelete} onClose={() => setConfirmDelete(false)} title="Delete workout?">
        <div className="flex flex-col gap-3 pt-1">
          <p className="text-sm text-muted-foreground">
            This permanently removes the workout and its sets from your history.
          </p>
          <button
            onClick={remove}
            className="touch-feedback h-12 rounded-xl bg-destructive font-semibold text-white"
          >
            Delete workout
          </button>
        </div>
      </Sheet>
    </div>
  )
}
