import { ChevronLeft, Clock, Trash2, Trophy, Weight } from 'lucide-react'
import { useEffect, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import Sheet from '../components/Sheet'
import { useAuth } from '../contexts/AuthContext'
import { api } from '../lib/api'
import {
  formatDuration,
  formatRelativeDate,
  formatSetWeight,
  formatTime,
  formatVolume,
} from '../lib/format'
import type { Workout } from '../lib/types'

export default function WorkoutDetailPage() {
  const { id } = useParams()
  const navigate = useNavigate()
  const { user } = useAuth()
  const [workout, setWorkout] = useState<Workout | null>(null)
  const [confirmDelete, setConfirmDelete] = useState(false)
  const unit = user?.unit ?? 'kg'

  useEffect(() => {
    api<Workout>(`/workouts/${id}`)
      .then(setWorkout)
      .catch(() => navigate('/history', { replace: true }))
  }, [id, navigate])

  if (!workout) return null

  const remove = async () => {
    await api(`/workouts/${workout.id}`, { method: 'DELETE' })
    navigate('/history', { replace: true })
  }

  return (
    <div className="safe-top px-4">
      <header className="flex items-center gap-2 pt-4 pb-2">
        <button
          onClick={() => navigate(-1)}
          className="touch-feedback -ml-2 rounded-full p-2 text-muted-foreground"
          aria-label="Back"
        >
          <ChevronLeft size={24} />
        </button>
        <div className="min-w-0 flex-1">
          <h1 className="truncate text-2xl">{workout.name}</h1>
          <p className="text-sm text-muted-foreground">
            {formatRelativeDate(workout.started_at)} at {formatTime(workout.started_at)}
          </p>
        </div>
        <button
          onClick={() => setConfirmDelete(true)}
          className="touch-feedback rounded-full p-2 text-muted-foreground"
          aria-label="Delete workout"
        >
          <Trash2 size={19} />
        </button>
      </header>

      <div className="mt-2 grid grid-cols-3 gap-2 md:max-w-md">
        <div className="rounded-xl border bg-card p-3 text-center">
          <Clock size={16} className="mx-auto mb-1 text-muted-foreground" />
          <div className="tnum font-semibold">{formatDuration(workout.duration_seconds ?? 0)}</div>
        </div>
        <div className="rounded-xl border bg-card p-3 text-center">
          <Weight size={16} className="mx-auto mb-1 text-muted-foreground" />
          <div className="tnum font-semibold">{formatVolume(workout.total_volume ?? 0, unit)}</div>
        </div>
        <div className="rounded-xl border bg-card p-3 text-center">
          <Trophy size={16} className="mx-auto mb-1 text-muted-foreground" />
          <div className="tnum font-semibold">{workout.pr_count ?? 0} PRs</div>
        </div>
      </div>

      {workout.notes && (
        <p className="mt-3 rounded-xl border bg-card p-3.5 text-sm whitespace-pre-wrap text-muted-foreground">
          {workout.notes}
        </p>
      )}

      <div className="mt-4 grid gap-3 pb-8 md:grid-cols-2 md:items-start">
        {workout.exercises.map((we) => (
          <section key={we.id} className="animate-card-appear rounded-xl border bg-card p-4">
            <Link to={`/exercises/${we.exercise_id}`} className="font-semibold text-primary">
              {we.name}
            </Link>
            <div className="mt-2 flex flex-col gap-1">
              {we.sets.map((set) => (
                <div key={set.id} className="flex items-center gap-3 text-sm">
                  <span className="tnum w-5 text-center font-semibold text-muted-foreground">
                    {set.is_warmup ? <span className="text-warning">W</span> : set.position + 1}
                  </span>
                  <span className="tnum">
                    {formatSetWeight(set.weight, unit)} × {set.reps}
                  </span>
                  {set.is_pr && <Trophy size={14} className="text-record" />}
                </div>
              ))}
            </div>
          </section>
        ))}
      </div>

      <Sheet open={confirmDelete} onClose={() => setConfirmDelete(false)} title="Delete workout?">
        <div className="flex flex-col gap-3 pt-1">
          <p className="text-sm text-muted-foreground">
            This permanently removes the workout and its sets from your history.
          </p>
          <button
            onClick={remove}
            className="touch-feedback h-12 rounded-xl bg-destructive font-semibold text-white"
          >
            Delete workout
          </button>
        </div>
      </Sheet>
    </div>
  )
}
