import { FastForward, Minus, Plus, Timer } from 'lucide-react'
import { restTimer, useRestTimer } from '../lib/timer'
import { formatClock } from '../lib/format'

/** Sticky rest countdown pinned above the bottom action area of the active
 *  workout. Progress track drains left-to-right as the rest elapses. */
export default function RestTimerBar() {
  const timer = useRestTimer()
  if (!timer) return null

  const pct = timer.total > 0 ? (timer.remaining / timer.total) * 100 : 0

  return (
    <div className="relative overflow-hidden rounded-xl border bg-card shadow-lg">
      <div
        className="absolute inset-y-0 left-0 bg-accent-soft transition-[width] duration-300 ease-linear"
        style={{ width: `${pct}%` }}
      />
      <div className="relative flex items-center gap-2 px-3 py-2">
        <Timer size={18} className="shrink-0 text-primary" />
        <span className="tnum min-w-[3.5rem] text-lg font-semibold">
          {formatClock(timer.remaining)}
        </span>
        <div className="ml-auto flex items-center gap-1.5">
          <button
            onClick={() => restTimer.adjust(-15)}
            className="touch-feedback flex h-9 items-center gap-0.5 rounded-lg bg-secondary px-2.5 text-sm font-semibold"
            aria-label="Subtract 15 seconds"
          >
            <Minus size={14} /> 15
          </button>
          <button
            onClick={() => restTimer.adjust(15)}
            className="touch-feedback flex h-9 items-center gap-0.5 rounded-lg bg-secondary px-2.5 text-sm font-semibold"
            aria-label="Add 15 seconds"
          >
            <Plus size={14} /> 15
          </button>
          <button
            onClick={() => restTimer.skip()}
            className="touch-feedback flex h-9 items-center gap-1 rounded-lg bg-primary px-3 text-sm font-semibold text-primary-foreground"
          >
            <FastForward size={14} /> Skip
          </button>
        </div>
      </div>
    </div>
  )
}
