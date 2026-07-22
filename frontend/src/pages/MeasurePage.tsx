import { ChevronLeft, ChevronRight, Plus, Trash2 } from 'lucide-react'
import { useCallback, useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import {
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'
import Sheet from '../components/Sheet'
import Skeleton from '../components/Skeleton'
import { useAuth } from '../contexts/AuthContext'
import { api } from '../lib/api'
import { useCachedState } from '../lib/dataCache'
import { formatRelativeDate, formatShortDate, toDatetimeLocal } from '../lib/format'

interface KindSummary {
  kind: string
  count: number
  latest: { value: number; measured_at: string } | null
}

interface Entry {
  id: number
  value: number
  measured_at: string
}

function unitFor(kind: string, weightUnit: string): string {
  if (kind === 'Weight') return weightUnit
  if (kind === 'Body fat') return '%'
  return weightUnit === 'lb' ? 'in' : 'cm'
}

export function MeasureListPage() {
  const navigate = useNavigate()
  const { user } = useAuth()
  const [kinds, setKinds] = useCachedState<KindSummary[] | null>('measurements', null)

  useEffect(() => {
    api<KindSummary[]>('/measurements').then(setKinds).catch(() => {})
  }, [])

  return (
    <div className="safe-top px-4 md:max-w-2xl">
      <header className="flex items-center gap-2 pt-4 pb-4">
        <button
          onClick={() => navigate(-1)}
          className="touch-feedback -ml-2 rounded-full p-2 text-muted-foreground"
          aria-label="Back"
        >
          <ChevronLeft size={24} />
        </button>
        <h1 className="text-2xl">Measurements</h1>
      </header>

      {kinds == null ? (
        <div className="flex flex-col gap-2">
          {Array.from({ length: 6 }, (_, i) => (
            <Skeleton key={i} className="h-14" />
          ))}
        </div>
      ) : (
        <ul className="divide-y divide-border overflow-hidden rounded-xl border bg-card">
          {kinds.map((k) => (
            <li key={k.kind}>
              <button
                onClick={() => navigate(`/measure/${encodeURIComponent(k.kind)}`, { viewTransition: true })}
                className="touch-feedback flex w-full items-center justify-between px-4 py-3.5 text-left"
              >
                <span className="font-medium">{k.kind}</span>
                <span className="flex items-center gap-2 text-sm text-muted-foreground">
                  {k.latest ? (
                    <>
                      <span className="tnum font-semibold text-foreground">
                        {k.latest.value} {unitFor(k.kind, user?.unit ?? 'kg')}
                      </span>
                      {formatRelativeDate(k.latest.measured_at)}
                    </>
                  ) : (
                    '—'
                  )}
                  <ChevronRight size={16} />
                </span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

export function MeasureDetailPage() {
  const { kind = '' } = useParams()
  const navigate = useNavigate()
  const { user } = useAuth()
  const [entries, setEntries] = useState<Entry[] | null>(null)
  const [adding, setAdding] = useState(false)
  const [value, setValue] = useState('')
  const [when, setWhen] = useState(() => toDatetimeLocal(new Date().toISOString()))
  const unit = unitFor(kind, user?.unit ?? 'kg')

  const load = useCallback(() => {
    api<Entry[]>(`/measurements/${encodeURIComponent(kind)}`)
      .then(setEntries)
      .catch(() => navigate('/measure', { replace: true }))
  }, [kind, navigate])

  useEffect(load, [load])

  const add = async () => {
    const parsed = parseFloat(value.replace(',', '.'))
    if (!Number.isFinite(parsed) || parsed <= 0) return
    await api('/measurements', {
      method: 'POST',
      body: { kind, value: parsed, measured_at: new Date(when).toISOString() },
    })
    setAdding(false)
    setValue('')
    load()
  }

  const remove = async (id: number) => {
    await api(`/measurements/${id}`, { method: 'DELETE' })
    setEntries((prev) => prev?.filter((e) => e.id !== id) ?? null)
  }

  const chartData = (entries ?? [])
    .slice()
    .reverse()
    .map((e) => ({ ...e, label: formatShortDate(e.measured_at) }))

  return (
    <div className="safe-top px-4 md:max-w-2xl">
      <header className="flex items-center gap-2 pt-4 pb-4">
        <button
          onClick={() => navigate(-1)}
          className="touch-feedback -ml-2 rounded-full p-2 text-muted-foreground"
          aria-label="Back"
        >
          <ChevronLeft size={24} />
        </button>
        <h1 className="flex-1 text-2xl">{kind}</h1>
        <button
          onClick={() => setAdding(true)}
          className="touch-feedback flex items-center gap-1 rounded-lg bg-primary px-3 py-2 text-sm font-semibold text-primary-foreground"
        >
          <Plus size={16} /> Add
        </button>
      </header>

      {entries != null && chartData.length >= 2 && (
        <section className="mb-4 rounded-xl border bg-card p-4">
          <div className="h-44">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart data={chartData} margin={{ top: 6, right: 12, bottom: 0, left: -18 }}>
                <CartesianGrid vertical={false} stroke="var(--border)" />
                <XAxis
                  dataKey="label"
                  tick={{ fill: 'var(--muted-foreground)', fontSize: 11 }}
                  tickLine={false}
                  axisLine={{ stroke: 'var(--border)' }}
                  interval="preserveStartEnd"
                />
                <YAxis
                  domain={['auto', 'auto']}
                  tick={{ fill: 'var(--muted-foreground)', fontSize: 11 }}
                  tickLine={false}
                  axisLine={false}
                  width={46}
                />
                <Tooltip
                  cursor={{ stroke: 'var(--muted-foreground)', strokeDasharray: '3 3' }}
                  contentStyle={{
                    backgroundColor: 'var(--popover)',
                    border: '1px solid var(--border)',
                    borderRadius: '10px',
                    color: 'var(--popover-foreground)',
                    fontSize: '13px',
                  }}
                  formatter={(v) => [`${v} ${unit}`, kind]}
                />
                <Line
                  type="monotone"
                  dataKey="value"
                  stroke="var(--chart-accent)"
                  strokeWidth={2}
                  dot={{ r: 3, fill: 'var(--chart-accent)', strokeWidth: 0 }}
                  activeDot={{ r: 5, fill: 'var(--chart-accent)', stroke: 'var(--card)', strokeWidth: 2 }}
                />
              </LineChart>
            </ResponsiveContainer>
          </div>
        </section>
      )}

      {entries == null ? (
        <div className="flex flex-col gap-2">
          {Array.from({ length: 4 }, (_, i) => (
            <Skeleton key={i} className="h-12" />
          ))}
        </div>
      ) : entries.length === 0 ? (
        <p className="rounded-xl border border-dashed p-8 text-center text-sm text-muted-foreground">
          No entries yet — add your first {kind.toLowerCase()} measurement.
        </p>
      ) : (
        <ul className="divide-y divide-border overflow-hidden rounded-xl border bg-card">
          {entries.map((e) => (
            <li key={e.id} className="flex items-center justify-between px-4 py-2.5">
              <span className="tnum font-semibold">
                {e.value} {unit}
              </span>
              <span className="flex items-center gap-1 text-sm text-muted-foreground">
                {formatRelativeDate(e.measured_at)}
                <button
                  onClick={() => remove(e.id)}
                  className="touch-feedback ml-1 rounded-full p-1.5"
                  aria-label="Delete entry"
                >
                  <Trash2 size={15} />
                </button>
              </span>
            </li>
          ))}
        </ul>
      )}

      <Sheet open={adding} onClose={() => setAdding(false)} title={`Add ${kind.toLowerCase()}`}>
        <div className="flex flex-col gap-3 pt-1">
          <label className="flex flex-col gap-1.5 text-sm font-medium">
            Value ({unit})
            <input
              autoFocus
              value={value}
              onChange={(e) => setValue(e.target.value)}
              inputMode="decimal"
              enterKeyHint="done"
              className="tnum h-12 rounded-lg border border-input bg-card px-4 text-base outline-none focus:ring-2 focus:ring-ring"
            />
          </label>
          <label className="flex flex-col gap-1.5 text-sm font-medium">
            When
            <input
              type="datetime-local"
              value={when}
              onChange={(e) => setWhen(e.target.value)}
              className="h-12 rounded-lg border border-input bg-card px-4 text-base outline-none focus:ring-2 focus:ring-ring"
            />
          </label>
          <button
            onClick={add}
            disabled={!value.trim()}
            className="touch-feedback h-12 rounded-xl bg-primary font-semibold text-primary-foreground disabled:opacity-50"
          >
            Save
          </button>
        </div>
      </Sheet>
    </div>
  )
}
