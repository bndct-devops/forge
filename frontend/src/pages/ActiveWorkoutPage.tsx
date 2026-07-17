import { ArrowLeftRight, Calculator, Check, ChevronDown, CloudOff, Flag, Flame, GripVertical, Link2, MoreHorizontal, Plus, StickyNote, Timer, Trash2, TrendingDown, TrendingUp, Unlink2, X } from 'lucide-react'
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
import { formatClock, formatRelativeDate, formatSetWeight, formatVolume, parseUTC, restLabel } from '../lib/format'
import { useOutboxSize } from '../lib/outbox'
import { restTimer } from '../lib/timer'
import { moveItem, useDragReorder } from '../lib/useDragReorder'
import type { FinishResult, SetEntry, WorkoutExercise } from '../lib/types'
import { cn } from '../lib/utils'

const REST_OPTIONS = [0, 30, 45, 60, 90, 120, 150, 180, 240, 300]
const BARBELL_EQUIPMENT = new Set(['Barbell', 'EZ Bar', 'Trap Bar', 'Smith Machine', 'Plate-Loaded'])

/** Best plate-calc prefill: heaviest filled set, else heaviest previous ghost. */
function plateWeightFor(we: WorkoutExercise): number | null {
  const filled = we.sets.map((s) => s.weight ?? 0).filter((w) => w > 0)
  if (filled.length) return Math.max(...filled)
  const previous = we.previous_sets.map((s) => s.weight ?? 0).filter((w) => w > 0)
  return previous.length ? Math.max(...previous) : null
}

/** Working weight the warm-up ramp builds toward: what's typed today, else
 *  the progression suggestion, else last session's top weight. */
function warmupTarget(we: WorkoutExercise): number | null {
  if (we.equipment === 'Bodyweight') return null
  const filled = we.sets.map((s) => s.weight ?? 0).filter((w) => w > 0)
  if (filled.length) return Math.max(...filled)
  if (we.suggested_weight != null && we.suggested_weight > 0) return we.suggested_weight
  const previous = we.previous_sets.map((s) => s.weight ?? 0).filter((w) => w > 0)
  return previous.length ? Math.max(...previous) : null
}

/** ~40/60/80% ramp, rounded to the plate step, deduped, always below target. */
function warmupRamp(target: number, unit: string): { weight: number; reps: number }[] {
  const step = unit === 'lb' ? 5 : 2.5
  const ramp = [
    { pct: 0.4, reps: 10 },
    { pct: 0.6, reps: 6 },
    { pct: 0.8, reps: 3 },
  ].map(({ pct, reps }) => ({
    weight: Math.max(step, Math.round((target * pct) / step) * step),
    reps,
  }))
  return ramp.filter(
    (r, i, all) => r.weight < target && all.findIndex((x) => x.weight === r.weight) === i,
  )
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
    swapExercise,
    addSet,
    updateSet,
    deleteSet,
    reorderExercises,
    finish,
    discard,
  } = useWorkout()
  const [pickerOpen, setPickerOpen] = useState(false)
  const [menuExercise, setMenuExercise] = useState<WorkoutExercise | null>(null)
  const [swapTarget, setSwapTarget] = useState<WorkoutExercise | null>(null)
  const [markerSet, setMarkerSet] = useState<SetEntry | null>(null)
  const [plateExercise, setPlateExercise] = useState<WorkoutExercise | null>(null)
  const [peekExercise, setPeekExercise] = useState<WorkoutExercise | null>(null)
  const [peekSessions, setPeekSessions] = useState<
    { workout_id: number; name: string; date: string; sets: { weight: number | null; reps: number | null; is_pr: boolean }[] }[] | null
  >(null)
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

  const openPeek = (we: WorkoutExercise) => {
    setPeekExercise(we)
    setPeekSessions(null)
    api<typeof peekSessions>(`/exercises/${we.exercise_id}/recent?limit=3`)
      .then(setPeekSessions)
      .catch(() => setPeekSessions([]))
  }

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
    <div className="safe-x mx-auto flex h-full max-w-lg flex-col md:max-w-2xl">
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
                    <button
                      onClick={() => openPeek(we)}
                      className="touch-feedback min-w-0 flex-1 truncate text-left text-base font-semibold text-primary"
                    >
                      {we.name}
                      {we.superset && (
                        <span className="ml-2 rounded bg-accent-soft px-1.5 py-0.5 align-middle text-[10px] font-semibold tracking-wide text-primary uppercase">
                          Superset {we.superset}
                        </span>
                      )}
                    </button>
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

                  {we.suggested_weight != null &&
                    (we.suggestion_kind === 'deload' ? (
                      <p className="mt-1 flex items-center gap-1.5 text-xs font-medium text-warning">
                        <TrendingDown size={13} className="shrink-0" />
                        Deload: {we.suggested_weight} {user?.unit ?? 'kg'} suggested after 3 stalled
                        sessions
                      </p>
                    ) : (
                      <p className="mt-1 flex items-center gap-1.5 text-xs font-medium text-primary">
                        <TrendingUp size={13} className="shrink-0" />
                        Progression: {we.suggested_weight} {user?.unit ?? 'kg'} suggested
                        {we.rep_min != null && we.rep_max != null && ` · target ${we.rep_min}–${we.rep_max} reps`}
                      </p>
                    ))}
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
                        progression={
                          we.suggested_weight != null || we.rep_min != null
                            ? { weight: we.suggested_weight, repMin: we.rep_min, repMax: we.rep_max }
                            : undefined
                        }
                        rpeEnabled={rpeEnabled}
                        onRpe={(rpe) => updateSet(set.id, { rpe })}
                        onComplete={(weight, reps) => completeSet(we, set.id, weight, reps)}
                        onUncomplete={() => updateSet(set.id, { is_completed: false })}
                        onMarker={() => setMarkerSet(set)}
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

      <ExercisePicker
        open={swapTarget != null}
        onClose={() => setSwapTarget(null)}
        onPick={async (exercise) => {
          const target = swapTarget
          setSwapTarget(null)
          if (!target || exercise.id === target.exercise_id) return
          try {
            await swapExercise(target.id, exercise.id)
          } catch {
            toast('Could not swap the exercise')
          }
        }}
      />

      <Sheet
        open={markerSet != null}
        onClose={() => setMarkerSet(null)}
        title={markerSet ? `Set ${markerSet.position + 1}` : undefined}
      >
        {markerSet && (
          <div className="flex flex-col gap-1 pt-1 pb-2">
            {(
              [
                { label: 'Working set', hint: 'Counts toward PRs and volume', warmup: false, type: null },
                { label: 'Warm-up', hint: 'Excluded from PRs and volume', warmup: true, type: null },
                { label: 'Drop set', hint: 'Reduced weight straight after a working set', warmup: false, type: 'drop' as const },
                { label: 'To failure', hint: 'Taken to technical failure', warmup: false, type: 'failure' as const },
              ] as const
            ).map((opt) => {
              const active =
                markerSet.is_warmup === opt.warmup && (markerSet.set_type ?? null) === opt.type
              return (
                <button
                  key={opt.label}
                  onClick={async () => {
                    setMarkerSet(null)
                    await updateSet(markerSet.id, { is_warmup: opt.warmup, set_type: opt.type })
                  }}
                  className={cn(
                    'touch-feedback flex items-center justify-between rounded-lg px-3 py-3 text-left hover:bg-secondary',
                    active && 'bg-accent-soft',
                  )}
                >
                  <span>
                    <span className={cn('font-medium', active && 'text-primary')}>{opt.label}</span>
                    <span className="block text-xs text-muted-foreground">{opt.hint}</span>
                  </span>
                  {active && <Check size={18} className="text-primary" />}
                </button>
              )
            })}
          </div>
        )}
      </Sheet>

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
            <button
              onClick={() => {
                setSwapTarget(menuExercise)
                setMenuExercise(null)
              }}
              className="touch-feedback flex items-center gap-3 rounded-lg px-3 py-3 text-left font-medium hover:bg-secondary"
            >
              <ArrowLeftRight size={18} /> Swap exercise
            </button>
            {(() => {
              const target = warmupTarget(menuExercise)
              const ramp = target != null ? warmupRamp(target, user?.unit ?? 'kg') : []
              if (ramp.length === 0) return null
              return (
                <button
                  onClick={async () => {
                    const we = menuExercise
                    setMenuExercise(null)
                    try {
                      let pos = 0
                      for (const r of ramp) {
                        await api(`/workouts/${workout!.id}/exercises/${we.id}/sets`, {
                          method: 'POST',
                          body: { position: pos++, weight: r.weight, reps: r.reps, is_warmup: true },
                        })
                      }
                      await refresh()
                    } catch {
                      toast('Could not add warm-up sets')
                    }
                  }}
                  className="touch-feedback flex items-center gap-3 rounded-lg px-3 py-3 text-left font-medium hover:bg-secondary"
                >
                  <Flame size={18} />
                  <span>
                    Add warm-up sets
                    <span className="block text-xs font-normal text-muted-foreground">
                      {ramp.map((r) => `${formatSetWeight(r.weight, user?.unit ?? 'kg')} × ${r.reps}`).join(' · ')}
                    </span>
                  </span>
                </button>
              )
            })()}
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

      <Sheet
        open={peekExercise != null}
        onClose={() => setPeekExercise(null)}
        title={peekExercise ? `Recent — ${peekExercise.name}` : undefined}
      >
        {peekSessions == null ? (
          <p className="py-6 text-center text-sm text-muted-foreground">Loading…</p>
        ) : peekSessions.length === 0 ? (
          <p className="py-6 text-center text-sm text-muted-foreground">
            No previous sessions of this exercise yet.
          </p>
        ) : (
          <div className="flex flex-col gap-3 pt-1 pb-2">
            {peekSessions.map((session) => (
              <div key={session.workout_id} className="rounded-xl border bg-card p-3.5">
                <div className="flex items-baseline justify-between text-sm">
                  <span className="font-medium">{session.name}</span>
                  <span className="text-muted-foreground">{formatRelativeDate(session.date)}</span>
                </div>
                <div className="tnum mt-1.5 flex flex-wrap gap-x-3 gap-y-0.5 text-sm text-muted-foreground">
                  {session.sets.map((st, i) => (
                    <span key={i}>
                      {formatSetWeight(st.weight, user?.unit ?? 'kg')}×{st.reps}
                    </span>
                  ))}
                </div>
              </div>
            ))}
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
