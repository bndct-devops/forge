import { Check, Trophy } from 'lucide-react'
import { useRef, useState } from 'react'
import { formatSetWeight } from '../lib/format'
import type { PastSet, SetEntry } from '../lib/types'
import { cn } from '../lib/utils'

interface SetRowProps {
  set: SetEntry
  previous: PastSet | undefined
  /** Placeholder fallback when there's no previous for this slot — the last
   *  filled set above it in the current session (Strong's behavior). */
  suggested?: { weight: number | null; reps: number | null }
  unit: string
  /** Bodyweight exercises complete on reps alone; empty weight logs as BW (0). */
  bodyweight: boolean
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
 *  Swipe left to reveal delete, matching Strong's gesture. */
export default function SetRow({
  set,
  previous,
  suggested,
  unit,
  bodyweight,
  onComplete,
  onUncomplete,
  onToggleWarmup,
  onDelete,
}: SetRowProps) {
  const [weight, setWeight] = useState(set.weight != null && set.weight !== 0 ? String(set.weight) : '')
  const [reps, setReps] = useState(set.reps != null ? String(set.reps) : '')
  const [offset, setOffset] = useState(0)
  const [justDone, setJustDone] = useState(false)
  const touchStart = useRef<number | null>(null)

  const fallbackWeight = previous?.weight ?? suggested?.weight ?? (bodyweight ? 0 : null)
  const fallbackReps = previous?.reps ?? suggested?.reps ?? null
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
    <div className="animate-card-appear relative overflow-hidden">
      {offset < 0 && (
        <button
          onClick={onDelete}
          className="absolute inset-y-0 right-0 flex w-20 items-center justify-center bg-destructive text-sm font-semibold text-white"
        >
          Delete
        </button>
      )}
      <div
        className={cn(
          'relative grid grid-cols-[2rem_1fr_4.5rem_4rem_2.75rem] items-center gap-2 bg-card py-1.5 transition-[transform,background-color] duration-300',
          set.is_completed && 'bg-accent-soft',
          justDone && 'animate-set-done',
        )}
        style={{ transform: `translateX(${offset}px)` }}
        onTouchStart={(e) => {
          touchStart.current = e.touches[0].clientX
        }}
        onTouchMove={(e) => {
          if (touchStart.current == null) return
          const dx = e.touches[0].clientX - touchStart.current
          setOffset(Math.max(-80, Math.min(0, dx)))
        }}
        onTouchEnd={() => {
          setOffset((o) => (o < -60 ? -80 : 0))
          touchStart.current = null
        }}
      >
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
          onKeyDown={(e) => e.key === 'Enter' && (e.target as HTMLInputElement).blur()}
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
          value={reps}
          onChange={(e) => setReps(e.target.value)}
          onFocus={(e) => e.target.select()}
          onKeyDown={(e) => e.key === 'Enter' && (e.target as HTMLInputElement).blur()}
          inputMode="numeric"
          enterKeyHint="done"
          placeholder={fallbackReps != null ? String(fallbackReps) : 'reps'}
          className="tnum h-9 rounded-md border border-input bg-background px-1 text-center text-base font-medium outline-none placeholder:text-muted-foreground/50 focus:ring-2 focus:ring-ring"
        />
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
