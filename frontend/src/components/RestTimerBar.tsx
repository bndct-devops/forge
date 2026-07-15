import { FastForward, Minus, Plus, Timer, Zap } from 'lucide-react'
import { useEffect, useState } from 'react'
import { restTimer, useRestTimer } from '../lib/timer'
import { formatClock } from '../lib/format'
import { cn } from '../lib/utils'

const GO_MS = 2600

/** Sticky rest countdown for the active workout. Slides in when a timer
 *  starts, drains left-to-right, and ends on a short "go!" beat instead of
 *  blinking out at 0:00. */
export default function RestTimerBar() {
  const timer = useRestTimer()
  const [, setTick] = useState(0)

  // Re-render once the "go!" window ends so the bar can slide away
  const sinceEnd = Date.now() - restTimer.lastNaturalEnd()
  const showGo = timer == null && sinceEnd < GO_MS
  useEffect(() => {
    if (!showGo) return
    const t = setTimeout(() => setTick((v) => v + 1), GO_MS - sinceEnd + 50)
    return () => clearTimeout(t)
  }, [showGo, sinceEnd])

  const visible = timer != null || showGo

  return (
    <div
      className="overflow-hidden px-3 transition-all duration-300"
      style={{
        transitionTimingFunction: 'var(--spring)',
        transform: visible ? 'translateY(0)' : 'translateY(110%)',
        opacity: visible ? 1 : 0,
        maxHeight: visible ? '6rem' : 0,
        paddingBottom: visible ? '0.75rem' : 0,
        pointerEvents: visible ? 'auto' : 'none',
      }}
    >
      <div
        className={cn(
          'relative overflow-hidden rounded-xl border bg-card shadow-lg',
          showGo && 'animate-timer-pulse border-success/40',
        )}
      >
        {timer && (
          <div
            className="absolute inset-y-0 left-0 bg-accent-soft transition-[width] duration-300 ease-linear"
            style={{ width: `${timer.total > 0 ? (timer.remaining / timer.total) * 100 : 0}%` }}
          />
        )}
        {showGo ? (
          <div className="relative flex items-center justify-center gap-2 px-3 py-3 font-semibold text-success">
            <Zap size={18} className="fill-current" /> Rest over — go!
          </div>
        ) : (
          timer && (
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
          )
        )}
      </div>
    </div>
  )
}
