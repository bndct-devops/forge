import { Copy, MoreVertical, Pencil, Play, Plus, Trash2 } from 'lucide-react'
import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import EmptyState from '../components/EmptyState'
import Sheet from '../components/Sheet'
import { useWorkout } from '../contexts/WorkoutContext'
import { api } from '../lib/api'
import type { Routine } from '../lib/types'
import { restLabel } from '../lib/format'

export default function WorkoutHomePage() {
  const navigate = useNavigate()
  const { workout, start } = useWorkout()
  const [routines, setRoutines] = useState<Routine[]>([])
  const [menuRoutine, setMenuRoutine] = useState<Routine | null>(null)
  const [error, setError] = useState('')

  useEffect(() => {
    api<Routine[]>('/routines').then(setRoutines).catch(() => {})
  }, [])

  const begin = async (routineId?: number) => {
    setError('')
    if (workout) {
      navigate('/workout')
      return
    }
    try {
      await start(routineId != null ? { routineId } : undefined)
      navigate('/workout')
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
        <button
          onClick={() => navigate('/routines/new')}
          className="touch-feedback flex items-center gap-1 rounded-lg px-2 py-1 text-sm font-semibold text-primary"
        >
          <Plus size={16} /> New
        </button>
      </div>

      {routines.length === 0 ? (
        <EmptyState title="No templates yet">
          Create one to start workouts with a single tap.
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
              onClick={() => deleteRoutine(menuRoutine)}
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
