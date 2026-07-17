import { ChevronDown, ChevronRight, Plus, Search } from 'lucide-react'
import { useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import ExerciseForm, { MUSCLE_GROUPS, type ExerciseFields } from '../components/ExerciseForm'
import { variantLabel } from '../components/ExercisePicker'
import Sheet from '../components/Sheet'
import Skeleton from '../components/Skeleton'
import { api } from '../lib/api'
import { fetchExercises, getCachedExercises } from '../lib/exerciseCache'
import type { Exercise } from '../lib/types'
import { cn } from '../lib/utils'

export default function ExercisesPage() {
  const navigate = useNavigate()
  const [exercises, setExercises] = useState<Exercise[]>(() => getCachedExercises() ?? [])
  const [query, setQuery] = useState('')
  const [group, setGroup] = useState<string | null>(null)
  const [creating, setCreating] = useState(false)
  const [loading, setLoading] = useState(() => getCachedExercises() == null)
  const [error, setError] = useState('')

  useEffect(() => {
    fetchExercises()
      .then(setExercises)
      .catch(() => {})
      .finally(() => setLoading(false))
  }, [])

  const [expanded, setExpanded] = useState<Set<number>>(new Set())
  const searching = query.trim().length > 0

  const families = useMemo(() => {
    const q = query.trim().toLowerCase()
    const byId = new Map(exercises.map((e) => [e.id, e]))
    const matches = (e: Exercise) =>
      (!group || e.muscle_group === group) && (!q || e.name.toLowerCase().includes(q))
    const map = new Map<number, Exercise[]>()
    for (const e of exercises) {
      if (!matches(e)) continue
      const rootId = e.variant_of_id ?? e.id
      map.set(rootId, [...(map.get(rootId) ?? []), e])
    }
    return [...map.entries()]
      .map(([baseId, members]) => {
        const base = byId.get(baseId) ?? null
        members.sort((a, b) => {
          if (a.id === baseId) return -1
          if (b.id === baseId) return 1
          const baseEq = byId.get(baseId)?.equipment
          const ae = a.equipment !== baseEq ? a.equipment : ''
          const be = b.equipment !== baseEq ? b.equipment : ''
          return ae.localeCompare(be) || a.name.localeCompare(b.name)
        })
        return { baseId, base, members }
      })
      .sort((a, b) =>
        (a.base?.name ?? a.members[0].name).localeCompare(b.base?.name ?? b.members[0].name),
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
          enterKeyHint="search"
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
        {!loading &&
          families.map((family) => {
            const head = family.base ?? family.members[0]
            const variants = family.members.filter((m) => m.id !== head.id)
            const isOpen = searching || expanded.has(family.baseId)
            return (
              <li key={family.baseId} className="cv-auto">
                <div className="flex items-center">
                  <button
                    onClick={() => navigate(`/exercises/${head.id}`, { viewTransition: true })}
                    className="touch-feedback flex min-w-0 flex-1 items-center justify-between py-3 pl-1 text-left"
                  >
                    <span className="min-w-0">
                      <span className="block truncate font-medium">{head.name}</span>
                      <span className="block text-sm text-muted-foreground">
                        {head.muscle_group} · {head.equipment}
                        {head.attachment && ` · ${head.attachment}`}
                        {head.grip && ` · ${head.grip}`}
                        {head.is_custom && ' · Custom'}
                      </span>
                    </span>
                  </button>
                  {variants.length > 0 ? (
                    <button
                      onClick={() =>
                        setExpanded((prev) => {
                          const next = new Set(prev)
                          if (next.has(family.baseId)) next.delete(family.baseId)
                          else next.add(family.baseId)
                          return next
                        })
                      }
                      className="touch-feedback flex shrink-0 items-center gap-1 rounded-lg px-2 py-2 text-xs font-medium text-muted-foreground"
                      aria-label={`Variants of ${head.name}`}
                    >
                      <span className="tnum">{variants.length}</span>
                      <ChevronDown
                        size={16}
                        className={cn('transition-transform', isOpen && 'rotate-180')}
                      />
                    </button>
                  ) : (
                    <ChevronRight size={18} className="mr-1 shrink-0 text-muted-foreground" />
                  )}
                </div>
                {isOpen && variants.length > 0 && (
                  <ul className="mb-1 divide-y divide-border/40 border-t border-border/40">
                    {variants.map((v) => (
                      <li key={v.id}>
                        {(() => {
                          const label = family.base ? variantLabel(v.name, family.base.name) : v.name
                          const chip =
                            family.base &&
                            v.equipment !== family.base.equipment &&
                            !label.toLowerCase().includes(v.equipment.toLowerCase())
                              ? v.equipment
                              : null
                          const attachment =
                            v.attachment && !label.toLowerCase().includes(v.attachment.toLowerCase())
                              ? v.attachment
                              : null
                          return (
                        <button
                          onClick={() => navigate(`/exercises/${v.id}`, { viewTransition: true })}
                          className="touch-feedback flex w-full items-center gap-2 py-2.5 pr-2 pl-6 text-left"
                        >
                          <span className="min-w-0 truncate font-medium">{label}</span>
                          {chip && (
                            <span className="shrink-0 rounded-full bg-secondary px-2 py-0.5 text-[10px] font-semibold text-muted-foreground">
                              {chip}
                            </span>
                          )}
                          {attachment && (
                            <span className="shrink-0 rounded-full bg-secondary px-2 py-0.5 text-[10px] font-semibold text-muted-foreground">
                              {attachment}
                            </span>
                          )}
                          {v.is_custom && (
                            <span className="shrink-0 rounded-full bg-accent-soft px-2 py-0.5 text-[10px] font-semibold text-primary">
                              Custom
                            </span>
                          )}
                        </button>
                          )
                        })()}
                      </li>
                    ))}
                  </ul>
                )}
              </li>
            )
          })}
        {!loading && families.length === 0 && (
          <li className="py-8 text-center text-sm text-muted-foreground">No exercises found</li>
        )}
      </ul>

      <Sheet open={creating} onClose={() => setCreating(false)} title="New exercise">
        <ExerciseForm submitLabel="Create" onSubmit={createExercise} error={error} />
      </Sheet>
    </div>
  )
}
