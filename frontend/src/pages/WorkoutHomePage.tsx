import { Copy, LibraryBig, MoreVertical, Pencil, Play, Plus, Trash2 } from 'lucide-react'
import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import ConfirmSheet from '../components/ConfirmSheet'
import EmptyState from '../components/EmptyState'
import Sheet from '../components/Sheet'
import { CardListSkeleton } from '../components/Skeleton'
import { useWorkout } from '../contexts/WorkoutContext'
import { api } from '../lib/api'
import type { Plan, Routine } from '../lib/types'
import { formatRelativeDate, restLabel } from '../lib/format'

function PlansSheet({
  open,
  onClose,
  onAdopted,
}: {
  open: boolean
  onClose: () => void
  onAdopted: (routines: Routine[]) => void
}) {
  const [plans, setPlans] = useState<Plan[]>([])
  const [adopting, setAdopting] = useState<string | null>(null)

  useEffect(() => {
    if (open && plans.length === 0) {
      api<Plan[]>('/plans').then(setPlans).catch(() => {})
    }
  }, [open, plans.length])

  const adopt = async (plan: Plan) => {
    setAdopting(plan.key)
    try {
      const created = await api<Routine[]>(`/plans/${plan.key}/adopt`, { method: 'POST' })
      onAdopted(created)
      onClose()
    } finally {
      setAdopting(null)
    }
  }

  return (
    <Sheet open={open} onClose={onClose} title="Training plans" full>
      <p className="mb-3 text-sm text-muted-foreground">
        Proven starting points — adding a plan copies its templates into yours, ready to edit.
      </p>
      <div className="flex flex-col gap-3 pb-2">
        {plans.map((plan) => (
          <div key={plan.key} className="rounded-xl border bg-card p-4">
            <h3 className="text-lg">{plan.name}</h3>
            <p className="mt-1 text-sm text-muted-foreground">{plan.description}</p>
            <div className="mt-2.5 flex flex-col gap-1">
              {plan.routines.map((r) => (
                <p key={r.name} className="text-sm">
                  <span className="font-medium">{r.name}</span>{' '}
                  <span className="text-muted-foreground">
                    — {r.exercises.map((e) => `${e.set_count}×${e.name}`).join(', ')}
                  </span>
                </p>
              ))}
            </div>
            <button
              onClick={() => adopt(plan)}
              disabled={adopting != null}
              className="touch-feedback mt-3 w-full rounded-lg bg-accent-soft py-2.5 font-semibold text-primary disabled:opacity-50"
            >
              {adopting === plan.key
                ? 'Adding…'
                : `Add ${plan.routines.length} template${plan.routines.length > 1 ? 's' : ''}`}
            </button>
          </div>
        ))}
      </div>
    </Sheet>
  )
}

export default function WorkoutHomePage() {
  const navigate = useNavigate()
  const { workout, start } = useWorkout()
  const [routines, setRoutines] = useState<Routine[]>([])
  const [menuRoutine, setMenuRoutine] = useState<Routine | null>(null)
  const [deleteRoutineTarget, setDeleteRoutineTarget] = useState<Routine | null>(null)
  const [plansOpen, setPlansOpen] = useState(false)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  useEffect(() => {
    api<Routine[]>('/routines')
      .then(setRoutines)
      .catch(() => {})
      .finally(() => setLoading(false))
  }, [])

  const begin = async (routineId?: number) => {
    setError('')
    if (workout) {
      navigate('/workout', { viewTransition: true })
      return
    }
    try {
      // Empty workouts get named by time of day, Strong-style
      const hour = new Date().getHours()
      const autoName =
        hour < 5 || hour >= 21
          ? 'Night Workout'
          : hour < 12
            ? 'Morning Workout'
            : hour < 17
              ? 'Afternoon Workout'
              : 'Evening Workout'
      await start(routineId != null ? { routineId } : { name: autoName })
      navigate('/workout', { viewTransition: true })
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not start workout')
    }
  }

  const deleteRoutine = async (routine: Routine) => {
    await api(`/routines/${routine.id}`, { method: 'DELETE' })
    setRoutines((rs) => rs.filter((r) => r.id !== routine.id))
    setMenuRoutine(null)
  }

  const duplicateRoutine = async (routine: Routine) => {
    const copy = await api<Routine>('/routines', {
      method: 'POST',
      body: {
        name: `${routine.name} (copy)`,
        exercises: routine.exercises.map((e) => ({
          exercise_id: e.exercise_id,
          set_count: e.set_count,
          rest_seconds: e.rest_seconds,
        })),
      },
    })
    setRoutines((rs) => [...rs, copy])
    setMenuRoutine(null)
  }

  return (
    <div className="safe-top px-4">
      <header className="pt-6 pb-4">
        <h1 className="text-3xl">Workout</h1>
      </header>

      <button
        onClick={() => begin()}
        className="touch-feedback flex h-13 w-full items-center justify-center gap-2 rounded-xl bg-primary py-3.5 text-base font-semibold text-primary-foreground md:max-w-sm"
      >
        <Play size={19} className="fill-current" />
        {workout ? 'Resume workout' : 'Start empty workout'}
      </button>
      {error && <p className="mt-2 text-sm text-destructive">{error}</p>}

      <div className="mt-8 mb-3 flex items-center justify-between">
        <h2 className="text-xl">Templates</h2>
        <div className="flex items-center gap-1">
          <button
            onClick={() => setPlansOpen(true)}
            className="touch-feedback flex items-center gap-1 rounded-lg px-2 py-1 text-sm font-semibold text-primary"
          >
            <LibraryBig size={16} /> Plans
          </button>
          <button
            onClick={() => navigate('/routines/new')}
            className="touch-feedback flex items-center gap-1 rounded-lg px-2 py-1 text-sm font-semibold text-primary"
          >
            <Plus size={16} /> New
          </button>
        </div>
      </div>

      {loading ? (
        <CardListSkeleton count={2} className="md:grid-cols-2 xl:grid-cols-3" />
      ) : routines.length === 0 ? (
        <EmptyState title="No templates yet">
          Create one, or add a proven plan from the Plans library above.
        </EmptyState>
      ) : (
        <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
          {routines.map((routine, i) => (
            <div
              key={routine.id}
              className="animate-card-appear flex flex-col rounded-xl border bg-card p-4"
              style={{ animationDelay: `${i * 40}ms` }}
            >
              <div className="flex items-start justify-between gap-2">
                <h3 className="text-lg">{routine.name}</h3>
                <button
                  onClick={() => setMenuRoutine(routine)}
                  className="touch-feedback -mt-1 -mr-1 rounded-full p-2 text-muted-foreground"
                  aria-label="Template options"
                >
                  <MoreVertical size={18} />
                </button>
              </div>
              <p className="mt-1 line-clamp-2 flex-1 text-sm text-muted-foreground">
                {routine.exercises.map((e) => `${e.set_count} × ${e.name}`).join(', ') ||
                  'No exercises'}
              </p>
              {routine.last_performed && (
                <p className="mt-1.5 text-xs text-muted-foreground/70">
                  Last performed {formatRelativeDate(routine.last_performed)}
                </p>
              )}
              <button
                onClick={() => begin(routine.id)}
                className="touch-feedback mt-3 w-full rounded-lg bg-accent-soft py-2.5 font-semibold text-primary"
              >
                {workout ? 'Resume workout' : 'Start workout'}
              </button>
            </div>
          ))}
        </div>
      )}

      <ConfirmSheet
        open={deleteRoutineTarget != null}
        onClose={() => setDeleteRoutineTarget(null)}
        title={`Delete “${deleteRoutineTarget?.name}”?`}
        message="The template goes away — workouts you logged with it stay in your history."
        actionLabel="Delete template"
        destructive
        onConfirm={() => {
          if (deleteRoutineTarget) deleteRoutine(deleteRoutineTarget)
          setDeleteRoutineTarget(null)
        }}
      />

      <PlansSheet
        open={plansOpen}
        onClose={() => setPlansOpen(false)}
        onAdopted={(created) => setRoutines((rs) => [...rs, ...created])}
      />

      <Sheet open={menuRoutine != null} onClose={() => setMenuRoutine(null)} title={menuRoutine?.name}>
        {menuRoutine && (
          <div className="flex flex-col gap-1 pt-1">
            <div className="mb-2 text-sm text-muted-foreground">
              {menuRoutine.exercises.map((e) => (
                <div key={e.position} className="flex justify-between py-0.5">
                  <span>
                    {e.set_count} × {e.name}
                  </span>
                  <span>{e.rest_seconds != null ? `rest ${restLabel(e.rest_seconds)}` : ''}</span>
                </div>
              ))}
            </div>
            <button
              onClick={() => navigate(`/routines/${menuRoutine.id}`)}
              className="touch-feedback flex items-center gap-3 rounded-lg px-3 py-3 text-left font-medium hover:bg-secondary"
            >
              <Pencil size={18} /> Edit template
            </button>
            <button
              onClick={() => duplicateRoutine(menuRoutine)}
              className="touch-feedback flex items-center gap-3 rounded-lg px-3 py-3 text-left font-medium hover:bg-secondary"
            >
              <Copy size={18} /> Duplicate template
            </button>
            <button
              onClick={() => {
                setDeleteRoutineTarget(menuRoutine)
                setMenuRoutine(null)
              }}
              className="touch-feedback flex items-center gap-3 rounded-lg px-3 py-3 text-left font-medium text-destructive hover:bg-secondary"
            >
              <Trash2 size={18} /> Delete template
            </button>
          </div>
        )}
      </Sheet>
    </div>
  )
}
