import { ChevronLeft, Search, Trophy } from 'lucide-react'
import { useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import Skeleton from '../components/Skeleton'
import { useAuth } from '../contexts/AuthContext'
import { api } from '../lib/api'
import { useCachedState } from '../lib/dataCache'
import { formatRelativeDate } from '../lib/format'

interface RecordRow {
  exercise_id: number
  name: string
  muscle_group: string
  best_weight: { weight: number; reps: number; date: string } | null
  best_1rm: { value: number; date: string } | null
  best_reps: { reps: number; date: string } | null
  sessions: number
}

export default function RecordsPage() {
  const navigate = useNavigate()
  const { user } = useAuth()
  const [records, setRecords] = useCachedState<RecordRow[] | null>('records', null)
  const [query, setQuery] = useState('')
  const unit = user?.unit ?? 'kg'

  useEffect(() => {
    api<RecordRow[]>('/stats/records').then(setRecords).catch(() => {})
  }, [])

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase()
    return (records ?? []).filter((r) => !q || r.name.toLowerCase().includes(q))
  }, [records, query])

  return (
    <div className="safe-top px-4 md:max-w-2xl">
      <header className="flex items-center gap-2 pt-4 pb-4">
        <button
          onClick={() => navigate(-1)}
          className="touch-feedback -ml-2 rounded-full p-2 text-muted-foreground"
          aria-label="Back"
        >
          <ChevronLeft size={24} />
        </button>
        <h1 className="text-2xl">Records</h1>
      </header>

      <div className="relative mb-3">
        <Search size={18} className="absolute top-1/2 left-3 -translate-y-1/2 text-muted-foreground" />
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search records"
          enterKeyHint="search"
          className="h-11 w-full rounded-lg border border-input bg-card pr-3 pl-10 text-base outline-none focus:ring-2 focus:ring-ring"
        />
      </div>

      {records == null ? (
        <div className="flex flex-col gap-2">
          {Array.from({ length: 6 }, (_, i) => (
            <Skeleton key={i} className="h-16" />
          ))}
        </div>
      ) : filtered.length === 0 ? (
        <p className="rounded-xl border border-dashed p-8 text-center text-sm text-muted-foreground">
          {query ? 'No matching records.' : 'Records appear once you finish workouts.'}
        </p>
      ) : (
        <ul className="divide-y divide-border overflow-hidden rounded-xl border bg-card">
          {filtered.map((r) => (
            <li key={r.exercise_id}>
              <button
                onClick={() => navigate(`/exercises/${r.exercise_id}`, { viewTransition: true })}
                className="touch-feedback w-full px-4 py-3 text-left"
              >
                <div className="flex items-baseline justify-between gap-2">
                  <span className="min-w-0 truncate font-medium">{r.name}</span>
                  <span className="shrink-0 text-xs text-muted-foreground">
                    {r.sessions} session{r.sessions === 1 ? '' : 's'}
                  </span>
                </div>
                <div className="tnum mt-1 flex flex-wrap items-center gap-x-4 gap-y-0.5 text-sm text-muted-foreground">
                  {r.best_weight && (
                    <span className="flex items-center gap-1">
                      <Trophy size={13} className="text-record" />
                      {r.best_weight.weight} {unit} × {r.best_weight.reps}
                    </span>
                  )}
                  {r.best_1rm && <span>1RM {r.best_1rm.value} {unit}</span>}
                  {r.best_reps && <span>{r.best_reps.reps} reps (BW)</span>}
                  {r.best_weight && (
                    <span className="text-muted-foreground/70">
                      {formatRelativeDate(r.best_weight.date)}
                    </span>
                  )}
                </div>
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
