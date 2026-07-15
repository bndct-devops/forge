import { ChevronRight, Search } from 'lucide-react'
import { useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { api } from '../lib/api'
import type { Exercise } from '../lib/types'
import { cn } from '../lib/utils'

const MUSCLE_GROUPS = ['Chest', 'Back', 'Shoulders', 'Arms', 'Legs', 'Core', 'Full Body']

export default function ExercisesPage() {
  const navigate = useNavigate()
  const [exercises, setExercises] = useState<Exercise[]>([])
  const [query, setQuery] = useState('')
  const [group, setGroup] = useState<string | null>(null)

  useEffect(() => {
    api<Exercise[]>('/exercises').then(setExercises).catch(() => {})
  }, [])

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase()
    return exercises.filter(
      (e) => (!group || e.muscle_group === group) && (!q || e.name.toLowerCase().includes(q)),
    )
  }, [exercises, query, group])

  return (
    <div className="safe-top px-4">
      <header className="pt-6 pb-4">
        <h1 className="text-3xl">Exercises</h1>
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

      <ul className="mt-2 divide-y divide-border">
        {filtered.map((e) => (
          <li key={e.id}>
            <button
              onClick={() => navigate(`/exercises/${e.id}`)}
              className="touch-feedback flex w-full items-center justify-between px-1 py-3 text-left"
            >
              <span>
                <span className="block font-medium">{e.name}</span>
                <span className="block text-sm text-muted-foreground">
                  {e.muscle_group} · {e.equipment}
                  {e.is_custom && ' · Custom'}
                </span>
              </span>
              <ChevronRight size={18} className="shrink-0 text-muted-foreground" />
            </button>
          </li>
        ))}
        {filtered.length === 0 && (
          <li className="py-8 text-center text-sm text-muted-foreground">No exercises found</li>
        )}
      </ul>
    </div>
  )
}
