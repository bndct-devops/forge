/** Backend stores naive UTC datetimes — parse them as UTC. */
export function parseUTC(value: string): Date {
  return new Date(/[zZ]|[+-]\d\d:\d\d$/.test(value) ? value : value + 'Z')
}

export function formatDuration(totalSeconds: number): string {
  const s = Math.max(0, Math.round(totalSeconds))
  const h = Math.floor(s / 3600)
  const m = Math.floor((s % 3600) / 60)
  const sec = s % 60
  if (h > 0) return `${h}h ${m}m`
  if (m > 0) return `${m}m ${sec}s`
  return `${sec}s`
}

export function formatClock(totalSeconds: number): string {
  const s = Math.max(0, Math.round(totalSeconds))
  const h = Math.floor(s / 3600)
  const m = Math.floor((s % 3600) / 60)
  const sec = s % 60
  const mm = h > 0 ? String(m).padStart(2, '0') : String(m)
  return `${h > 0 ? h + ':' : ''}${mm}:${String(sec).padStart(2, '0')}`
}

export function formatWeight(weight: number | null | undefined, unit: string): string {
  if (weight == null) return '—'
  const rounded = Math.round(weight * 100) / 100
  return `${rounded} ${unit}`
}

export function formatVolume(volume: number, unit: string): string {
  if (volume >= 10000) return `${Math.round(volume / 100) / 10}k ${unit}`
  return `${Math.round(volume)} ${unit}`
}

export function formatRelativeDate(value: string): string {
  const date = parseUTC(value)
  const now = new Date()
  const startOfDay = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
  const days = Math.round((startOfDay(now) - startOfDay(date)) / 86400000)
  if (days === 0) return 'Today'
  if (days === 1) return 'Yesterday'
  if (days < 7) return date.toLocaleDateString(undefined, { weekday: 'long' })
  return date.toLocaleDateString(undefined, {
    day: 'numeric',
    month: 'short',
    year: date.getFullYear() === now.getFullYear() ? undefined : 'numeric',
  })
}

export function formatTime(value: string): string {
  return parseUTC(value).toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' })
}

export function formatShortDate(value: string): string {
  return parseUTC(value).toLocaleDateString(undefined, { day: 'numeric', month: 'short' })
}

export function epley1RM(weight: number, reps: number): number {
  if (reps <= 0) return 0
  if (reps === 1) return weight
  return weight * (1 + reps / 30)
}

export function restLabel(seconds: number): string {
  if (seconds === 0) return 'Off'
  const m = Math.floor(seconds / 60)
  const s = seconds % 60
  return `${m}:${String(s).padStart(2, '0')}`
}
