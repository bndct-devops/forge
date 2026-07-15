import { ChevronLeft, Trophy } from 'lucide-react'
import { useEffect, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import {
  Bar,
  BarChart,
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'
import Segmented from '../components/Segmented'
import { useAuth } from '../contexts/AuthContext'
import { api } from '../lib/api'
import { formatRelativeDate, formatShortDate, formatVolume } from '../lib/format'
import type { ExerciseStats } from '../lib/types'

type Metric = 'best_1rm' | 'best_weight' | 'volume'

const METRIC_LABEL: Record<Metric, string> = {
  best_1rm: 'Est. 1RM',
  best_weight: 'Best weight',
  volume: 'Volume',
}

function StatTile({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div className="rounded-xl border bg-card p-3">
      <div className="text-xs text-muted-foreground">{label}</div>
      <div className="tnum mt-0.5 text-lg font-semibold">{value}</div>
      {sub && <div className="tnum text-xs text-muted-foreground">{sub}</div>}
    </div>
  )
}

export default function ExerciseDetailPage() {
  const { id } = useParams()
  const navigate = useNavigate()
  const { user } = useAuth()
  const [stats, setStats] = useState<ExerciseStats | null>(null)
  const [metric, setMetric] = useState<Metric>('best_1rm')
  const unit = user?.unit ?? 'kg'

  useEffect(() => {
    api<ExerciseStats>(`/exercises/${id}/stats`)
      .then(setStats)
      .catch(() => navigate('/exercises', { replace: true }))
  }, [id, navigate])

  if (!stats) return null

  const { exercise, records, chart, history } = stats
  const data = chart.map((c) => ({ ...c, label: formatShortDate(c.date) }))

  const tooltipStyle = {
    backgroundColor: 'var(--popover)',
    border: '1px solid var(--border)',
    borderRadius: '10px',
    color: 'var(--popover-foreground)',
    fontSize: '13px',
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
        <div className="min-w-0">
          <h1 className="truncate text-2xl">{exercise.name}</h1>
          <p className="text-sm text-muted-foreground">
            {exercise.muscle_group} · {exercise.equipment}
          </p>
        </div>
      </header>

      {records.times_performed === 0 ? (
        <div className="mt-4 rounded-xl border border-dashed p-8 text-center text-sm text-muted-foreground">
          No sets logged yet. Records and progress will appear once you train this exercise.
        </div>
      ) : (
        <>
          <div className="mt-2 grid grid-cols-2 gap-2 md:grid-cols-4">
            <StatTile
              label="Best weight"
              value={records.best_weight ? `${records.best_weight.weight} ${unit}` : '—'}
              sub={records.best_weight ? `× ${records.best_weight.reps}` : undefined}
            />
            <StatTile
              label="Est. 1RM (Epley)"
              value={records.best_1rm ? `${records.best_1rm.value} ${unit}` : '—'}
              sub={
                records.best_1rm
                  ? `${records.best_1rm.weight} ${unit} × ${records.best_1rm.reps}`
                  : undefined
              }
            />
            <StatTile
              label="Best set volume"
              value={records.best_volume_set ? formatVolume(records.best_volume_set.value, unit) : '—'}
              sub={
                records.best_volume_set
                  ? `${records.best_volume_set.weight} ${unit} × ${records.best_volume_set.reps}`
                  : undefined
              }
            />
            <StatTile label="Workouts" value={String(records.times_performed)} />
          </div>

          <section className="mt-4 rounded-xl border bg-card p-4">
            <div className="mb-3 flex items-center justify-between gap-2">
              <h2 className="text-base">{METRIC_LABEL[metric]}</h2>
            </div>
            <Segmented<Metric>
              options={[
                { value: 'best_1rm', label: '1RM' },
                { value: 'best_weight', label: 'Weight' },
                { value: 'volume', label: 'Volume' },
              ]}
              value={metric}
              onChange={setMetric}
              className="mb-4"
            />
            <div className="h-52 md:h-72">
              <ResponsiveContainer width="100%" height="100%">
                {metric === 'volume' ? (
                  <BarChart data={data} margin={{ top: 6, right: 12, bottom: 0, left: -18 }}>
                    <CartesianGrid vertical={false} stroke="var(--border)" />
                    <XAxis
                      dataKey="label"
                      tick={{ fill: 'var(--muted-foreground)', fontSize: 11 }}
                      tickLine={false}
                      axisLine={{ stroke: 'var(--border)' }}
                    />
                    <YAxis
                      tick={{ fill: 'var(--muted-foreground)', fontSize: 11 }}
                      tickLine={false}
                      axisLine={false}
                      width={46}
                    />
                    <Tooltip
                      cursor={{ fill: 'var(--accent-soft)' }}
                      contentStyle={tooltipStyle}
                      formatter={(value) => [`${value} ${unit}`, 'Volume']}
                    />
                    <Bar
                      dataKey="volume"
                      fill="var(--chart-accent)"
                      radius={[4, 4, 0, 0]}
                      maxBarSize={28}
                    />
                  </BarChart>
                ) : (
                  <LineChart data={data} margin={{ top: 6, right: 12, bottom: 0, left: -18 }}>
                    <CartesianGrid vertical={false} stroke="var(--border)" />
                    <XAxis
                      dataKey="label"
                      tick={{ fill: 'var(--muted-foreground)', fontSize: 11 }}
                      tickLine={false}
                      axisLine={{ stroke: 'var(--border)' }}
                    />
                    <YAxis
                      domain={['auto', 'auto']}
                      tick={{ fill: 'var(--muted-foreground)', fontSize: 11 }}
                      tickLine={false}
                      axisLine={false}
                      width={46}
                    />
                    <Tooltip
                      cursor={{ stroke: 'var(--muted-foreground)', strokeDasharray: '3 3' }}
                      contentStyle={tooltipStyle}
                      formatter={(value) => [`${value} ${unit}`, METRIC_LABEL[metric]]}
                    />
                    <Line
                      type="monotone"
                      dataKey={metric}
                      stroke="var(--chart-accent)"
                      strokeWidth={2}
                      dot={{ r: 3, fill: 'var(--chart-accent)', strokeWidth: 0 }}
                      activeDot={{ r: 5, fill: 'var(--chart-accent)', stroke: 'var(--card)', strokeWidth: 2 }}
                    />
                  </LineChart>
                )}
              </ResponsiveContainer>
            </div>
          </section>

          <section className="mt-4 pb-8">
            <h2 className="mb-2 text-base">History</h2>
            <div className="grid gap-2 md:grid-cols-2">
              {history.map((h) => (
                <Link
                  key={h.workout_id}
                  to={`/history/${h.workout_id}`}
                  className="touch-feedback rounded-xl border bg-card p-3.5"
                >
                  <div className="flex items-baseline justify-between">
                    <span className="font-medium">{h.workout_name}</span>
                    <span className="text-sm text-muted-foreground">{formatRelativeDate(h.date)}</span>
                  </div>
                  <div className="mt-1.5 flex flex-col gap-0.5">
                    {h.sets.map((s, i) => (
                      <div key={i} className="tnum flex items-center gap-2 text-sm text-muted-foreground">
                        <span className="w-4 text-center font-semibold">{i + 1}</span>
                        <span>
                          {s.weight} {unit} × {s.reps}
                        </span>
                        {s.is_pr && <Trophy size={13} className="text-record" />}
                      </div>
                    ))}
                  </div>
                </Link>
              ))}
            </div>
          </section>
        </>
      )}
    </div>
  )
}
