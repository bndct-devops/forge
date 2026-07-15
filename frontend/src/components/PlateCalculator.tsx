import { Minus, Plus } from 'lucide-react'
import { useMemo, useState } from 'react'
import Sheet from './Sheet'

const BAR_KEY = 'forge_bar_weight'

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
const BARS_KG = [20, 15, 10]
const BARS_LB = [45, 35, 15]

function getStoredBar(unit: string): number {
  const stored = parseFloat(localStorage.getItem(BAR_KEY) ?? '')
  const bars = unit === 'lb' ? BARS_LB : BARS_KG
  return bars.includes(stored) ? stored : bars[0]
}

interface PlateCalculatorProps {
  open: boolean
  onClose: () => void
  initialWeight: number | null
  unit: string
}

export default function PlateCalculator({ open, onClose, initialWeight, unit }: PlateCalculatorProps) {
  const [weight, setWeight] = useState<string | null>(null)
  const [bar, setBar] = useState(() => getStoredBar(unit))
  const plates = unit === 'lb' ? PLATES_LB : PLATES_KG
  const bars = unit === 'lb' ? BARS_LB : BARS_KG
  const step = unit === 'lb' ? 5 : 2.5

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
  }, [target, bar, plates])

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
            <span className="text-muted-foreground">Empty bar</span>
          ) : (
            <span className="tnum font-medium">
              Per side: {counts.map(([w, n]) => `${n} × ${w}`).join('  ·  ')}
            </span>
          )}
          {remainder > 0 && target >= bar && (
            <p className="tnum mt-1 text-xs text-warning">
              {remainder} {unit} can’t be plated with standard plates
            </p>
          )}
        </div>

        <label className="flex items-center justify-between text-sm font-medium">
          Bar weight
          <select
            value={bar}
            onChange={(e) => {
              const value = Number(e.target.value)
              setBar(value)
              localStorage.setItem(BAR_KEY, String(value))
            }}
            className="h-10 rounded-lg border border-input bg-card px-2 text-sm outline-none"
          >
            {bars.map((b) => (
              <option key={b} value={b}>
                {b} {unit}
              </option>
            ))}
          </select>
        </label>
      </div>
    </Sheet>
  )
}
