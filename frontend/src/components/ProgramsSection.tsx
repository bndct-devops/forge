import { CalendarRange, ChevronRight, Plus, Trash2, X } from 'lucide-react'
import { useCallback, useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'
import { useWorkout } from '../contexts/WorkoutContext'
import { api } from '../lib/api'
import { toast } from '../lib/toast'
import type { Exercise } from '../lib/types'
import ConfirmSheet from './ConfirmSheet'
import ExercisePicker from './ExercisePicker'
import Sheet from './Sheet'

interface ProgramSet {
  pct: number
  weight: number
  reps: number
  amrap: boolean
}

interface Program {
  id: number
  name: string
  scheme: string
  scheme_name: string
  rounding: number
  current_week: number
  cycle_length: number
  cycle_number: number
  // id is absent on lifts added in the edit sheet and not yet saved
  lifts: { id?: number; exercise_id: number; name: string; training_max: number; increment: number }[]
  next: { exercise_name: string; week: number; sets: ProgramSet[] } | null
}

interface SchemeInfo {
  name: string
  description: string
  weeks: { pct: number; reps: number; amrap: boolean }[][]
}

interface DraftLift {
  exercise: Exercise
  training_max: number
  increment: number
}

interface RecordRow {
  exercise_id: number
  best_1rm: { value: number } | null
}

function roundTo(v: number, step: number) {
  return Math.round(v / step) * step
}

export default function ProgramsSection() {
  const navigate = useNavigate()
  const { user } = useAuth()
  const { refresh } = useWorkout()
  const unit = user?.unit ?? 'kg'
  const [programs, setPrograms] = useState<Program[]>([])
  const [schemes, setSchemes] = useState<Record<string, SchemeInfo>>({})
  const [creating, setCreating] = useState(false)
  const [editTarget, setEditTarget] = useState<Program | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<Program | null>(null)
  const [busy, setBusy] = useState(false)

  // Create-sheet draft state
  const [draftName, setDraftName] = useState('')
  const [draftScheme, setDraftScheme] = useState('531')
  const [draftLifts, setDraftLifts] = useState<DraftLift[]>([])
  const [pickerOpen, setPickerOpen] = useState(false)
  const [records, setRecords] = useState<RecordRow[]>([])

  const load = useCallback(() => {
    api<Program[]>('/programs').then(setPrograms).catch(() => {})
  }, [])

  useEffect(() => {
    load()
    api<Record<string, SchemeInfo>>('/programs/schemes').then(setSchemes).catch(() => {})
  }, [load])

  const openCreate = () => {
    setDraftName('')
    setDraftScheme('531')
    setDraftLifts([])
    setCreating(true)
    api<RecordRow[]>('/stats/records').then(setRecords).catch(() => {})
  }

  const openEdit = (p: Program) => {
    setEditTarget(structuredClone(p))
    api<RecordRow[]>('/stats/records').then(setRecords).catch(() => {})
  }

  // Conventional training max: 90% of the best estimated 1RM
  const suggestLift = (exercise: Exercise) => {
    const record = records.find((r) => r.exercise_id === exercise.id)
    const tm = record?.best_1rm ? roundTo(record.best_1rm.value * 0.9, 2.5) : 40
    const increment = exercise.muscle_group === 'Legs' ? 5 : 2.5
    return { training_max: Math.max(20, tm), increment }
  }

  const addLift = (exercise: Exercise) => {
    setPickerOpen(false)
    if (editTarget) {
      if (editTarget.lifts.some((l) => l.exercise_id === exercise.id)) return
      setEditTarget({
        ...editTarget,
        lifts: [...editTarget.lifts, { exercise_id: exercise.id, name: exercise.name, ...suggestLift(exercise) }],
      })
      return
    }
    if (draftLifts.some((l) => l.exercise.id === exercise.id)) return
    setDraftLifts((ls) => [...ls, { exercise, ...suggestLift(exercise) }])
  }

  const createProgram = async () => {
    if (draftLifts.length === 0) return
    setBusy(true)
    try {
      await api('/programs', {
        method: 'POST',
        body: {
          name: draftName.trim() || schemes[draftScheme]?.name || 'Program',
          scheme: draftScheme,
          lifts: draftLifts.map((l) => ({
            exercise_id: l.exercise.id,
            training_max: l.training_max,
            increment: l.increment,
          })),
        },
      })
      setCreating(false)
      load()
    } catch (e) {
      toast(e instanceof Error ? e.message : 'Could not create the program')
    } finally {
      setBusy(false)
    }
  }

  const saveEdit = async () => {
    if (!editTarget) return
    setBusy(true)
    try {
      await api(`/programs/${editTarget.id}`, {
        method: 'PATCH',
        body: {
          name: editTarget.name,
          lifts: editTarget.lifts.map((l) => ({
            id: l.id,
            exercise_id: l.exercise_id,
            training_max: l.training_max,
            increment: l.increment,
          })),
        },
      })
      setEditTarget(null)
      load()
    } catch (e) {
      toast(e instanceof Error ? e.message : 'Could not save')
    } finally {
      setBusy(false)
    }
  }

  const startSession = async (p: Program) => {
    setBusy(true)
    try {
      await api(`/programs/${p.id}/start-workout`, { method: 'POST' })
      await refresh()
      navigate('/workout', { viewTransition: true })
    } catch (e) {
      toast(e instanceof Error ? e.message : 'Could not start the session')
      setBusy(false)
    }
  }

  const removeProgram = async (p: Program) => {
    await api(`/programs/${p.id}`, { method: 'DELETE' })
    setDeleteTarget(null)
    load()
  }

  const setsSummary = (sets: ProgramSet[]) =>
    sets.map((s) => `${s.weight}×${s.reps}${s.amrap ? '+' : ''}`).join(' · ')

  return (
    <>
      <div className="mt-8 mb-3 flex items-center justify-between">
        <h2 className="text-xl">Programs</h2>
        <button
          onClick={openCreate}
          className="touch-feedback flex items-center gap-1 rounded-lg px-2 py-1 text-sm font-semibold text-primary"
        >
          <Plus size={16} /> New
        </button>
      </div>

      {programs.length === 0 ? (
        <p className="text-sm text-muted-foreground">
          Percentage-based training cycles — 5/3/1 or a linear block — with training maxes
          that advance themselves. Weights come prefilled every session.
        </p>
      ) : (
        <div className="flex flex-col gap-3 md:grid md:grid-cols-2">
          {programs.map((p) => (
            <div key={p.id} className="rounded-xl border bg-card p-4">
              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0">
                  <div className="truncate font-semibold">{p.name}</div>
                  <div className="text-xs text-muted-foreground">
                    {p.scheme_name} · Cycle {p.cycle_number} · Week {p.current_week}/{p.cycle_length}
                  </div>
                </div>
                <button
                  onClick={() => openEdit(p)}
                  className="touch-feedback shrink-0 rounded-lg px-2 py-1 text-xs font-medium text-muted-foreground"
                >
                  Edit
                </button>
              </div>
              {p.next && (
                <div className="mt-3 rounded-lg bg-secondary/60 px-3 py-2.5">
                  <div className="text-xs text-muted-foreground">
                    Next · {p.next.exercise_name}
                  </div>
                  <div className="tnum mt-0.5 text-sm font-medium">
                    {setsSummary(p.next.sets)} {unit}
                  </div>
                </div>
              )}
              <button
                onClick={() => startSession(p)}
                disabled={busy}
                className="touch-feedback mt-3 flex w-full items-center justify-center gap-1.5 rounded-lg bg-accent-soft py-2.5 text-sm font-semibold text-primary"
              >
                Start session <ChevronRight size={15} />
              </button>
            </div>
          ))}
        </div>
      )}

      {/* Create sheet */}
      <Sheet open={creating} onClose={() => setCreating(false)} title="New program">
        <div className="flex flex-col gap-4 pb-2">
          <input
            value={draftName}
            onChange={(e) => setDraftName(e.target.value)}
            placeholder={schemes[draftScheme]?.name ?? 'Program name'}
            className="w-full rounded-xl border bg-card px-3.5 py-2.5 text-[15px] outline-none focus:ring-2 focus:ring-ring"
          />
          <div className="flex flex-col gap-2">
            {Object.entries(schemes).map(([key, s]) => (
              <button
                key={key}
                onClick={() => setDraftScheme(key)}
                className={`touch-feedback rounded-xl border p-3 text-left ${
                  draftScheme === key ? 'border-primary bg-accent-soft' : 'bg-card'
                }`}
              >
                <div className="flex items-center gap-2 text-sm font-semibold">
                  <CalendarRange size={15} className="text-primary" />
                  {s.name}
                </div>
                <p className="mt-1 text-xs leading-relaxed text-muted-foreground">{s.description}</p>
              </button>
            ))}
          </div>

          <div>
            <div className="mb-2 flex items-center justify-between">
              <span className="text-sm font-semibold">Lifts</span>
              <button
                onClick={() => setPickerOpen(true)}
                className="touch-feedback flex items-center gap-1 rounded-lg px-2 py-1 text-sm font-semibold text-primary"
              >
                <Plus size={15} /> Add lift
              </button>
            </div>
            {draftLifts.length === 0 && (
              <p className="text-xs text-muted-foreground">
                Training maxes prefill at 90% of your best estimated 1RM where history exists.
              </p>
            )}
            <div className="flex flex-col gap-2">
              {draftLifts.map((l, i) => (
                <div key={l.exercise.id} className="flex items-center gap-2 rounded-xl border bg-card px-3 py-2">
                  <span className="min-w-0 flex-1 truncate text-sm font-medium">{l.exercise.name}</span>
                  <label className="flex items-center gap-1 text-xs text-muted-foreground">
                    TM
                    <input
                      type="number"
                      inputMode="decimal"
                      value={l.training_max}
                      onChange={(e) =>
                        setDraftLifts((ls) =>
                          ls.map((x, j) => (j === i ? { ...x, training_max: Number(e.target.value) } : x)),
                        )
                      }
                      className="tnum w-16 rounded-lg border bg-background px-2 py-1 text-right text-sm"
                    />
                  </label>
                  <label className="flex items-center gap-1 text-xs text-muted-foreground">
                    <Plus size={11} />
                    <input
                      type="number"
                      inputMode="decimal"
                      value={l.increment}
                      onChange={(e) =>
                        setDraftLifts((ls) =>
                          ls.map((x, j) => (j === i ? { ...x, increment: Number(e.target.value) } : x)),
                        )
                      }
                      className="tnum w-12 rounded-lg border bg-background px-2 py-1 text-right text-sm"
                    />
                  </label>
                  <button
                    onClick={() => setDraftLifts((ls) => ls.filter((_, j) => j !== i))}
                    className="touch-feedback shrink-0 p-1 text-muted-foreground"
                    aria-label={`Remove ${l.exercise.name}`}
                  >
                    <X size={15} />
                  </button>
                </div>
              ))}
            </div>
          </div>

          <button
            onClick={createProgram}
            disabled={busy || draftLifts.length === 0}
            className="touch-feedback w-full rounded-xl bg-primary py-3 font-semibold text-primary-foreground disabled:opacity-40"
          >
            Create program
          </button>
        </div>
      </Sheet>

      {/* Edit sheet */}
      <Sheet open={editTarget != null} onClose={() => setEditTarget(null)} title="Edit program">
        {editTarget && (
          <div className="flex flex-col gap-4 pb-2">
            <input
              value={editTarget.name}
              onChange={(e) => setEditTarget({ ...editTarget, name: e.target.value })}
              className="w-full rounded-xl border bg-card px-3.5 py-2.5 text-[15px] outline-none focus:ring-2 focus:ring-ring"
            />
            <div className="flex items-center justify-between">
              <span className="text-sm font-semibold">Lifts</span>
              <button
                onClick={() => setPickerOpen(true)}
                className="touch-feedback flex items-center gap-1 rounded-lg px-2 py-1 text-sm font-semibold text-primary"
              >
                <Plus size={15} /> Add lift
              </button>
            </div>
            <div className="flex flex-col gap-2">
              {editTarget.lifts.map((l, i) => (
                <div key={l.id ?? `new-${l.exercise_id}`} className="flex items-center gap-2 rounded-xl border bg-card px-3 py-2">
                  <span className="min-w-0 flex-1 truncate text-sm font-medium">{l.name}</span>
                  <label className="flex items-center gap-1 text-xs text-muted-foreground">
                    TM
                    <input
                      type="number"
                      inputMode="decimal"
                      value={l.training_max}
                      onChange={(e) =>
                        setEditTarget({
                          ...editTarget,
                          lifts: editTarget.lifts.map((x, j) =>
                            j === i ? { ...x, training_max: Number(e.target.value) } : x,
                          ),
                        })
                      }
                      className="tnum w-16 rounded-lg border bg-background px-2 py-1 text-right text-sm"
                    />
                  </label>
                  <label className="flex items-center gap-1 text-xs text-muted-foreground">
                    <Plus size={11} />
                    <input
                      type="number"
                      inputMode="decimal"
                      value={l.increment}
                      onChange={(e) =>
                        setEditTarget({
                          ...editTarget,
                          lifts: editTarget.lifts.map((x, j) =>
                            j === i ? { ...x, increment: Number(e.target.value) } : x,
                          ),
                        })
                      }
                      className="tnum w-12 rounded-lg border bg-background px-2 py-1 text-right text-sm"
                    />
                  </label>
                  {editTarget.lifts.length > 1 && (
                    <button
                      onClick={() =>
                        setEditTarget({
                          ...editTarget,
                          lifts: editTarget.lifts.filter((_, j) => j !== i),
                        })
                      }
                      className="touch-feedback shrink-0 p-1 text-muted-foreground"
                      aria-label={`Remove ${l.name}`}
                    >
                      <X size={15} />
                    </button>
                  )}
                </div>
              ))}
            </div>
            <div className="flex gap-2">
              <button
                onClick={() => {
                  setDeleteTarget(editTarget)
                  setEditTarget(null)
                }}
                className="touch-feedback flex items-center justify-center gap-1.5 rounded-xl border px-4 py-3 text-sm font-semibold text-destructive"
              >
                <Trash2 size={15} /> Delete
              </button>
              <button
                onClick={saveEdit}
                disabled={busy}
                className="touch-feedback flex-1 rounded-xl bg-primary py-3 font-semibold text-primary-foreground"
              >
                Save
              </button>
            </div>
          </div>
        )}
      </Sheet>

      <ExercisePicker open={pickerOpen} onClose={() => setPickerOpen(false)} onPick={addLift} />

      <ConfirmSheet
        open={deleteTarget != null}
        title={`Delete ${deleteTarget?.name ?? 'program'}?`}
        message="Logged workouts stay; only the program and its state are removed."
        actionLabel="Delete"
        destructive
        onConfirm={() => deleteTarget && removeProgram(deleteTarget)}
        onClose={() => setDeleteTarget(null)}
      />
    </>
  )
}
