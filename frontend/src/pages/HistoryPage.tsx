import { CalendarDays, Clock, Trophy, Weight } from 'lucide-react'
import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'
import { api } from '../lib/api'
import { formatDuration, formatRelativeDate, formatVolume } from '../lib/format'
import type { WorkoutSummary } from '../lib/types'

const PAGE = 20

export default function HistoryPage() {
  const navigate = useNavigate()
  const { user } = useAuth()
  const [workouts, setWorkouts] = useState<WorkoutSummary[]>([])
  const [done, setDone] = useState(false)
  const [loading, setLoading] = useState(true)

  const load = (offset: number) => {
    setLoading(true)
    api<WorkoutSummary[]>(`/workouts?limit=${PAGE}&offset=${offset}`)
      .then((page) => {
        setWorkouts((prev) => (offset === 0 ? page : [...prev, ...page]))
        if (page.length < PAGE) setDone(true)
      })
      .catch(() => {})
      .finally(() => setLoading(false))
  }

  useEffect(() => load(0), [])

  return (
    <div className="safe-top px-4">
      <header className="pt-6 pb-4">
        <h1 className="text-3xl">History</h1>
      </header>

      {workouts.length === 0 && !loading ? (
        <div className="rounded-xl border border-dashed p-8 text-center text-sm text-muted-foreground">
          No workouts yet. Your finished workouts will show up here.
        </div>
      ) : (
        <div className="grid gap-3 md:grid-cols-2">
          {workouts.map((w, i) => (
            <button
              key={w.id}
              onClick={() => navigate(`/history/${w.id}`)}
              className="animate-card-appear touch-feedback rounded-xl border bg-card p-4 text-left"
              style={{ animationDelay: `${Math.min(i, 8) * 40}ms` }}
            >
              <div className="flex items-baseline justify-between gap-2">
                <h3 className="min-w-0 truncate text-lg">{w.name}</h3>
                <span className="flex shrink-0 items-center gap-1 text-sm text-muted-foreground">
                  <CalendarDays size={14} /> {formatRelativeDate(w.started_at)}
                </span>
              </div>
              <div className="mt-1.5 flex items-center gap-4 text-sm text-muted-foreground">
                <span className="tnum flex items-center gap-1">
                  <Clock size={14} /> {formatDuration(w.duration_seconds)}
                </span>
                <span className="tnum flex items-center gap-1">
                  <Weight size={14} /> {formatVolume(w.total_volume, user?.unit ?? 'kg')}
                </span>
                {w.pr_count > 0 && (
                  <span className="tnum flex items-center gap-1 text-record">
                    <Trophy size={14} /> {w.pr_count} PR{w.pr_count > 1 ? 's' : ''}
                  </span>
                )}
              </div>
              <p className="mt-2 line-clamp-2 text-sm text-muted-foreground">
                {w.exercise_summaries.join(', ')}
              </p>
            </button>
          ))}
          {!done && workouts.length > 0 && (
            <button
              onClick={() => load(workouts.length)}
              disabled={loading}
              className="touch-feedback rounded-lg py-3 text-sm font-semibold text-primary disabled:opacity-50 md:col-span-2"
            >
              {loading ? 'Loading…' : 'Load more'}
            </button>
          )}
        </div>
      )}
    </div>
  )
}
