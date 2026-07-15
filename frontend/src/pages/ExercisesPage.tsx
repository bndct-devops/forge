import { ChevronRight, Plus, Search } from 'lucide-react'
import { useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import ExerciseForm, { MUSCLE_GROUPS, type ExerciseFields } from '../components/ExerciseForm'
import Sheet from '../components/Sheet'
import Skeleton from '../components/Skeleton'
import { api } from '../lib/api'
import type { Exercise } from '../lib/types'
import { cn } from '../lib/utils'

export default function ExercisesPage() {
  const navigate = useNavigate()
  const [exercises, setExercises] = useState<Exercise[]>([])
  const [query, setQuery] = useState('')
  const [group, setGroup] = useState<string | null>(null)
  const [creating, setCreating] = useState(false)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  useEffect(() => {
    api<Exercise[]>('/exercises')
      .then(setExercises)
      .catch(() => {})
      .finally(() => setLoading(false))
  }, [])

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase()
    return exercises.filter(
      (e) => (!group || e.muscle_group === group) && (!q || e.name.toLowerCase().includes(q)),
    )
  }, [exercises, query, group])

  const createExercise = async (fields: ExerciseFields) => {
    setError('')
    try {
      const created = await api<Exercise>('/exercises', { method: 'POST', body: fields })
      setCreating(false)
      navigate(`/exercises/${created.id}`)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to create exercise')
    }
  }

  return (
    <div className="safe-top px-4 md:max-w-2xl">
      <header className="flex items-baseline justify-between pt-6 pb-4">
        <h1 className="text-3xl">Exercises</h1>
        <button
          onClick={() => setCreating(true)}
          className="touch-feedback flex items-center gap-1 rounded-lg px-2 py-1 text-sm font-semibold text-primary"
        >
          <Plus size={16} /> New
        </button>
      </header>

      <div className="relative">
        <Search size={18} className="absolute top-1/2 left-3 -translate-y-1/2 text-muted-foreground" />
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search exercises"
          className="h-11 w-full rounded-lg border border-input bg-card pr-3 pl-10 text-base outline-none focus:ring-2 focus:ring-ring"
        />
      </div>
      <div className="scrollbar-none -mx-1 mt-2 flex gap-1.5 overflow-x-auto px-1 pb-1">
        {MUSCLE_GROUPS.map((g) => (
          <button
            key={g}
            onClick={() => setGroup(group === g ? null : g)}
            className={cn(
              'touch-feedback shrink-0 rounded-full px-3 py-1.5 text-sm font-medium',
              group === g ? 'bg-primary text-primary-foreground' : 'bg-secondary text-secondary-foreground',
            )}
          >
            {g}
          </button>
        ))}
      </div>

      {loading && (
        <div className="mt-3 flex flex-col gap-2">
          {Array.from({ length: 8 }, (_, i) => (
            <Skeleton key={i} className="h-12" />
          ))}
        </div>
      )}
      <ul className="mt-2 divide-y divide-border">
        {!loading && filtered.map((e) => (
          <li key={e.id}>
            <button
              onClick={() => navigate(`/exercises/${e.id}`, { viewTransition: true })}
              className="touch-feedback flex w-full items-center justify-between px-1 py-3 text-left"
            >
              <span>
                <span className="block font-medium">{e.name}</span>
                <span className="block text-sm text-muted-foreground">
                  {e.muscle_group} · {e.equipment}
                  {e.grip && ` · ${e.grip} grip`}
                  {e.is_custom && ' · Custom'}
                </span>
              </span>
              <ChevronRight size={18} className="shrink-0 text-muted-foreground" />
            </button>
          </li>
        ))}
        {!loading && filtered.length === 0 && (
          <li className="py-8 text-center text-sm text-muted-foreground">No exercises found</li>
        )}
      </ul>

      <Sheet open={creating} onClose={() => setCreating(false)} title="New exercise">
        <ExerciseForm submitLabel="Create" onSubmit={createExercise} error={error} />
      </Sheet>
    </div>
  )
}
