import { ChevronLeft, ChevronRight } from 'lucide-react'
import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import Sheet from './Sheet'
import { api } from '../lib/api'
import { formatTime, formatVolume, parseUTC } from '../lib/format'
import type { WorkoutSummary } from '../lib/types'
import { cn } from '../lib/utils'

const WEEKDAYS = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su']

function monthKey(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`
}

export default function HistoryCalendar({ unit }: { unit: string }) {
  const navigate = useNavigate()
  const [month, setMonth] = useState(() => new Date())
  const [workouts, setWorkouts] = useState<WorkoutSummary[]>([])
  const [dayWorkouts, setDayWorkouts] = useState<WorkoutSummary[] | null>(null)

  useEffect(() => {
    api<WorkoutSummary[]>(`/workouts?month=${monthKey(month)}`)
      .then(setWorkouts)
      .catch(() => {})
  }, [month])

  const byDay = new Map<number, WorkoutSummary[]>()
  for (const w of workouts) {
    const d = parseUTC(w.started_at)
    if (d.getMonth() === month.getMonth() && d.getFullYear() === month.getFullYear()) {
      const day = d.getDate()
      byDay.set(day, [...(byDay.get(day) ?? []), w])
    }
  }

  const first = new Date(month.getFullYear(), month.getMonth(), 1)
  const daysInMonth = new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate()
  const leadingBlanks = (first.getDay() + 6) % 7 // Monday-start
  const today = new Date()
  const isThisMonth =
    today.getMonth() === month.getMonth() && today.getFullYear() === month.getFullYear()

  const openDay = (day: number) => {
    const list = byDay.get(day)
    if (!list || list.length === 0) return
    if (list.length === 1) navigate(`/history/${list[0].id}`, { viewTransition: true })
    else setDayWorkouts(list)
  }

  return (
    <div>
      <div className="mb-3 flex items-center justify-between">
        <button
          onClick={() => setMonth(new Date(month.getFullYear(), month.getMonth() - 1, 1))}
          className="touch-feedback rounded-full p-2 text-muted-foreground"
          aria-label="Previous month"
        >
          <ChevronLeft size={20} />
        </button>
        <h2 className="text-base">
          {month.toLocaleDateString(undefined, { month: 'long', year: 'numeric' })}
        </h2>
        <button
          onClick={() => setMonth(new Date(month.getFullYear(), month.getMonth() + 1, 1))}
          className="touch-feedback rounded-full p-2 text-muted-foreground"
          aria-label="Next month"
        >
          <ChevronRight size={20} />
        </button>
      </div>

      <div className="grid grid-cols-7 gap-1.5">
        {WEEKDAYS.map((d) => (
          <div key={d} className="pb-1 text-center text-[11px] font-semibold text-muted-foreground">
            {d}
          </div>
        ))}
        {Array.from({ length: leadingBlanks }, (_, i) => (
          <div key={`blank-${i}`} />
        ))}
        {Array.from({ length: daysInMonth }, (_, i) => {
          const day = i + 1
          const count = byDay.get(day)?.length ?? 0
          const isToday = isThisMonth && today.getDate() === day
          return (
            <button
              key={day}
              onClick={() => openDay(day)}
              className={cn(
                'touch-feedback tnum flex aspect-square flex-col items-center justify-center rounded-lg text-sm',
                count > 0
                  ? 'bg-accent-soft font-semibold text-primary'
                  : 'text-muted-foreground',
                isToday && 'ring-1 ring-ring',
              )}
            >
              {day}
              {count > 0 && (
                <span className="mt-0.5 flex gap-0.5">
                  {Array.from({ length: Math.min(count, 3) }, (_, j) => (
                    <span key={j} className="h-1 w-1 rounded-full bg-primary" />
                  ))}
                </span>
              )}
            </button>
          )
        })}
      </div>

      <Sheet
        open={dayWorkouts != null}
        onClose={() => setDayWorkouts(null)}
        title="Workouts that day"
      >
        <div className="flex flex-col gap-2 pt-1 pb-2">
          {dayWorkouts?.map((w) => (
            <button
              key={w.id}
              onClick={() => navigate(`/history/${w.id}`, { viewTransition: true })}
              className="touch-feedback rounded-xl border bg-card p-3.5 text-left"
            >
              <div className="flex items-baseline justify-between">
                <span className="font-medium">{w.name}</span>
                <span className="text-sm text-muted-foreground">{formatTime(w.started_at)}</span>
              </div>
              <p className="tnum mt-1 text-sm text-muted-foreground">
                {w.total_sets} sets · {formatVolume(w.total_volume, unit)}
              </p>
            </button>
          ))}
        </div>
      </Sheet>
    </div>
  )
}
