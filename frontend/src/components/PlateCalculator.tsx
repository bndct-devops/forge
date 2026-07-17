import { Minus, Plus } from 'lucide-react'
import { useMemo, useState } from 'react'
import Sheet from './Sheet'
import { useAuth } from '../contexts/AuthContext'
import { cn } from '../lib/utils'

// IWF-style colors, softened a touch so they sit inside the theme
const PLATES_KG: { weight: number; color: string; height: number }[] = [
  { weight: 25, color: '#c0504d', height: 96 },
  { weight: 20, color: '#4f6d9e', height: 96 },
  { weight: 15, color: '#b89a3f', height: 88 },
  { weight: 10, color: '#5a9367', height: 78 },
  { weight: 5, color: '#e8e4dc', height: 62 },
  { weight: 2.5, color: '#3d3936', height: 48 },
  { weight: 1.25, color: '#8a8580', height: 38 },
]
const PLATES_LB: { weight: number; color: string; height: number }[] = [
  { weight: 45, color: '#4f6d9e', height: 96 },
  { weight: 35, color: '#b89a3f', height: 88 },
  { weight: 25, color: '#5a9367', height: 78 },
  { weight: 10, color: '#e8e4dc', height: 62 },
  { weight: 5, color: '#3d3936', height: 48 },
  { weight: 2.5, color: '#8a8580', height: 38 },
]
// 0 = "the tracked weight is plates only" — the default. Whether the bar
// counts is a personal tracking convention, so it's opt-in per account.
const BARS_KG = [0, 20, 15, 10]
const BARS_LB = [0, 45, 35, 15]

interface PlateConfig {
  bar: number
  plates: number[]
}

function parseConfig(raw: string | null | undefined, unit: string): PlateConfig {
  const all = (unit === 'lb' ? PLATES_LB : PLATES_KG).map((p) => p.weight)
  const bars = unit === 'lb' ? BARS_LB : BARS_KG
  try {
    const parsed = raw ? (JSON.parse(raw) as Partial<PlateConfig>) : {}
    const bar = typeof parsed.bar === 'number' && bars.includes(parsed.bar) ? parsed.bar : 0
    const plates = Array.isArray(parsed.plates)
      ? all.filter((w) => (parsed.plates as number[]).includes(w))
      : all
    return { bar, plates: plates.length ? plates : all }
  } catch {
    return { bar: 0, plates: all }
  }
}

interface PlateCalculatorProps {
  open: boolean
  onClose: () => void
  initialWeight: number | null
  unit: string
}

export default function PlateCalculator({ open, onClose, initialWeight, unit }: PlateCalculatorProps) {
  const { user, updateUser } = useAuth()
  const [weight, setWeight] = useState<string | null>(null)
  const [config, setConfig] = useState<PlateConfig>(() => parseConfig(user?.plate_config, unit))
  const allPlates = unit === 'lb' ? PLATES_LB : PLATES_KG
  const plates = allPlates.filter((p) => config.plates.includes(p.weight))
  const bars = unit === 'lb' ? BARS_LB : BARS_KG
  const step = unit === 'lb' ? 5 : 2.5
  const bar = config.bar

  const saveConfig = (next: PlateConfig) => {
    setConfig(next)
    updateUser({ plate_config: JSON.stringify(next) }).catch(() => {})
  }

  const target = weight != null ? parseFloat(weight.replace(',', '.')) || 0 : (initialWeight ?? 0)

  const { perSide, remainder } = useMemo(() => {
    let side = Math.max(0, (target - bar) / 2)
    const result: { weight: number; color: string; height: number }[] = []
    for (const plate of plates) {
      while (side >= plate.weight - 1e-9) {
        result.push(plate)
        side -= plate.weight
      }
    }
    return { perSide: result, remainder: Math.round(side * 2 * 100) / 100 }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [target, bar, config.plates, unit])

  const counts = useMemo(() => {
    const map = new Map<number, number>()
    perSide.forEach((p) => map.set(p.weight, (map.get(p.weight) ?? 0) + 1))
    return [...map.entries()]
  }, [perSide])

  const adjust = (delta: number) => {
    setWeight(String(Math.max(bar, Math.round((target + delta) * 100) / 100)))
  }

  return (
    <Sheet open={open} onClose={onClose} title="Plate calculator">
      <div className="flex flex-col gap-4 pt-1">
        <div className="flex items-center justify-center gap-3">
          <button
            onClick={() => adjust(-step)}
            className="touch-feedback rounded-lg bg-secondary p-2.5"
            aria-label={`Minus ${step}`}
          >
            <Minus size={18} />
          </button>
          <div className="flex items-baseline gap-1">
            <input
              value={weight ?? (initialWeight != null ? String(initialWeight) : '')}
              onChange={(e) => setWeight(e.target.value)}
              onFocus={(e) => e.target.select()}
              inputMode="decimal"
              className="tnum w-28 rounded-lg border border-input bg-card px-2 py-1.5 text-center text-2xl font-semibold outline-none focus:ring-2 focus:ring-ring"
            />
            <span className="text-muted-foreground">{unit}</span>
          </div>
          <button
            onClick={() => adjust(step)}
            className="touch-feedback rounded-lg bg-secondary p-2.5"
            aria-label={`Plus ${step}`}
          >
            <Plus size={18} />
          </button>
        </div>

        {/* Half the bar, loaded left-to-right */}
        <div className="flex h-32 items-center rounded-xl bg-secondary/60 px-4">
          <div className="h-2.5 w-8 shrink-0 rounded-l-sm bg-muted-foreground/60" />
          <div className="h-4 w-1.5 shrink-0 bg-muted-foreground/70" />
          <div className="flex h-full items-center gap-1 pl-1">
            {perSide.map((p, i) => (
              <div
                key={i}
                className="w-3.5 shrink-0 rounded-[3px] border border-black/20"
                style={{ height: `${p.height}%`, backgroundColor: p.color }}
                title={`${p.weight} ${unit}`}
              />
            ))}
          </div>
          <div className="h-2.5 min-w-4 flex-1 rounded-r-sm bg-muted-foreground/60" />
        </div>

        <div className="text-center text-sm">
          {target < bar ? (
            <span className="text-muted-foreground">Below bar weight</span>
          ) : counts.length === 0 ? (
            <span className="text-muted-foreground">
              {bar > 0 ? 'Empty bar' : 'Nothing to plate'}
            </span>
          ) : (
            <span className="tnum font-medium">
              Per side: {counts.map(([w, n]) => `${n} × ${w}`).join('  ·  ')}
            </span>
          )}
          {remainder > 0 && target >= bar && (
            <p className="tnum mt-1 text-xs text-warning">
              {remainder} {unit} can’t be plated with your plates
            </p>
          )}
        </div>

        {target > bar && (
          <div>
            <h3 className="mb-1.5 text-sm font-semibold tracking-wide text-muted-foreground uppercase">
              Warm-up ramp
            </h3>
            <div className="flex flex-col gap-1">
              {[
                ...(bar > 0 ? [{ label: 'Empty bar', weight: bar, reps: 10 }] : []),
                { label: '40%', weight: Math.max(bar, Math.round((target * 0.4) / step) * step), reps: 5 },
                { label: '60%', weight: Math.max(bar, Math.round((target * 0.6) / step) * step), reps: 3 },
                { label: '80%', weight: Math.max(bar, Math.round((target * 0.8) / step) * step), reps: 2 },
              ]
                .filter((w, i, arr) => i === 0 || w.weight > arr[i - 1].weight)
                .map((w) => (
                  <div key={w.label} className="flex items-center justify-between rounded-lg bg-secondary px-3 py-1.5 text-sm">
                    <span className="text-muted-foreground">{w.label}</span>
                    <span className="tnum font-semibold">
                      {w.weight} {unit} × {w.reps}
                    </span>
                  </div>
                ))}
              <div className="flex items-center justify-between rounded-lg bg-accent-soft px-3 py-1.5 text-sm">
                <span className="font-medium text-primary">Working set</span>
                <span className="tnum font-semibold text-primary">
                  {target} {unit}
                </span>
              </div>
            </div>
          </div>
        )}

        <label className="flex items-center justify-between text-sm font-medium">
          Bar weight
          <select
            value={bar}
            onChange={(e) => saveConfig({ ...config, bar: Number(e.target.value) })}
            className="h-10 rounded-lg border border-input bg-card px-2 text-sm outline-none"
          >
            {bars.map((b) => (
              <option key={b} value={b}>
                {b === 0 ? 'Not counted' : `${b} ${unit}`}
              </option>
            ))}
          </select>
        </label>

        <div>
          <h3 className="mb-1.5 text-sm font-semibold tracking-wide text-muted-foreground uppercase">
            Your plates
          </h3>
          <div className="flex flex-wrap gap-1.5">
            {allPlates.map((p) => {
              const active = config.plates.includes(p.weight)
              return (
                <button
                  key={p.weight}
                  onClick={() => {
                    const next = active
                      ? config.plates.filter((w) => w !== p.weight)
                      : [...config.plates, p.weight]
                    if (next.length === 0) return // at least one plate
                    saveConfig({ ...config, plates: next })
                  }}
                  className={cn(
                    'tnum touch-feedback rounded-full border px-3 py-1.5 text-sm font-semibold',
                    active
                      ? 'border-transparent bg-accent-soft text-primary'
                      : 'text-muted-foreground line-through opacity-60',
                  )}
                >
                  {p.weight}
                </button>
              )
            })}
          </div>
        </div>
      </div>
    </Sheet>
  )
}
