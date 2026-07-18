import { CalendarDays, Dumbbell, Flame, Hourglass, Moon, Repeat, Ruler, Timer, TrendingDown, TrendingUp, Trophy, Weight } from 'lucide-react'
import { useEffect, useRef, useState } from 'react'
import {
  Bar,
  BarChart,
  CartesianGrid,
  ComposedChart,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'
import EmptyState from '../components/EmptyState'
import Segmented from '../components/Segmented'
import Skeleton from '../components/Skeleton'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'
import { api } from '../lib/api'
import { getPageCache, setPageCache } from '../lib/pageCache'
import { formatDuration, formatShortDate, formatVolume } from '../lib/format'
import { cn } from '../lib/utils'

interface StatsExtras {
  avg_per_week: number
  avg_duration_seconds: number
  avg_volume: number
  total_time_seconds: number
  longest_streak_weeks: number
  top_exercise: { name: string; sessions: number } | null
  busiest_weekday: string | null
  month_volume: number
  prev_month_volume: number
}

interface StatsTrends {
  weekdays: { day: string; workouts: number }[]
  rep_ranges: { range: string; sets: number }[]
  prs_by_month: { month: string; prs: number }[]
  top_lifts: { names: string[]; weeks: Record<string, string | number | null>[] }
  pacing: {
    weeks: { week_start: string; avg_rest_seconds: number | null; density: number | null }[]
    avg_rest_seconds: number | null
    avg_density: number | null
  } | null
  relative: { names: string[]; weeks: Record<string, string | number | null>[] } | null
}

interface StatsData {
  stalls: { exercise_id: number; name: string; weight: number; sessions: number; last_day: string }[]
  nudges: { group: string; days: number }[]
  extras: StatsExtras | null
  trends: StatsTrends
  totals: { workouts: number; volume: number; sets: number; prs: number; since: string | null }
  streak_weeks: number
  calendar: { date: string; workouts: number }[]
  weeks: { week_start: string; volume: number; workouts: number; avg_rpe: number | null }[]
  muscle_groups: { group: string; sets: number }[]
  muscle_trend: Record<string, { week_start: string; sets: number }[]>
  split_days: number
}

function StatTile({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <div className="min-w-0 rounded-xl border bg-card p-3">
      <div className="truncate text-xs text-muted-foreground">{label}</div>
      <div className="tnum mt-0.5 truncate text-lg font-semibold">{value}</div>
      {hint && <div className="truncate text-[10px] text-muted-foreground">{hint}</div>}
    </div>
  )
}

const CELL = 12 // px — GitHub-sized squares, never stretched
const GAP = 3

function heatColor(workouts: number): string {
  return workouts === 0
    ? 'var(--secondary)'
    : workouts === 1
      ? 'color-mix(in oklch, var(--chart-accent) 55%, var(--secondary))'
      : 'var(--chart-accent)'
}

const LABEL_COL = 30 // px, weekday labels

const SERIES_COLORS = ['var(--chart-accent)', '#6d87ab', '#5a9367']
const RPE_COLOR = '#6d87ab'

function formatRest(seconds: number): string {
  const m = Math.floor(seconds / 60)
  const s = Math.round(seconds % 60)
  return `${m}:${String(s).padStart(2, '0')}`
}

function HighlightRow({
  icon: Icon,
  label,
  value,
  hint,
}: {
  icon: typeof Flame
  label: string
  value: string
  hint?: string
}) {
  return (
    <div className="flex items-center gap-3 py-2">
      <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-accent-soft text-primary">
        <Icon size={15} />
      </div>
      <div className="min-w-0">
        <div className="text-xs text-muted-foreground">{label}</div>
        <div className="truncate text-sm font-semibold">
          {value}
          {hint && <span className="ml-1.5 font-normal text-muted-foreground">{hint}</span>}
        </div>
      </div>
    </div>
  )
}

/** GitHub-style training calendar: Monday-aligned week columns × 7 day rows
 *  at fixed cell size. No scrolling — the card shows as many of the most
 *  recent weeks as fit its width (a year on desktop, ~5 months on phones). */
function CalendarHeatmap({ days }: { days: StatsData['calendar'] }) {
  const wrapRef = useRef<HTMLDivElement>(null)
  const [fitWeeks, setFitWeeks] = useState(20)
  useEffect(() => {
    const el = wrapRef.current
    if (!el) return
    const update = () =>
      setFitWeeks(Math.max(8, Math.floor((el.clientWidth - LABEL_COL + GAP) / (CELL + GAP))))
    update()
    const ro = new ResizeObserver(update)
    ro.observe(el)
    return () => ro.disconnect()
  }, [])

  const allWeeks: StatsData['calendar'][] = []
  for (let i = 0; i < days.length; i += 7) allWeeks.push(days.slice(i, i + 7))
  const weeks = allWeeks.slice(-fitWeeks)

  // A month label goes above the first week of each month in view
  const monthLabels = weeks.map((week, i) => {
    const month = new Date(`${week[0].date}T00:00:00`).toLocaleDateString(undefined, {
      month: 'short',
    })
    const prev = i > 0 ? weeks[i - 1] : null
    const prevMonth = prev
      ? new Date(`${prev[0].date}T00:00:00`).toLocaleDateString(undefined, { month: 'short' })
      : null
    return month !== prevMonth ? month : ''
  })

  const col = CELL + GAP
  return (
    <div ref={wrapRef}>
      <div>
        <div
          className="mb-1 flex text-[9px] text-muted-foreground"
          style={{ paddingLeft: LABEL_COL }}
        >
          {monthLabels.map((label, i) => (
            <span key={i} className="shrink-0 overflow-visible whitespace-nowrap" style={{ width: col }}>
              {label}
            </span>
          ))}
        </div>
        <div className="flex" style={{ gap: GAP }}>
          <div
            className="flex shrink-0 flex-col pr-1.5 text-right text-[9px] leading-none text-muted-foreground"
            style={{ gap: GAP, width: LABEL_COL - GAP }}
          >
            {['Mon', '', 'Wed', '', 'Fri', '', ''].map((d, i) => (
              <span key={i} className="flex items-center justify-end" style={{ height: CELL }}>
                {d}
              </span>
            ))}
          </div>
          {weeks.map((week, i) => (
            <div key={i} className="flex shrink-0 flex-col" style={{ gap: GAP }}>
              {week.map((d) => (
                <div
                  key={d.date}
                  title={`${d.date}: ${d.workouts} workout${d.workouts === 1 ? '' : 's'}`}
                  className="rounded-[3px]"
                  style={{ width: CELL, height: CELL, backgroundColor: heatColor(d.workouts) }}
                />
              ))}
            </div>
          ))}
        </div>
      </div>
      <div className="mt-2 flex items-center justify-end gap-1.5 text-[10px] text-muted-foreground">
        Less
        {[0, 1, 2].map((n) => (
          <span
            key={n}
            className="h-2.5 w-2.5 rounded-[3px]"
            style={{ backgroundColor: heatColor(n) }}
          />
        ))}
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
  const [tab, setTab] = useState<'overview' | 'trends'>('overview')
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
  const hasRpe = trend.some((w) => w.avg_rpe != null)
  const maxSets = Math.max(1, ...stats.muscle_groups.map((g) => g.sets))

  return (
    <div className="safe-top px-4 pb-8">
      <header className="flex items-center justify-between pt-6 pb-4">
        <h1 className="text-3xl">Stats</h1>
        <Segmented<'overview' | 'trends'>
          options={[
            { value: 'overview', label: 'Overview' },
            { value: 'trends', label: 'Trends' },
          ]}
          value={tab}
          onChange={setTab}
        />
      </header>

      {stats.totals.workouts === 0 ? (
        <EmptyState title="No training data yet">
          Finish your first workout and your stats will grow here.
        </EmptyState>
      ) : (
        <div className="flex flex-col gap-4">
          {tab === 'overview' && (
            <>
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
                    ? `weekly goal hit — ${thisWeek} workout${thisWeek === 1 ? '' : 's'} this week`
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

          {(stats.nudges ?? []).map((n) => (
            <div
              key={n.group}
              className="flex items-center gap-3 rounded-xl border bg-card px-4 py-3 text-sm"
            >
              <Moon size={17} className="shrink-0 text-muted-foreground" />
              <span>
                No <span className="font-semibold">{n.group}</span> work in {n.days} days
              </span>
            </div>
          ))}

          {(stats.stalls ?? []).length > 0 && (
            <section className="rounded-xl border bg-card px-4 py-2">
              <div className="flex items-center gap-2 pt-2 pb-1">
                <TrendingDown size={15} className="text-muted-foreground" />
                <h2 className="text-sm font-semibold">Stalled lifts</h2>
              </div>
              {stats.stalls.map((s) => (
                <button
                  key={s.exercise_id}
                  onClick={() => navigate(`/exercises/${s.exercise_id}`, { viewTransition: true })}
                  className="touch-feedback flex w-full items-center justify-between gap-3 py-2 text-left text-sm"
                >
                  <span className="min-w-0 truncate">
                    <span className="font-semibold">{s.name}</span>{' '}
                    <span className="text-muted-foreground">
                      stuck at {s.weight} {unit}
                    </span>
                  </span>
                  <span className="tnum shrink-0 text-xs text-muted-foreground">
                    {s.sessions} sessions
                  </span>
                </button>
              ))}
              <p className="pb-2 pt-1 text-[11px] text-muted-foreground">
                same top weight, rep target missed — a deload or variation may help
              </p>
            </section>
          )}

          <div className="grid grid-cols-2 gap-2 md:grid-cols-4">
            <StatTile label="Workouts" value={String(stats.totals.workouts)} />
            <StatTile label="Total volume" value={formatVolume(stats.totals.volume, unit)} />
            <StatTile label="Working sets" value={String(stats.totals.sets)} />
            <StatTile label="PRs" value={String(stats.totals.prs)} />
          </div>

          {stats.extras && (
            <section className="rounded-xl border bg-card px-4 py-2">
              <div className="grid md:grid-cols-2 md:gap-x-6">
                <HighlightRow
                  icon={Repeat}
                  label="Frequency"
                  value={`${stats.extras.avg_per_week}× / week`}
                />
                <HighlightRow
                  icon={Timer}
                  label="Average session"
                  value={formatDuration(stats.extras.avg_duration_seconds)}
                  hint={`· ${formatVolume(stats.extras.avg_volume, unit)}`}
                />
                <HighlightRow
                  icon={Hourglass}
                  label="Time under iron"
                  value={formatDuration(stats.extras.total_time_seconds)}
                />
                <HighlightRow
                  icon={Flame}
                  label="Longest streak"
                  value={`${stats.extras.longest_streak_weeks} week${stats.extras.longest_streak_weeks === 1 ? '' : 's'}`}
                />
                {stats.extras.top_exercise && (
                  <HighlightRow
                    icon={Dumbbell}
                    label="Most trained"
                    value={stats.extras.top_exercise.name}
                    hint={`· ${stats.extras.top_exercise.sessions} sessions`}
                  />
                )}
                {stats.extras.busiest_weekday && (
                  <HighlightRow
                    icon={CalendarDays}
                    label="Favourite day"
                    value={stats.extras.busiest_weekday}
                  />
                )}
                <HighlightRow
                  icon={TrendingUp}
                  label="This month"
                  value={formatVolume(stats.extras.month_volume, unit)}
                  hint={
                    stats.extras.prev_month_volume > 0
                      ? `· ${stats.extras.month_volume >= stats.extras.prev_month_volume ? '+' : ''}${Math.round(((stats.extras.month_volume - stats.extras.prev_month_volume) / stats.extras.prev_month_volume) * 100)}% vs last`
                      : undefined
                  }
                />
                {stats.totals.since && (
                  <HighlightRow
                    icon={Weight}
                    label="Training since"
                    value={new Date(stats.totals.since).toLocaleDateString(undefined, {
                      month: 'long',
                      year: 'numeric',
                    })}
                  />
                )}
              </div>
            </section>
          )}

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

            </>
          )}

          {tab === 'trends' && (
            <>
          <section className="rounded-xl border bg-card p-4">
            <h2 className={cn('text-base', hasRpe ? 'mb-1' : 'mb-3')}>Weekly volume</h2>
            {hasRpe && (
              <div className="mb-3 flex flex-wrap gap-x-4 gap-y-1">
                <span className="flex items-center gap-1.5 text-xs text-muted-foreground">
                  <span className="h-2 w-2 rounded-full" style={{ backgroundColor: 'var(--chart-accent)' }} />
                  Volume
                </span>
                <span className="flex items-center gap-1.5 text-xs text-muted-foreground">
                  <span className="h-2 w-2 rounded-full" style={{ backgroundColor: RPE_COLOR }} />
                  Avg RPE
                </span>
              </div>
            )}
            <div className="h-44 md:h-56">
              <ResponsiveContainer width="100%" height="100%">
                <ComposedChart data={trend} margin={{ top: 6, right: hasRpe ? -8 : 12, bottom: 0, left: -14 }}>
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
                    tickFormatter={(v: number) => (v >= 1000 ? `${Math.round(v / 1000)}k` : String(v))}
                  />
                  {hasRpe && (
                    <YAxis
                      yAxisId="rpe"
                      orientation="right"
                      domain={[5, 10]}
                      tick={{ fill: 'var(--muted-foreground)', fontSize: 11 }}
                      tickLine={false}
                      axisLine={false}
                      width={30}
                    />
                  )}
                  <Tooltip
                    cursor={{ fill: 'var(--accent-soft)' }}
                    contentStyle={{
                      backgroundColor: 'var(--popover)',
                      border: '1px solid var(--border)',
                      borderRadius: '10px',
                      color: 'var(--popover-foreground)',
                      fontSize: '13px',
                    }}
                    formatter={(value, name) =>
                      name === 'Avg RPE' ? [String(value), 'Avg RPE'] : [`${value} ${unit}`, 'Volume']
                    }
                    labelFormatter={(label) => `Week of ${label}`}
                  />
                  <Bar dataKey="volume" fill="var(--chart-accent)" radius={[4, 4, 0, 0]} maxBarSize={22} />
                  {hasRpe && (
                    <Line
                      yAxisId="rpe"
                      type="monotone"
                      dataKey="avg_rpe"
                      name="Avg RPE"
                      stroke={RPE_COLOR}
                      strokeWidth={2}
                      strokeDasharray="5 4"
                      dot={{ r: 3, fill: RPE_COLOR, strokeWidth: 0 }}
                      connectNulls
                    />
                  )}
                </ComposedChart>
              </ResponsiveContainer>
            </div>
          </section>

          {stats.trends.top_lifts.names.length > 0 && (
            <section className="rounded-xl border bg-card p-4">
              <h2 className="mb-1 text-base">Top lifts — estimated 1RM</h2>
              <div className="mb-3 flex flex-wrap gap-x-4 gap-y-1">
                {stats.trends.top_lifts.names.map((name, i) => (
                  <span key={name} className="flex items-center gap-1.5 text-xs text-muted-foreground">
                    <span
                      className="h-2 w-2 rounded-full"
                      style={{ backgroundColor: SERIES_COLORS[i] }}
                    />
                    {name}
                  </span>
                ))}
              </div>
              <div className="h-48 md:h-56">
                <ResponsiveContainer width="100%" height="100%">
                  <LineChart
                    data={stats.trends.top_lifts.weeks}
                    margin={{ top: 6, right: 12, bottom: 0, left: -14 }}
                  >
                    <CartesianGrid vertical={false} stroke="var(--border)" />
                    <XAxis
                      dataKey="week_start"
                      tick={{ fill: 'var(--muted-foreground)', fontSize: 11 }}
                      tickLine={false}
                      axisLine={{ stroke: 'var(--border)' }}
                      tickFormatter={(v: string) => formatShortDate(v)}
                      interval="preserveStartEnd"
                    />
                    <YAxis
                      tick={{ fill: 'var(--muted-foreground)', fontSize: 11 }}
                      tickLine={false}
                      axisLine={false}
                      width={44}
                      domain={['auto', 'auto']}
                    />
                    <Tooltip
                      contentStyle={{
                        backgroundColor: 'var(--popover)',
                        border: '1px solid var(--border)',
                        borderRadius: '10px',
                        color: 'var(--popover-foreground)',
                        fontSize: '13px',
                      }}
                      formatter={(value, name) => [`${value} ${unit}`, name]}
                      labelFormatter={(label) => `Week of ${formatShortDate(String(label))}`}
                    />
                    {stats.trends.top_lifts.names.map((name, i) => (
                      <Line
                        key={name}
                        type="monotone"
                        dataKey={name}
                        stroke={SERIES_COLORS[i]}
                        strokeWidth={2}
                        dot={{ r: 3, fill: SERIES_COLORS[i], strokeWidth: 0 }}
                        connectNulls
                      />
                    ))}
                  </LineChart>
                </ResponsiveContainer>
              </div>
            </section>
          )}

          {stats.trends.relative && stats.trends.relative.names.length > 0 && (
            <section className="rounded-xl border bg-card p-4">
              <h2 className="mb-1 text-base">Relative strength</h2>
              <p className="mb-3 text-xs text-muted-foreground">
                estimated 1RM ÷ bodyweight — honest progress while cutting or bulking
              </p>
              <div className="h-48 md:h-56">
                <ResponsiveContainer width="100%" height="100%">
                  <LineChart
                    data={stats.trends.relative.weeks}
                    margin={{ top: 6, right: 12, bottom: 0, left: -14 }}
                  >
                    <CartesianGrid vertical={false} stroke="var(--border)" />
                    <XAxis
                      dataKey="week_start"
                      tick={{ fill: 'var(--muted-foreground)', fontSize: 11 }}
                      tickLine={false}
                      axisLine={{ stroke: 'var(--border)' }}
                      tickFormatter={(v: string) => formatShortDate(v)}
                      interval="preserveStartEnd"
                    />
                    <YAxis
                      tick={{ fill: 'var(--muted-foreground)', fontSize: 11 }}
                      tickLine={false}
                      axisLine={false}
                      width={44}
                      domain={['auto', 'auto']}
                      tickFormatter={(v: number) => `${v}×`}
                    />
                    <Tooltip
                      contentStyle={{
                        backgroundColor: 'var(--popover)',
                        border: '1px solid var(--border)',
                        borderRadius: '10px',
                        color: 'var(--popover-foreground)',
                        fontSize: '13px',
                      }}
                      formatter={(value, name) => [`${value}× bodyweight`, name]}
                      labelFormatter={(label) => `Week of ${formatShortDate(String(label))}`}
                    />
                    {stats.trends.relative.names.map((name, i) => (
                      <Line
                        key={name}
                        type="monotone"
                        dataKey={name}
                        stroke={SERIES_COLORS[i]}
                        strokeWidth={2}
                        dot={{ r: 3, fill: SERIES_COLORS[i], strokeWidth: 0 }}
                        connectNulls
                      />
                    ))}
                  </LineChart>
                </ResponsiveContainer>
              </div>
            </section>
          )}

          {stats.trends.pacing && (
            <section className="rounded-xl border bg-card p-4">
              <h2 className="mb-1 text-base">Pacing</h2>
              <p className="mb-3 text-xs text-muted-foreground">
                measured rest between sets and how densely you train
              </p>
              <div className="mb-3 grid grid-cols-2 gap-2">
                <StatTile
                  label="Avg rest"
                  value={
                    stats.trends.pacing.avg_rest_seconds != null
                      ? `${formatRest(stats.trends.pacing.avg_rest_seconds)} min`
                      : '—'
                  }
                />
                <StatTile
                  label="Density"
                  value={
                    stats.trends.pacing.avg_density != null
                      ? `${stats.trends.pacing.avg_density} ${unit}/min`
                      : '—'
                  }
                />
              </div>
              {stats.trends.pacing.weeks.some((w) => w.avg_rest_seconds != null) && (
                <div className="h-36">
                  <ResponsiveContainer width="100%" height="100%">
                    <LineChart
                      data={stats.trends.pacing.weeks}
                      margin={{ top: 6, right: 12, bottom: 0, left: -14 }}
                    >
                      <CartesianGrid vertical={false} stroke="var(--border)" />
                      <XAxis
                        dataKey="week_start"
                        tick={{ fill: 'var(--muted-foreground)', fontSize: 11 }}
                        tickLine={false}
                        axisLine={{ stroke: 'var(--border)' }}
                        tickFormatter={(v: string) => formatShortDate(v)}
                        interval="preserveStartEnd"
                      />
                      <YAxis
                        tick={{ fill: 'var(--muted-foreground)', fontSize: 11 }}
                        tickLine={false}
                        axisLine={false}
                        width={44}
                        domain={['auto', 'auto']}
                        tickFormatter={(v: number) => formatRest(v)}
                      />
                      <Tooltip
                        contentStyle={{
                          backgroundColor: 'var(--popover)',
                          border: '1px solid var(--border)',
                          borderRadius: '10px',
                          color: 'var(--popover-foreground)',
                          fontSize: '13px',
                        }}
                        formatter={(value) => [`${formatRest(Number(value))} min`, 'Avg rest']}
                        labelFormatter={(label) => `Week of ${formatShortDate(String(label))}`}
                      />
                      <Line
                        type="monotone"
                        dataKey="avg_rest_seconds"
                        stroke="var(--chart-accent)"
                        strokeWidth={2}
                        dot={{ r: 3, fill: 'var(--chart-accent)', strokeWidth: 0 }}
                        connectNulls
                      />
                    </LineChart>
                  </ResponsiveContainer>
                </div>
              )}
            </section>
          )}

          <div className="grid gap-4 md:grid-cols-2">
            <section className="rounded-xl border bg-card p-4">
              <h2 className="mb-3 text-base">Training days</h2>
              <div className="h-36">
                <ResponsiveContainer width="100%" height="100%">
                  <BarChart data={stats.trends.weekdays} margin={{ top: 6, right: 0, bottom: 0, left: -30 }}>
                    <CartesianGrid vertical={false} stroke="var(--border)" />
                    <XAxis
                      dataKey="day"
                      tick={{ fill: 'var(--muted-foreground)', fontSize: 11 }}
                      tickLine={false}
                      axisLine={{ stroke: 'var(--border)' }}
                    />
                    <YAxis
                      tick={{ fill: 'var(--muted-foreground)', fontSize: 11 }}
                      tickLine={false}
                      axisLine={false}
                      allowDecimals={false}
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
                      formatter={(value) => [String(value), 'Workouts']}
                    />
                    <Bar dataKey="workouts" fill="var(--chart-accent)" radius={[4, 4, 0, 0]} maxBarSize={22} />
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </section>

            <section className="rounded-xl border bg-card p-4">
              <h2 className="mb-1 text-base">Rep ranges</h2>
              <p className="mb-3 text-xs text-muted-foreground">
                working sets, last {stats.split_days} days
              </p>
              <div className="flex flex-col gap-2.5">
                {(() => {
                  const maxBucket = Math.max(1, ...stats.trends.rep_ranges.map((r) => r.sets))
                  return stats.trends.rep_ranges.map((r) => (
                    <div key={r.range} className="flex items-center gap-3">
                      <span className="tnum w-12 shrink-0 text-sm font-medium">{r.range}</span>
                      <div className="h-4 flex-1 overflow-hidden rounded-full bg-secondary">
                        <div
                          className="h-full rounded-full"
                          style={{
                            width: `${(r.sets / maxBucket) * 100}%`,
                            backgroundColor: 'var(--chart-accent)',
                          }}
                        />
                      </div>
                      <span className="tnum w-8 shrink-0 text-right text-sm text-muted-foreground">
                        {r.sets}
                      </span>
                    </div>
                  ))
                })()}
              </div>
              <p className="mt-3 text-xs text-muted-foreground">reps per working set</p>
            </section>
          </div>

          <section className="rounded-xl border bg-card p-4">
            <h2 className="mb-3 text-base">PRs per month</h2>
            <div className="h-36">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={stats.trends.prs_by_month} margin={{ top: 6, right: 0, bottom: 0, left: -30 }}>
                  <CartesianGrid vertical={false} stroke="var(--border)" />
                  <XAxis
                    dataKey="month"
                    tick={{ fill: 'var(--muted-foreground)', fontSize: 11 }}
                    tickLine={false}
                    axisLine={{ stroke: 'var(--border)' }}
                  />
                  <YAxis
                    tick={{ fill: 'var(--muted-foreground)', fontSize: 11 }}
                    tickLine={false}
                    axisLine={false}
                    allowDecimals={false}
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
                    formatter={(value) => [String(value), 'PRs']}
                  />
                  <Bar dataKey="prs" fill="#d4a843" radius={[4, 4, 0, 0]} maxBarSize={22} />
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
            </>
          )}
        </div>
      )}
    </div>
  )
}
