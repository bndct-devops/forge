import { Check, Share, Trophy } from 'lucide-react'
import { useEffect, useRef, useState } from 'react'
import { formatDuration, formatRelativeDate, formatVolume } from '../lib/format'
import { shareWorkoutCard } from '../lib/shareCard'
import { toast } from '../lib/toast'
import type { FinishResult } from '../lib/types'

/** Brief ember-toned confetti burst. Hand-rolled — no dependencies, respects
 *  prefers-reduced-motion, cleans itself up after the burst settles. */
function Confetti() {
  const canvasRef = useRef<HTMLCanvasElement>(null)

  useEffect(() => {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return
    const canvas = canvasRef.current
    if (!canvas) return
    const ctx = canvas.getContext('2d')
    if (!ctx) return

    const dpr = window.devicePixelRatio || 1
    const w = canvas.clientWidth
    const h = canvas.clientHeight
    canvas.width = w * dpr
    canvas.height = h * dpr
    ctx.scale(dpr, dpr)

    const colors = ['#de844f', '#b8873f', '#e8e4dc', '#b05315', '#c56b6a']
    const origin = { x: w / 2, y: h * 0.3 }
    const particles = Array.from({ length: 60 }, (_, i) => {
      const angle = (Math.PI * 2 * i) / 60 + Math.random() * 0.4
      const speed = 3 + Math.random() * 5.5
      return {
        x: origin.x,
        y: origin.y,
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed - 3,
        size: 3 + Math.random() * 4,
        color: colors[i % colors.length],
        rotation: Math.random() * Math.PI,
        vr: (Math.random() - 0.5) * 0.3,
        life: 1,
      }
    })

    let frame = 0
    let raf = 0
    const tick = () => {
      frame++
      ctx.clearRect(0, 0, w, h)
      let alive = false
      for (const p of particles) {
        if (p.life <= 0) continue
        alive = true
        p.x += p.vx
        p.y += p.vy
        p.vy += 0.18 // gravity
        p.vx *= 0.985
        p.rotation += p.vr
        if (frame > 45) p.life -= 0.03
        ctx.save()
        ctx.globalAlpha = Math.max(0, p.life)
        ctx.translate(p.x, p.y)
        ctx.rotate(p.rotation)
        ctx.fillStyle = p.color
        ctx.fillRect(-p.size / 2, -p.size / 2, p.size, p.size * 0.6)
        ctx.restore()
      }
      if (alive && frame < 160) raf = requestAnimationFrame(tick)
      else ctx.clearRect(0, 0, w, h)
    }
    raf = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(raf)
  }, [])

  return (
    <canvas
      ref={canvasRef}
      className="pointer-events-none absolute inset-0 h-full w-full"
      aria-hidden="true"
    />
  )
}

function ordinal(n: number): string {
  if (n % 100 >= 11 && n % 100 <= 13) return `${n}th`
  return `${n}${['th', 'st', 'nd', 'rd'][Math.min(n % 10, 4)] ?? 'th'}`
}

interface FinishScreenProps {
  summary: FinishResult
  unit: string
  onDone: () => void
}

export default function FinishScreen({ summary, unit, onDone }: FinishScreenProps) {
  const [sharing, setSharing] = useState(false)
  const doShare = async () => {
    setSharing(true)
    try {
      await shareWorkoutCard(summary, unit)
    } catch {
      toast('Could not create the share image')
    }
    setSharing(false)
  }
  return (
    <div className="safe-top safe-bottom relative flex h-full flex-col">
      <Confetti />
      <div className="overscroll-contain flex min-h-0 flex-1 flex-col items-center justify-center overflow-y-auto px-6 py-8 text-center">
        <div
          className="animate-trophy-pop flex h-20 w-20 items-center justify-center rounded-full bg-primary text-primary-foreground"
          style={{ animationDelay: '100ms' }}
        >
          <Check size={40} strokeWidth={3} />
        </div>
        <h1 className="animate-card-appear mt-5 text-3xl" style={{ animationDelay: '200ms' }}>
          Workout complete
        </h1>
        <p
          className="animate-card-appear mt-1.5 text-sm text-muted-foreground"
          style={{ animationDelay: '280ms' }}
        >
          {summary.name} · your {ordinal(summary.workout_number)} workout
          {summary.week_workouts > 1 && ` · ${ordinal(summary.week_workouts)} this week`}
        </p>

        <div
          className="animate-card-appear mt-7 grid w-full max-w-sm grid-cols-3 gap-2"
          style={{ animationDelay: '360ms' }}
        >
          <div className="rounded-xl border bg-card p-3">
            <div className="tnum text-lg font-semibold">{formatDuration(summary.duration_seconds)}</div>
            <div className="text-xs text-muted-foreground">Duration</div>
          </div>
          <div className="rounded-xl border bg-card p-3">
            <div className="tnum text-lg font-semibold">{formatVolume(summary.total_volume, unit)}</div>
            <div className="text-xs text-muted-foreground">Volume</div>
          </div>
          <div className="rounded-xl border bg-card p-3">
            <div className="tnum text-lg font-semibold">{summary.total_sets}</div>
            <div className="text-xs text-muted-foreground">Sets</div>
          </div>
        </div>

        {summary.comparison && summary.comparison.prev_volume > 0 && (
          <p
            className="animate-card-appear mt-3 text-sm font-medium"
            style={{ animationDelay: '400ms' }}
          >
            {(() => {
              const delta =
                ((summary.total_volume - summary.comparison.prev_volume) /
                  summary.comparison.prev_volume) *
                100
              const rounded = Math.round(delta)
              const cls =
                rounded > 0 ? 'text-success' : rounded < 0 ? 'text-muted-foreground' : 'text-muted-foreground'
              return (
                <span className={cls}>
                  {rounded > 0 ? '+' : ''}
                  {rounded}% volume vs last time ({formatRelativeDate(summary.comparison.prev_date)})
                </span>
              )
            })()}
          </p>
        )}

        {summary.prs.length > 0 && (
          <div
            className="animate-card-appear mt-4 w-full max-w-sm"
            style={{ animationDelay: '440ms' }}
          >
            <h2 className="mb-2 text-left text-sm font-semibold tracking-wide text-muted-foreground uppercase">
              Personal records
            </h2>
            <div className="flex flex-col gap-1.5">
              {summary.prs.map((pr, i) => (
                <div
                  key={i}
                  className="flex items-center gap-2.5 rounded-lg border bg-card px-3 py-2.5 text-sm"
                >
                  <Trophy
                    size={16}
                    className="animate-trophy-pop shrink-0 text-record"
                    style={{ animationDelay: `${550 + i * 120}ms` }}
                  />
                  <span className="min-w-0 flex-1 truncate text-left font-medium">
                    {pr.exercise_name}
                  </span>
                  <span className="tnum text-muted-foreground">
                    {pr.kind === 'weight' && `${pr.value} ${unit} × ${pr.reps}`}
                    {pr.kind === '1rm' && `est. 1RM ${pr.value} ${unit}`}
                    {pr.kind === 'reps' && `${pr.value} reps`}
                  </span>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>

      <div className="flex shrink-0 gap-2 px-4 pb-4">
        <button
          onClick={doShare}
          disabled={sharing}
          className="touch-feedback flex h-13 items-center justify-center gap-2 rounded-xl bg-secondary px-5 py-3.5 text-base font-semibold text-secondary-foreground disabled:opacity-60"
        >
          <Share size={18} /> {sharing ? 'Rendering…' : 'Share'}
        </button>
        <button
          onClick={onDone}
          className="touch-feedback h-13 flex-1 rounded-xl bg-primary py-3.5 text-base font-semibold text-primary-foreground"
        >
          Done
        </button>
      </div>
    </div>
  )
}
