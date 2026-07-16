import { Flame, Ruler, Trophy } from 'lucide-react'
import { useEffect, useState } from 'react'
import {
  Bar,
  BarChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'
import EmptyState from '../components/EmptyState'
import Skeleton from '../components/Skeleton'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'
import { api } from '../lib/api'
import { getPageCache, setPageCache } from '../lib/pageCache'
import { formatShortDate, formatVolume } from '../lib/format'
import { cn } from '../lib/utils'

interface StatsData {
  totals: { workouts: number; volume: number; sets: number; prs: number; since: string | null }
  streak_weeks: number
  calendar: { date: string; workouts: number }[]
  weeks: { week_start: string; volume: number; workouts: number }[]
  muscle_groups: { group: string; sets: number }[]
  muscle_trend: Record<string, { week_start: string; sets: number }[]>
  split_days: number
}

function StatTile({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-xl border bg-card p-3">
      <div className="text-xs text-muted-foreground">{label}</div>
      <div className="tnum mt-0.5 text-lg font-semibold">{value}</div>
    </div>
  )
}

/** GitHub-style training calendar: 20 week columns x 7 day rows.
 *  Sequential single-hue fill from the chart accent (0 / 1 / 2+ sessions). */
function CalendarHeatmap({ days }: { days: StatsData['calendar'] }) {
  return (
    <div>
      <div className="grid w-full grid-flow-col grid-rows-7 gap-1">
        {days.map((d) => (
          <div
            key={d.date}
            title={`${d.date}: ${d.workouts} workout${d.workouts === 1 ? '' : 's'}`}
            className="aspect-square w-full rounded-[3px]"
            style={{
              backgroundColor:
                d.workouts === 0
                  ? 'var(--secondary)'
                  : d.workouts === 1
                    ? 'color-mix(in oklch, var(--chart-accent) 55%, var(--secondary))'
                    : 'var(--chart-accent)',
            }}
          />
        ))}
      </div>
      <div className="mt-2 flex items-center justify-end gap-1.5 text-[10px] text-muted-foreground">
        Less
        <span className="h-2.5 w-2.5 rounded-[3px]" style={{ backgroundColor: 'var(--secondary)' }} />
        <span
          className="h-2.5 w-2.5 rounded-[3px]"
          style={{ backgroundColor: 'color-mix(in oklch, var(--chart-accent) 55%, var(--secondary))' }}
        />
        <span className="h-2.5 w-2.5 rounded-[3px]" style={{ backgroundColor: 'var(--chart-accent)' }} />
        More
      </div>
    </div>
  )
}

export default function StatsPage() {
  const { user } = useAuth()
  const navigate = useNavigate()
  const [stats, setStats] = useState<StatsData | null>(() => getPageCache<StatsData>('stats'))
  const [expandedGroup, setExpandedGroup] = useState<string | null>(null)
  const unit = user?.unit ?? 'kg'

  useEffect(() => {
    api<StatsData>('/stats')
      .then((s) => {
        setPageCache('stats', s)
        setStats(s)
      })
      .catch(() => {})
  }, [])

  if (!stats) {
    return (
      <div className="safe-top px-4 pb-8">
        <header className="pt-6 pb-4">
          <h1 className="text-3xl">Stats</h1>
        </header>
        <div className="flex flex-col gap-4">
          <Skeleton className="h-20 rounded-xl" />
          <div className="grid grid-cols-2 gap-2 md:grid-cols-4">
            {Array.from({ length: 4 }, (_, i) => (
              <Skeleton key={i} className="h-16 rounded-xl" />
            ))}
          </div>
          <Skeleton className="h-44 rounded-xl" />
          <Skeleton className="h-56 rounded-xl" />
        </div>
      </div>
    )
  }

  const trend = stats.weeks.map((w) => ({
    ...w,
    label: formatShortDate(w.week_start + 'T00:00:00'),
  }))
  const maxSets = Math.max(1, ...stats.muscle_groups.map((g) => g.sets))

  return (
    <div className="safe-top px-4 pb-8">
      <header className="pt-6 pb-4">
        <h1 className="text-3xl">Stats</h1>
      </header>

      {stats.totals.workouts === 0 ? (
        <EmptyState title="No training data yet">
          Finish your first workout and your stats will grow here.
        </EmptyState>
      ) : (
        <div className="flex flex-col gap-4">
          <div
            className={cn(
              'flex items-center gap-3 rounded-xl border bg-card p-4',
              stats.streak_weeks > 0 && 'border-[color:var(--accent-soft)]',
            )}
          >
            <div className="flex h-11 w-11 items-center justify-center rounded-xl bg-accent-soft text-primary">
              <Flame size={22} />
            </div>
            <div className="flex-1">
              <div className="tnum text-lg font-semibold">
                {stats.streak_weeks} week{stats.streak_weeks === 1 ? '' : 's'} streak
              </div>
              <div className="text-sm text-muted-foreground">
                {(() => {
                  const thisWeek = stats.weeks[stats.weeks.length - 1]?.workouts ?? 0
                  const goal = user?.weekly_goal ?? 3
                  return thisWeek >= goal
                    ? `weekly goal hit — ${thisWeek} of ${goal} workouts`
                    : `${thisWeek} of ${goal} workouts this week`
                })()}
              </div>
              <div className="mt-1.5 flex gap-1">
                {Array.from({ length: user?.weekly_goal ?? 3 }, (_, i) => (
                  <div
                    key={i}
                    className="h-1.5 flex-1 rounded-full"
                    style={{
                      backgroundColor:
                        i < (stats.weeks[stats.weeks.length - 1]?.workouts ?? 0)
                          ? 'var(--chart-accent)'
                          : 'var(--secondary)',
                    }}
                  />
                ))}
              </div>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-2 md:grid-cols-4">
            <StatTile label="Workouts" value={String(stats.totals.workouts)} />
            <StatTile label="Total volume" value={formatVolume(stats.totals.volume, unit)} />
            <StatTile label="Working sets" value={String(stats.totals.sets)} />
            <StatTile label="PRs" value={String(stats.totals.prs)} />
          </div>

          <div className="grid grid-cols-2 gap-2">
            <button
              onClick={() => navigate('/records', { viewTransition: true })}
              className="touch-feedback flex items-center gap-2.5 rounded-xl border bg-card p-3.5 text-left"
            >
              <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-accent-soft text-primary">
                <Trophy size={18} />
              </div>
              <div className="min-w-0">
                <div className="truncate text-sm font-semibold">Records</div>
                <div className="truncate text-xs text-muted-foreground">all-time bests</div>
              </div>
            </button>
            <button
              onClick={() => navigate('/measure', { viewTransition: true })}
              className="touch-feedback flex items-center gap-2.5 rounded-xl border bg-card p-3.5 text-left"
            >
              <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-accent-soft text-primary">
                <Ruler size={18} />
              </div>
              <div className="min-w-0">
                <div className="truncate text-sm font-semibold">Measurements</div>
                <div className="truncate text-xs text-muted-foreground">body tracking</div>
              </div>
            </button>
          </div>

          <section className="rounded-xl border bg-card p-4">
            <h2 className="mb-3 text-base">Training calendar</h2>
            <CalendarHeatmap days={stats.calendar} />
          </section>

          <section className="rounded-xl border bg-card p-4">
            <h2 className="mb-3 text-base">Weekly volume</h2>
            <div className="h-44 md:h-56">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={trend} margin={{ top: 6, right: 12, bottom: 0, left: -14 }}>
                  <CartesianGrid vertical={false} stroke="var(--border)" />
                  <XAxis
                    dataKey="label"
                    tick={{ fill: 'var(--muted-foreground)', fontSize: 11 }}
                    tickLine={false}
                    axisLine={{ stroke: 'var(--border)' }}
                    interval="preserveStartEnd"
                  />
                  <YAxis
                    tick={{ fill: 'var(--muted-foreground)', fontSize: 11 }}
                    tickLine={false}
                    axisLine={false}
                    width={44}
                    tickFormatter={(v: number) => (v >= 1000 ? `${v / 1000}k` : String(v))}
                  />
                  <Tooltip
                    cursor={{ fill: 'var(--accent-soft)' }}
                    contentStyle={{
                      backgroundColor: 'var(--popover)',
                      border: '1px solid var(--border)',
                      borderRadius: '10px',
                      color: 'var(--popover-foreground)',
                      fontSize: '13px',
                    }}
                    formatter={(value) => [`${value} ${unit}`, 'Volume']}
                    labelFormatter={(label) => `Week of ${label}`}
                  />
                  <Bar dataKey="volume" fill="var(--chart-accent)" radius={[4, 4, 0, 0]} maxBarSize={22} />
                </BarChart>
              </ResponsiveContainer>
            </div>
          </section>

          <section className="rounded-xl border bg-card p-4">
            <h2 className="mb-1 text-base">Muscle split</h2>
            <p className="mb-3 text-xs text-muted-foreground">
              working sets, last {stats.split_days} days
            </p>
            <div className="flex flex-col gap-2.5">
              {stats.muscle_groups.map((g) => (
                <div key={g.group}>
                  <button
                    onClick={() => setExpandedGroup(expandedGroup === g.group ? null : g.group)}
                    className="touch-feedback flex w-full items-center gap-3"
                  >
                    <span className="w-20 shrink-0 text-left text-sm font-medium">{g.group}</span>
                    <div className="h-4 flex-1 overflow-hidden rounded-full bg-secondary">
                      <div
                        className="h-full rounded-full"
                        style={{
                          width: `${(g.sets / maxSets) * 100}%`,
                          backgroundColor: 'var(--chart-accent)',
                        }}
                      />
                    </div>
                    <span className="tnum w-8 shrink-0 text-right text-sm text-muted-foreground">
                      {g.sets}
                    </span>
                  </button>
                  {expandedGroup === g.group && stats.muscle_trend[g.group] && (
                    <div className="mt-2 mb-1 ml-20">
                      <div className="flex h-14 items-end gap-1">
                        {stats.muscle_trend[g.group].map((w) => {
                          const max = Math.max(1, ...stats.muscle_trend[g.group].map((x) => x.sets))
                          return (
                            <div key={w.week_start} className="flex flex-1 flex-col items-center gap-0.5">
                              <span className="tnum text-[9px] text-muted-foreground">{w.sets || ''}</span>
                              <div
                                className="w-full rounded-t-[3px]"
                                style={{
                                  height: `${Math.max(2, (w.sets / max) * 40)}px`,
                                  backgroundColor: w.sets > 0 ? 'var(--chart-accent)' : 'var(--secondary)',
                                }}
                              />
                            </div>
                          )
                        })}
                      </div>
                      <p className="mt-1 text-[10px] text-muted-foreground">sets per week, last 8 weeks</p>
                    </div>
                  )}
                </div>
              ))}
              {stats.muscle_groups.length === 0 && (
                <p className="text-sm text-muted-foreground">No working sets in this window yet.</p>
              )}
            </div>
          </section>
        </div>
      )}
    </div>
  )
}
