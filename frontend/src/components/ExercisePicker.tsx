import { Plus, Search } from 'lucide-react'
import { useEffect, useMemo, useState } from 'react'
import { api } from '../lib/api'
import type { Exercise } from '../lib/types'
import { cn } from '../lib/utils'
import ExerciseForm, { MUSCLE_GROUPS, type ExerciseFields } from './ExerciseForm'
import Sheet from './Sheet'

interface ExercisePickerProps {
  open: boolean
  onClose: () => void
  onPick: (exercise: Exercise) => void
}

export default function ExercisePicker({ open, onClose, onPick }: ExercisePickerProps) {
  const [exercises, setExercises] = useState<Exercise[]>([])
  const [query, setQuery] = useState('')
  const [group, setGroup] = useState<string | null>(null)
  const [creating, setCreating] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    if (open) {
      api<Exercise[]>('/exercises').then(setExercises).catch(() => {})
      setQuery('')
      setGroup(null)
      setCreating(false)
      setError('')
    }
  }, [open])

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase()
    return exercises.filter(
      (e) =>
        (!group || e.muscle_group === group) &&
        (!q || e.name.toLowerCase().includes(q)),
    )
  }, [exercises, query, group])

  const createExercise = async (fields: ExerciseFields) => {
    setError('')
    try {
      const created = await api<Exercise>('/exercises', { method: 'POST', body: fields })
      onPick(created)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to create exercise')
    }
  }

  return (
    <Sheet open={open} onClose={onClose} title={creating ? 'New exercise' : 'Add exercise'} full>
      {creating ? (
        <ExerciseForm
          submitLabel="Create"
          onSubmit={createExercise}
          error={error}
          secondaryAction={
            <button
              onClick={() => setCreating(false)}
              className="touch-feedback h-11 flex-1 rounded-lg bg-secondary font-semibold text-secondary-foreground"
            >
              Back
            </button>
          }
        />
      ) : (
        <>
          <div className="sticky top-0 z-10 -mx-5 bg-popover px-5 pb-2">
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
                    group === g
                      ? 'bg-primary text-primary-foreground'
                      : 'bg-secondary text-secondary-foreground',
                  )}
                >
                  {g}
                </button>
              ))}
            </div>
          </div>
          <button
            onClick={() => setCreating(true)}
            className="touch-feedback mt-1 flex w-full items-center gap-2 rounded-lg px-2 py-2.5 text-left font-medium text-primary"
          >
            <Plus size={18} /> Create custom exercise
          </button>
          <ul className="divide-y divide-border">
            {filtered.map((e) => (
              <li key={e.id}>
                <button
                  onClick={() => onPick(e)}
                  className="touch-feedback flex w-full items-center justify-between px-2 py-3 text-left"
                >
                  <span>
                    <span className="block font-medium">{e.name}</span>
                    <span className="block text-sm text-muted-foreground">
                      {e.muscle_group} · {e.equipment}
                      {e.is_custom && ' · Custom'}
                    </span>
                  </span>
                </button>
              </li>
            ))}
            {filtered.length === 0 && (
              <li className="py-8 text-center text-sm text-muted-foreground">No exercises found</li>
            )}
          </ul>
        </>
      )}
    </Sheet>
  )
}
