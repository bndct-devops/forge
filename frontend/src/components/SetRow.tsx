import { Check, Trophy } from 'lucide-react'
import { useRef, useState } from 'react'
import { formatSetWeight } from '../lib/format'
import type { PastSet, SetEntry } from '../lib/types'
import { cn } from '../lib/utils'

export const SET_GRID = 'grid-cols-[2rem_1fr_4.5rem_4rem_2.75rem]'
export const SET_GRID_RPE = 'grid-cols-[2rem_1fr_3.75rem_3.25rem_2.75rem_2.75rem]'

interface SetRowProps {
  set: SetEntry
  previous: PastSet | undefined
  /** Placeholder fallback when there's no previous for this slot — the last
   *  filled set above it in the current session. */
  suggested?: { weight: number | null; reps: number | null }
  unit: string
  /** Bodyweight exercises complete on reps alone; empty weight logs as BW (0). */
  bodyweight: boolean
  /** Template progression: suggested weight + rep target range. */
  progression?: { weight: number | null; repMin: number | null; repMax: number | null }
  rpeEnabled: boolean
  onRpe: (rpe: number | null) => void
  onComplete: (weight: number, reps: number) => void
  onUncomplete: () => void
  onToggleWarmup: () => void
  onDelete: () => void
}

function parseNum(value: string): number | null {
  const n = parseFloat(value.replace(',', '.'))
  return Number.isFinite(n) ? n : null
}

/** One set line: number | previous ghost | weight | reps | check.
 *  Tap the set number to mark it a warm-up (excluded from PRs and volume).
 *  Swipe left to reveal delete, like a native list row. */
export default function SetRow({
  set,
  previous,
  suggested,
  unit,
  bodyweight,
  progression,
  rpeEnabled,
  onRpe,
  onComplete,
  onUncomplete,
  onToggleWarmup,
  onDelete,
}: SetRowProps) {
  const [weight, setWeight] = useState(set.weight != null && set.weight !== 0 ? String(set.weight) : '')
  const [reps, setReps] = useState(set.reps != null ? String(set.reps) : '')
  const [rpe, setRpe] = useState(set.rpe != null ? String(set.rpe) : '')
  const [justDone, setJustDone] = useState(false)
  const [removing, setRemoving] = useState(false)
  const [swipeActive, setSwipeActive] = useState(false)
  const rowRef = useRef<HTMLDivElement>(null)
  const gesture = useRef<{
    x: number
    y: number
    base: number
    mode: 'undecided' | 'swipe' | 'scroll'
    startedAt: number
    last: number
  } | null>(null)
  const revealed = useRef(false)
  const repsRef = useRef<HTMLInputElement>(null)

  // Direct DOM writes during the gesture — no React work per touchmove,
  // no transition fighting the finger. Animation only on release.
  const setX = (px: number, animate: boolean) => {
    const el = rowRef.current
    if (!el) return
    el.style.transition = animate ? 'transform 0.25s var(--spring)' : 'none'
    el.style.transform = `translateX(${px}px)`
  }

  const REVEAL = -80
  const FULL_SWIPE = -180

  const onTouchStart = (e: React.TouchEvent) => {
    gesture.current = {
      x: e.touches[0].clientX,
      y: e.touches[0].clientY,
      base: revealed.current ? REVEAL : 0,
      mode: 'undecided',
      startedAt: performance.now(),
      last: 0,
    }
  }

  const onTouchMove = (e: React.TouchEvent) => {
    const g = gesture.current
    if (!g || g.mode === 'scroll') return
    const dx = e.touches[0].clientX - g.x
    const dy = e.touches[0].clientY - g.y
    if (g.mode === 'undecided') {
      if (Math.abs(dy) > 10 && Math.abs(dy) > Math.abs(dx)) {
        g.mode = 'scroll' // vertical wins — hands off, let the page scroll
        return
      }
      if (Math.abs(dx) > 8 && Math.abs(dx) > Math.abs(dy) * 1.2) {
        g.mode = 'swipe'
        setSwipeActive(true) // mounts the red layer, once per gesture
      } else {
        return
      }
    }
    g.last = g.base + dx
    // free leftward travel (full-swipe deletes); slight resistance rightward
    const next = Math.min(0, g.last)
    setX(next, false)
  }

  const onTouchEnd = () => {
    const g = gesture.current
    gesture.current = null
    if (!g || g.mode !== 'swipe') return
    const total = Math.min(0, g.last)
    const quickFlick = performance.now() - g.startedAt < 220 && total - g.base < -40
    if (total <= FULL_SWIPE) {
      requestDelete() // iOS-Mail-style full swipe
      return
    }
    if (total < REVEAL * 0.6 || quickFlick) {
      revealed.current = true
      setX(REVEAL, true)
    } else {
      revealed.current = false
      setX(0, true)
      setSwipeActive(false)
    }
  }

  const requestDelete = () => {
    setX(-400, true)
    setRemoving(true) // collapse while sliding out, then remove from the list
    setTimeout(onDelete, 200)
  }

  // Progression suggestion beats the raw previous weight — that's the point
  const fallbackWeight =
    progression?.weight ?? previous?.weight ?? suggested?.weight ?? (bodyweight ? 0 : null)
  const fallbackReps =
    (progression?.weight != null ? progression.repMin : null) ??
    previous?.reps ??
    suggested?.reps ??
    progression?.repMin ??
    null
  const effectiveWeight = weight !== '' ? parseNum(weight) : fallbackWeight
  const effectiveReps = reps !== '' ? parseNum(reps) : fallbackReps
  const canComplete = effectiveWeight != null && effectiveReps != null

  const toggle = () => {
    if (set.is_completed) {
      onUncomplete()
      return
    }
    if (!canComplete) return
    if (weight === '' && fallbackWeight != null && fallbackWeight !== 0) {
      setWeight(String(fallbackWeight))
    }
    if (reps === '' && fallbackReps != null) setReps(String(fallbackReps))
    setJustDone(true)
    setTimeout(() => setJustDone(false), 600)
    onComplete(effectiveWeight!, effectiveReps!)
  }

  return (
    <div
      className="animate-card-appear relative overflow-hidden transition-[max-height,opacity] duration-200 ease-out"
      style={{ maxHeight: removing ? 0 : 64, opacity: removing ? 0 : 1 }}
    >
      {swipeActive && (
        <button
          onClick={requestDelete}
          className="absolute inset-0 flex items-center justify-end bg-destructive pr-7 text-sm font-semibold text-white"
        >
          Delete
        </button>
      )}
      <div
        ref={rowRef}
        className={cn(
          'relative grid items-center gap-2 bg-card py-1.5 transition-colors duration-300',
          rpeEnabled ? SET_GRID_RPE : SET_GRID,
          set.is_completed && 'bg-set-done',
        )}
        style={{ touchAction: 'pan-y' }}
        onTouchStart={onTouchStart}
        onTouchMove={onTouchMove}
        onTouchEnd={onTouchEnd}
        onTouchCancel={onTouchEnd}
      >
        {justDone && (
          <div className="animate-set-flash pointer-events-none absolute inset-0 bg-primary" />
        )}
        <button
          onClick={onToggleWarmup}
          aria-label={set.is_warmup ? 'Make working set' : 'Make warm-up set'}
          className="touch-feedback tnum rounded-md py-1 text-center text-sm font-semibold text-muted-foreground"
        >
          {set.is_pr ? (
            <Trophy size={15} className="mx-auto text-record" />
          ) : set.is_warmup ? (
            <span className="text-warning">W</span>
          ) : (
            set.position + 1
          )}
        </button>
        <span className="tnum truncate text-center text-sm text-muted-foreground">
          {previous && previous.reps != null
            ? `${formatSetWeight(previous.weight, unit)} × ${previous.reps}`
            : '—'}
        </span>
        <input
          value={weight}
          onChange={(e) => setWeight(e.target.value)}
          onFocus={(e) => e.target.select()}
          onKeyDown={(e) => e.key === 'Enter' && repsRef.current?.focus()}
          inputMode="decimal"
          enterKeyHint="next"
          placeholder={
            fallbackWeight != null && fallbackWeight !== 0
              ? String(fallbackWeight)
              : bodyweight
                ? 'BW'
                : unit
          }
          className="tnum h-9 rounded-md border border-input bg-background px-1 text-center text-base font-medium outline-none placeholder:text-muted-foreground/50 focus:ring-2 focus:ring-ring"
        />
        <input
          ref={repsRef}
          value={reps}
          onChange={(e) => setReps(e.target.value)}
          onFocus={(e) => e.target.select()}
          onKeyDown={(e) => e.key === 'Enter' && (e.target as HTMLInputElement).blur()}
          inputMode="numeric"
          enterKeyHint="done"
          placeholder={
            fallbackReps != null
              ? String(fallbackReps)
              : progression?.repMin != null && progression?.repMax != null
                ? `${progression.repMin}–${progression.repMax}`
                : 'reps'
          }
          className="tnum h-9 rounded-md border border-input bg-background px-1 text-center text-base font-medium outline-none placeholder:text-muted-foreground/50 focus:ring-2 focus:ring-ring"
        />
        {rpeEnabled && (
          <input
            value={rpe}
            onChange={(e) => setRpe(e.target.value)}
            onFocus={(e) => e.target.select()}
            onBlur={() => {
              const parsed = rpe !== '' ? parseNum(rpe) : null
              if (parsed !== (set.rpe ?? null)) onRpe(parsed)
            }}
            onKeyDown={(e) => e.key === 'Enter' && (e.target as HTMLInputElement).blur()}
            inputMode="decimal"
            enterKeyHint="done"
            placeholder="RPE"
            className="tnum h-9 rounded-md border border-input bg-background px-0.5 text-center text-sm font-medium outline-none placeholder:text-muted-foreground/50 focus:ring-2 focus:ring-ring"
          />
        )}
        <button
          onClick={toggle}
          disabled={!set.is_completed && !canComplete}
          aria-label={set.is_completed ? 'Mark set incomplete' : 'Complete set'}
          className={cn(
            'touch-feedback mx-auto flex h-9 w-9 items-center justify-center rounded-lg border transition-colors',
            set.is_completed
              ? 'border-success bg-success text-white'
              : 'border-input bg-secondary text-muted-foreground disabled:opacity-40',
            justDone && 'animate-check-pop',
          )}
        >
          <Check size={18} strokeWidth={3} />
        </button>
      </div>
    </div>
  )
}
