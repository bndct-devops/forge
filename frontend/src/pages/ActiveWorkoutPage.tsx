import { ChevronDown, Flag, MoreHorizontal, Plus, Timer, Trash2, Trophy, X } from 'lucide-react'
import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import ExercisePicker from '../components/ExercisePicker'
import RestTimerBar from '../components/RestTimerBar'
import SetRow from '../components/SetRow'
import Sheet from '../components/Sheet'
import { useAuth } from '../contexts/AuthContext'
import { useWorkout } from '../contexts/WorkoutContext'
import { formatClock, formatVolume, formatDuration, parseUTC, restLabel } from '../lib/format'
import { restTimer } from '../lib/timer'
import type { FinishResult, WorkoutExercise } from '../lib/types'

const REST_OPTIONS = [0, 30, 45, 60, 90, 120, 150, 180, 240, 300]

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
    rename,
    updateNotes,
    addExercise,
    removeExercise,
    setExerciseRest,
    addSet,
    updateSet,
    deleteSet,
    finish,
    discard,
  } = useWorkout()
  const [pickerOpen, setPickerOpen] = useState(false)
  const [menuExercise, setMenuExercise] = useState<WorkoutExercise | null>(null)
  const [workoutMenu, setWorkoutMenu] = useState(false)
  const [confirmFinish, setConfirmFinish] = useState(false)
  const [summary, setSummary] = useState<FinishResult | null>(null)
  const [error, setError] = useState('')

  useEffect(() => {
    if (!loading && !workout && !summary) navigate('/', { replace: true })
  }, [loading, workout, summary, navigate])

  if (!workout && !summary) return null

  const completedCount =
    workout?.exercises.reduce((n, we) => n + we.sets.filter((s) => s.is_completed).length, 0) ?? 0
  const incompleteCount =
    workout?.exercises.reduce((n, we) => n + we.sets.filter((s) => !s.is_completed).length, 0) ?? 0

  const completeSet = async (we: WorkoutExercise, setId: number, weight: number, reps: number) => {
    await updateSet(setId, { weight, reps, is_completed: true })
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
    <div className="mx-auto flex min-h-dvh max-w-lg flex-col md:max-w-2xl">
      {workout && (
        <>
          <header className="safe-top sticky top-0 z-30 border-b bg-background/90 backdrop-blur-lg">
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
                <ElapsedClock startedAt={workout.started_at} />
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

          <main className="flex-1 px-4 pt-4 pb-44">
            {error && <p className="mb-3 text-sm text-destructive">{error}</p>}
            <div className="flex flex-col gap-4">
              {workout.exercises.map((we) => (
                <section key={we.id} className="animate-card-appear rounded-xl border bg-card p-3.5">
                  <div className="flex items-center justify-between gap-2">
                    <h3 className="min-w-0 truncate text-base font-semibold text-primary">
                      {we.name}
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

                  <div className="mt-2 grid grid-cols-[2rem_1fr_4.5rem_4rem_2.75rem] gap-2 pb-1 text-[11px] font-semibold tracking-wide text-muted-foreground uppercase">
                    <span className="text-center">Set</span>
                    <span className="text-center">Previous</span>
                    <span className="text-center">{user?.unit ?? 'kg'}</span>
                    <span className="text-center">Reps</span>
                    <span />
                  </div>

                  <div className="divide-y divide-border/60">
                    {we.sets.map((set) => (
                      <SetRow
                        key={set.id}
                        set={set}
                        previous={we.previous_sets[set.position]}
                        unit={user?.unit ?? 'kg'}
                        bodyweight={we.equipment === 'Bodyweight'}
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
              onClick={doDiscard}
              className="touch-feedback mx-auto mt-6 flex items-center gap-2 rounded-lg px-4 py-2 text-sm font-semibold text-destructive"
            >
              <X size={16} /> Cancel workout
            </button>
          </main>

          <div className="safe-bottom fixed inset-x-0 bottom-0 z-40">
            <div className="mx-auto max-w-lg px-3 pb-3 md:max-w-2xl">
              <RestTimerBar />
            </div>
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
              doDiscard()
            }}
            className="touch-feedback flex items-center gap-3 rounded-lg px-3 py-3 text-left font-medium text-destructive hover:bg-secondary"
          >
            <Trash2 size={18} /> Discard workout
          </button>
        </div>
      </Sheet>

      <Sheet open={confirmFinish} onClose={() => setConfirmFinish(false)} title="Finish workout?">
        <div className="flex flex-col gap-3 pt-1">
          <p className="text-sm text-muted-foreground">
            {completedCount} completed {completedCount === 1 ? 'set' : 'sets'}
            {incompleteCount > 0 && ` — ${incompleteCount} incomplete ${incompleteCount === 1 ? 'set' : 'sets'} will be discarded`}
            .
          </p>
          <button
            onClick={doFinish}
            className="touch-feedback flex h-12 items-center justify-center gap-2 rounded-xl bg-primary font-semibold text-primary-foreground"
          >
            <Flag size={18} /> Finish workout
          </button>
        </div>
      </Sheet>

      {/* Leave `summary` set while navigating away — clearing it first lets the
          no-workout redirect effect win over these navigations (router v7
          navigations are transitions and commit after plain state updates). */}
      <Sheet
        open={summary != null}
        onClose={() => navigate('/', { replace: true })}
        title="Workout complete"
      >
        {summary && (
          <div className="flex flex-col gap-4 pt-1">
            <div className="grid grid-cols-3 gap-2">
              <div className="rounded-xl bg-secondary p-3 text-center">
                <div className="tnum text-lg font-semibold">{formatDuration(summary.duration_seconds)}</div>
                <div className="text-xs text-muted-foreground">Duration</div>
              </div>
              <div className="rounded-xl bg-secondary p-3 text-center">
                <div className="tnum text-lg font-semibold">
                  {formatVolume(summary.total_volume, user?.unit ?? 'kg')}
                </div>
                <div className="text-xs text-muted-foreground">Volume</div>
              </div>
              <div className="rounded-xl bg-secondary p-3 text-center">
                <div className="tnum text-lg font-semibold">{summary.total_sets}</div>
                <div className="text-xs text-muted-foreground">Sets</div>
              </div>
            </div>
            {summary.prs.length > 0 && (
              <div>
                <h3 className="mb-2 text-base">Personal records</h3>
                <div className="flex flex-col gap-1.5">
                  {summary.prs.map((pr, i) => (
                    <div key={i} className="flex items-center gap-2.5 rounded-lg bg-secondary px-3 py-2.5 text-sm">
                      <Trophy size={16} className="shrink-0 text-record" />
                      <span className="min-w-0 flex-1 truncate font-medium">{pr.exercise_name}</span>
                      <span className="tnum text-muted-foreground">
                        {pr.kind === 'weight' && `${pr.value} ${user?.unit ?? 'kg'} × ${pr.reps}`}
                        {pr.kind === '1rm' && `est. 1RM ${pr.value} ${user?.unit ?? 'kg'}`}
                        {pr.kind === 'reps' && `${pr.value} reps`}
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            )}
            <button
              onClick={() => navigate('/history', { replace: true })}
              className="touch-feedback h-12 rounded-xl bg-primary font-semibold text-primary-foreground"
            >
              Done
            </button>
          </div>
        )}
      </Sheet>
    </div>
  )
}
