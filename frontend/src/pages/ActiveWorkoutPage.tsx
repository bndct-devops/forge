import { Calculator, ChevronDown, CloudOff, Flag, GripVertical, Link2, MoreHorizontal, Plus, StickyNote, Timer, Trash2, Unlink2, X } from 'lucide-react'
import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import ConfirmSheet from '../components/ConfirmSheet'
import ExercisePicker from '../components/ExercisePicker'
import FinishScreen from '../components/FinishScreen'
import PlateCalculator from '../components/PlateCalculator'
import RestTimerBar from '../components/RestTimerBar'
import SetRow, { SET_GRID, SET_GRID_RPE } from '../components/SetRow'
import Sheet from '../components/Sheet'
import { useAuth } from '../contexts/AuthContext'
import { useWorkout } from '../contexts/WorkoutContext'
import { api } from '../lib/api'
import { isRpeEnabled } from '../lib/prefs'
import { toast } from '../lib/toast'
import { formatClock, formatVolume, parseUTC, restLabel } from '../lib/format'
import { useOutboxSize } from '../lib/outbox'
import { restTimer } from '../lib/timer'
import { moveItem, useDragReorder } from '../lib/useDragReorder'
import type { FinishResult, WorkoutExercise } from '../lib/types'

const REST_OPTIONS = [0, 30, 45, 60, 90, 120, 150, 180, 240, 300]
const BARBELL_EQUIPMENT = new Set(['Barbell', 'EZ Bar', 'Trap Bar'])

/** Best plate-calc prefill: heaviest filled set, else heaviest previous ghost. */
function plateWeightFor(we: WorkoutExercise): number | null {
  const filled = we.sets.map((s) => s.weight ?? 0).filter((w) => w > 0)
  if (filled.length) return Math.max(...filled)
  const previous = we.previous_sets.map((s) => s.weight ?? 0).filter((w) => w > 0)
  return previous.length ? Math.max(...previous) : null
}

function NameInput({ name, onCommit }: { name: string; onCommit: (name: string) => void }) {
  const [value, setValue] = useState(name)
  useEffect(() => setValue(name), [name])
  return (
    <input
      value={value}
      onChange={(e) => setValue(e.target.value)}
      onBlur={() => {
        const trimmed = value.trim()
        if (trimmed && trimmed !== name) onCommit(trimmed)
        else setValue(name)
      }}
      className="w-full truncate bg-transparent text-lg font-semibold outline-none"
      style={{ fontFamily: "'Bricolage Grotesque', 'Onest', sans-serif" }}
    />
  )
}

function ElapsedClock({ startedAt }: { startedAt: string }) {
  const [, setTick] = useState(0)
  useEffect(() => {
    const t = setInterval(() => setTick((v) => v + 1), 1000)
    return () => clearInterval(t)
  }, [])
  const elapsed = (Date.now() - parseUTC(startedAt).getTime()) / 1000
  return <span className="tnum text-sm font-medium text-muted-foreground">{formatClock(elapsed)}</span>
}

export default function ActiveWorkoutPage() {
  const navigate = useNavigate()
  const { user } = useAuth()
  const {
    workout,
    loading,
    refresh,
    rename,
    updateNotes,
    addExercise,
    removeExercise,
    setExerciseRest,
    setSupersetLink,
    addSet,
    updateSet,
    deleteSet,
    reorderExercises,
    finish,
    discard,
  } = useWorkout()
  const [pickerOpen, setPickerOpen] = useState(false)
  const [menuExercise, setMenuExercise] = useState<WorkoutExercise | null>(null)
  const [plateExercise, setPlateExercise] = useState<WorkoutExercise | null>(null)
  const [workoutMenu, setWorkoutMenu] = useState(false)
  const [confirmFinish, setConfirmFinish] = useState(false)
  const [confirmDiscard, setConfirmDiscard] = useState(false)
  const [summary, setSummary] = useState<FinishResult | null>(null)
  const [error, setError] = useState('')
  const pendingSync = useOutboxSize()
  const rpeEnabled = isRpeEnabled()
  const exerciseCount = workout?.exercises.length ?? 0
  const { handleProps, itemProps } = useDragReorder(exerciseCount, (from, to) => {
    if (!workout) return
    reorderExercises(moveItem(workout.exercises, from, to).map((we) => we.id))
  })

  useEffect(() => {
    if (!loading && !workout && !summary) navigate('/', { replace: true })
  }, [loading, workout, summary, navigate])

  if (!workout && !summary) return null

  if (summary) {
    return (
      <div className="mx-auto h-full max-w-lg md:max-w-2xl">
        <FinishScreen
          summary={summary}
          unit={user?.unit ?? 'kg'}
          onDone={() => navigate('/history', { replace: true })}
        />
      </div>
    )
  }

  const completedCount =
    workout?.exercises.reduce((n, we) => n + we.sets.filter((s) => s.is_completed).length, 0) ?? 0
  const incompleteCount =
    workout?.exercises.reduce((n, we) => n + we.sets.filter((s) => !s.is_completed).length, 0) ?? 0
  const liveVolume =
    workout?.exercises.reduce(
      (v, we) =>
        v +
        we.sets.reduce(
          (sv, s) =>
            s.is_completed && !s.is_warmup && s.reps != null ? sv + (s.weight ?? 0) * s.reps : sv,
          0,
        ),
      0,
    ) ?? 0

  const completeSet = async (we: WorkoutExercise, setId: number, weight: number, reps: number) => {
    await updateSet(setId, { weight, reps, is_completed: true })
    // Inside a superset, rest comes after the group's last exercise
    if (we.superset && !we.superset_last) return
    restTimer.start(we.rest_seconds ?? user?.default_rest_seconds ?? 120)
  }

  const doFinish = async () => {
    setError('')
    try {
      const result = await finish()
      restTimer.skip()
      setConfirmFinish(false)
      setSummary(result)
    } catch (e) {
      setConfirmFinish(false)
      setError(e instanceof Error ? e.message : 'Could not finish workout')
    }
  }

  const doDiscard = async () => {
    await discard()
    restTimer.skip()
    navigate('/', { replace: true })
  }

  return (
    <div className="mx-auto flex h-full max-w-lg flex-col md:max-w-2xl">
      {workout && (
        <>
          <header className="safe-top shrink-0 border-b bg-background">
            <div className="flex items-center gap-2 px-4 py-3">
              <button
                onClick={() => navigate('/')}
                className="touch-feedback -ml-2 rounded-full p-2 text-muted-foreground"
                aria-label="Minimize workout"
              >
                <ChevronDown size={22} />
              </button>
              <div className="min-w-0 flex-1">
                <NameInput name={workout.name} onCommit={rename} />
                <span className="flex items-center gap-2">
                  <ElapsedClock startedAt={workout.started_at} />
                  {completedCount > 0 && (
                    <span className="tnum text-sm text-muted-foreground">
                      · {completedCount} {completedCount === 1 ? 'set' : 'sets'} ·{' '}
                      {formatVolume(liveVolume, user?.unit ?? 'kg')}
                    </span>
                  )}
                  {pendingSync > 0 && (
                    <span className="flex items-center gap-1 rounded-full bg-warning/15 px-2 py-0.5 text-xs font-medium text-warning">
                      <CloudOff size={12} /> {pendingSync} to sync
                    </span>
                  )}
                </span>
              </div>
              <button
                onClick={() => setWorkoutMenu(true)}
                className="touch-feedback rounded-full p-2 text-muted-foreground"
                aria-label="Workout options"
              >
                <MoreHorizontal size={20} />
              </button>
              <button
                onClick={() => setConfirmFinish(true)}
                className="touch-feedback rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground"
              >
                Finish
              </button>
            </div>
          </header>

          <main className="overscroll-contain flex-1 overflow-y-auto px-4 pt-4 pb-8">
            {error && <p className="mb-3 text-sm text-destructive">{error}</p>}
            <div className="flex flex-col gap-4">
              {workout.exercises.map((we, i) => (
                <section
                  key={we.id}
                  {...itemProps(i)}
                  className={
                    we.superset
                      ? 'animate-card-appear rounded-xl border border-l-2 border-l-primary bg-card p-3.5'
                      : 'animate-card-appear rounded-xl border bg-card p-3.5'
                  }
                >
                  <div className="flex items-center justify-between gap-2">
                    <button
                      {...handleProps(i)}
                      aria-label={`Reorder ${we.name}`}
                      className="-m-1 shrink-0 rounded p-1 text-muted-foreground/50"
                    >
                      <GripVertical size={16} />
                    </button>
                    <h3 className="min-w-0 flex-1 truncate text-base font-semibold text-primary">
                      {we.name}
                      {we.superset && (
                        <span className="ml-2 rounded bg-accent-soft px-1.5 py-0.5 align-middle text-[10px] font-semibold tracking-wide text-primary uppercase">
                          Superset {we.superset}
                        </span>
                      )}
                    </h3>
                    <div className="flex items-center gap-1">
                      <span className="flex items-center gap-1 rounded-full bg-secondary px-2 py-1 text-xs font-medium text-muted-foreground">
                        <Timer size={12} />
                        {restLabel(we.rest_seconds ?? user?.default_rest_seconds ?? 120)}
                      </span>
                      <button
                        onClick={() => setMenuExercise(we)}
                        className="touch-feedback rounded-full p-1.5 text-muted-foreground"
                        aria-label="Exercise options"
                      >
                        <MoreHorizontal size={18} />
                      </button>
                    </div>
                  </div>

                  {we.note && (
                    <p className="mt-1 flex items-start gap-1.5 text-xs text-muted-foreground">
                      <StickyNote size={13} className="mt-0.5 shrink-0" />
                      <span className="whitespace-pre-wrap">{we.note}</span>
                    </p>
                  )}

                  <div
                    className={`mt-2 grid ${rpeEnabled ? SET_GRID_RPE : SET_GRID} gap-2 pb-1 text-[11px] font-semibold tracking-wide text-muted-foreground uppercase`}
                  >
                    <span className="text-center">Set</span>
                    <span className="text-center">Previous</span>
                    <span className="text-center">{user?.unit ?? 'kg'}</span>
                    <span className="text-center">Reps</span>
                    {rpeEnabled && <span className="text-center">RPE</span>}
                    <span />
                  </div>

                  <div className="divide-y divide-border/60">
                    {we.sets.map((set, i) => (
                      <SetRow
                        key={set.id}
                        set={set}
                        previous={we.previous_sets[set.position]}
                        suggested={we.sets
                          .slice(0, i)
                          .reverse()
                          .find((s) => s.weight != null && s.reps != null)}
                        unit={user?.unit ?? 'kg'}
                        bodyweight={we.equipment === 'Bodyweight'}
                        rpeEnabled={rpeEnabled}
                        onRpe={(rpe) => updateSet(set.id, { rpe })}
                        onComplete={(weight, reps) => completeSet(we, set.id, weight, reps)}
                        onUncomplete={() => updateSet(set.id, { is_completed: false })}
                        onToggleWarmup={() => updateSet(set.id, { is_warmup: !set.is_warmup })}
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
                </section>
              ))}
            </div>

            <button
              onClick={() => setPickerOpen(true)}
              className="touch-feedback mt-4 flex w-full items-center justify-center gap-2 rounded-xl border border-dashed py-3.5 font-semibold text-primary"
            >
              <Plus size={18} /> Add exercise
            </button>

            <button
              onClick={() => setConfirmDiscard(true)}
              className="touch-feedback mx-auto mt-6 flex items-center gap-2 rounded-lg px-4 py-2 text-sm font-semibold text-destructive"
            >
              <X size={16} /> Cancel workout
            </button>
          </main>

          <div className="safe-bottom shrink-0">
            <RestTimerBar />
          </div>
        </>
      )}

      <ExercisePicker
        open={pickerOpen}
        onClose={() => setPickerOpen(false)}
        onPick={async (exercise) => {
          setPickerOpen(false)
          await addExercise(exercise.id)
        }}
      />

      <Sheet open={menuExercise != null} onClose={() => setMenuExercise(null)} title={menuExercise?.name}>
        {menuExercise && (
          <div className="flex flex-col gap-3 pt-1">
            <label className="flex flex-col gap-1.5 text-sm font-medium">
              Exercise note
              <textarea
                defaultValue={menuExercise.note}
                onBlur={(e) =>
                  api(`/exercises/${menuExercise.exercise_id}/note`, {
                    method: 'PUT',
                    body: { text: e.target.value },
                  })
                    .then(() => refresh())
                    .catch(() => toast('Could not save the note'))
                }
                placeholder="Seat height, cues, grip width — pinned to this exercise everywhere"
                rows={2}
                className="rounded-lg border border-input bg-card px-3 py-2 text-base outline-none focus:ring-2 focus:ring-ring"
              />
            </label>
            {workout && menuExercise.position < workout.exercises.length - 1 && (
              <button
                onClick={async () => {
                  await setSupersetLink(menuExercise.id, !menuExercise.superset_with_next)
                  setMenuExercise(null)
                }}
                className="touch-feedback flex items-center gap-3 rounded-lg px-3 py-3 text-left font-medium hover:bg-secondary"
              >
                {menuExercise.superset_with_next ? <Unlink2 size={18} /> : <Link2 size={18} />}
                {menuExercise.superset_with_next
                  ? 'Remove superset with next'
                  : 'Superset with next exercise'}
              </button>
            )}
            {BARBELL_EQUIPMENT.has(menuExercise.equipment) && (
              <button
                onClick={() => {
                  setPlateExercise(menuExercise)
                  setMenuExercise(null)
                }}
                className="touch-feedback flex items-center gap-3 rounded-lg px-3 py-3 text-left font-medium hover:bg-secondary"
              >
                <Calculator size={18} /> Plate calculator
              </button>
            )}
            <label className="flex items-center justify-between gap-2 text-sm font-medium">
              Rest timer for this exercise
              <select
                value={menuExercise.rest_seconds ?? 'default'}
                onChange={async (e) => {
                  const value = e.target.value === 'default' ? null : Number(e.target.value)
                  await setExerciseRest(menuExercise.id, value)
                  setMenuExercise(null)
                }}
                className="h-10 rounded-lg border border-input bg-card px-2 text-sm outline-none"
              >
                <option value="default">
                  Default ({restLabel(user?.default_rest_seconds ?? 120)})
                </option>
                {REST_OPTIONS.map((s) => (
                  <option key={s} value={s}>
                    {restLabel(s)}
                  </option>
                ))}
              </select>
            </label>
            <button
              onClick={async () => {
                await removeExercise(menuExercise.id)
                setMenuExercise(null)
              }}
              className="touch-feedback flex items-center gap-3 rounded-lg px-3 py-3 text-left font-medium text-destructive hover:bg-secondary"
            >
              <Trash2 size={18} /> Remove from workout
            </button>
          </div>
        )}
      </Sheet>

      <PlateCalculator
        key={plateExercise?.id ?? 'closed'}
        open={plateExercise != null}
        onClose={() => setPlateExercise(null)}
        initialWeight={plateExercise ? plateWeightFor(plateExercise) : null}
        unit={user?.unit ?? 'kg'}
      />

      <Sheet open={workoutMenu} onClose={() => setWorkoutMenu(false)} title="Workout options">
        <div className="flex flex-col gap-3 pt-1">
          <label className="flex flex-col gap-1.5 text-sm font-medium">
            Notes
            <textarea
              defaultValue={workout?.notes ?? ''}
              onBlur={(e) => updateNotes(e.target.value)}
              placeholder="How did it go?"
              rows={3}
              className="rounded-lg border border-input bg-card px-3 py-2 text-base outline-none focus:ring-2 focus:ring-ring"
            />
          </label>
          <button
            onClick={() => {
              setWorkoutMenu(false)
              setConfirmDiscard(true)
            }}
            className="touch-feedback flex items-center gap-3 rounded-lg px-3 py-3 text-left font-medium text-destructive hover:bg-secondary"
          >
            <Trash2 size={18} /> Discard workout
          </button>
        </div>
      </Sheet>

      <ConfirmSheet
        open={confirmDiscard}
        onClose={() => setConfirmDiscard(false)}
        title="Discard workout?"
        message={
          completedCount > 0
            ? `This throws away ${completedCount} completed ${completedCount === 1 ? 'set' : 'sets'} — it won't appear in your history.`
            : 'This workout will be thrown away.'
        }
        actionLabel="Discard workout"
        destructive
        onConfirm={() => {
          setConfirmDiscard(false)
          doDiscard()
        }}
      />

      <Sheet open={confirmFinish} onClose={() => setConfirmFinish(false)} title="Finish workout?">
        <div className="flex flex-col gap-3 pt-1">
          <p className="text-sm text-muted-foreground">
            {completedCount === 0
              ? 'No completed sets yet — check off at least one set, or discard the workout.'
              : `${completedCount} completed ${completedCount === 1 ? 'set' : 'sets'}${
                  incompleteCount > 0
                    ? ` — ${incompleteCount} incomplete ${incompleteCount === 1 ? 'set' : 'sets'} will be discarded`
                    : ''
                }.`}
          </p>
          <button
            onClick={doFinish}
            disabled={completedCount === 0}
            className="touch-feedback flex h-12 items-center justify-center gap-2 rounded-xl bg-primary font-semibold text-primary-foreground disabled:opacity-50"
          >
            <Flag size={18} /> Finish workout
          </button>
          {completedCount === 0 && (
            <button
              onClick={() => {
                setConfirmFinish(false)
                doDiscard()
              }}
              className="touch-feedback flex h-12 items-center justify-center gap-2 rounded-xl bg-secondary font-semibold text-destructive"
            >
              <Trash2 size={18} /> Discard workout
            </button>
          )}
        </div>
      </Sheet>

    </div>
  )
}
