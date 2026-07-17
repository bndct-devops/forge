/** Renders a finished workout as a shareable image and hands it to the
 *  system share sheet (Web Share API level 2). Falls back to a download
 *  where file-sharing isn't available. */
import { formatDuration, formatVolume } from './format'
import type { FinishResult } from './types'

// Tome/Forge dark tokens, hex-approximated for canvas
const BG = '#171412'
const CARD = '#211d1a'
const BORDER = '#37312c'
const INK = '#ece7e0'
const MUTED = '#a49c92'
const EMBER = '#de844f'
const RECORD = '#d4a843'

const W = 1080
const H = 1350
const PAD = 88

function roundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
  ctx.beginPath()
  ctx.moveTo(x + r, y)
  ctx.arcTo(x + w, y, x + w, y + h, r)
  ctx.arcTo(x + w, y + h, x, y + h, r)
  ctx.arcTo(x, y + h, x, y, r)
  ctx.arcTo(x, y, x + w, y, r)
  ctx.closePath()
}

function drawCard(summary: FinishResult, unit: string): HTMLCanvasElement {
  const canvas = document.createElement('canvas')
  canvas.width = W
  canvas.height = H
  const ctx = canvas.getContext('2d')!

  ctx.fillStyle = BG
  ctx.fillRect(0, 0, W, H)

  // Ember glow up top so the card isn't a flat void
  const glow = ctx.createRadialGradient(W / 2, -200, 60, W / 2, -200, 900)
  glow.addColorStop(0, 'rgba(222,132,79,0.28)')
  glow.addColorStop(1, 'rgba(222,132,79,0)')
  ctx.fillStyle = glow
  ctx.fillRect(0, 0, W, 700)

  // Wordmark + date
  ctx.fillStyle = EMBER
  ctx.font = "700 44px 'Bricolage Grotesque', 'Onest', sans-serif"
  ctx.textBaseline = 'top'
  ctx.fillText('Forge', PAD, PAD)
  const date = new Date().toLocaleDateString(undefined, {
    day: 'numeric',
    month: 'long',
    year: 'numeric',
  })
  ctx.fillStyle = MUTED
  ctx.font = "500 34px 'Onest', sans-serif"
  ctx.textAlign = 'right'
  ctx.fillText(date, W - PAD, PAD + 8)
  ctx.textAlign = 'left'

  // Workout name — wrap onto two lines max
  ctx.fillStyle = INK
  ctx.font = "700 92px 'Bricolage Grotesque', 'Onest', sans-serif"
  const words = summary.name.split(' ')
  const lines: string[] = []
  let line = ''
  for (const word of words) {
    const probe = line ? `${line} ${word}` : word
    if (ctx.measureText(probe).width > W - PAD * 2 && line) {
      lines.push(line)
      line = word
    } else {
      line = probe
    }
  }
  if (line) lines.push(line)
  let y = 240
  for (const l of lines.slice(0, 2)) {
    ctx.fillText(l, PAD, y)
    y += 108
  }
  y += 24

  // Stat tiles
  const stats: [string, string][] = [
    [formatDuration(summary.duration_seconds), 'Duration'],
    [formatVolume(summary.total_volume, unit), 'Volume'],
    [String(summary.total_sets), 'Sets'],
  ]
  const tileGap = 24
  const tileW = (W - PAD * 2 - tileGap * 2) / 3
  const tileH = 190
  stats.forEach(([value, label], i) => {
    const x = PAD + i * (tileW + tileGap)
    ctx.fillStyle = CARD
    roundRect(ctx, x, y, tileW, tileH, 28)
    ctx.fill()
    ctx.strokeStyle = BORDER
    ctx.lineWidth = 2
    ctx.stroke()
    ctx.fillStyle = INK
    ctx.font = "700 56px 'Onest', sans-serif"
    ctx.fillText(value, x + 36, y + 44)
    ctx.fillStyle = MUTED
    ctx.font = "500 30px 'Onest', sans-serif"
    ctx.fillText(label, x + 36, y + 120)
  })
  y += tileH + 48

  // Volume delta vs last time
  if (summary.comparison && summary.comparison.prev_volume > 0) {
    const delta = Math.round(
      ((summary.total_volume - summary.comparison.prev_volume) / summary.comparison.prev_volume) *
        100,
    )
    if (delta !== 0) {
      ctx.fillStyle = delta > 0 ? EMBER : MUTED
      ctx.font = "600 36px 'Onest', sans-serif"
      ctx.fillText(`${delta > 0 ? '+' : ''}${delta}% volume vs last time`, PAD, y)
      y += 76
    }
  }

  // PRs
  if (summary.prs.length > 0) {
    ctx.fillStyle = MUTED
    ctx.font = "600 30px 'Onest', sans-serif"
    ctx.fillText('PERSONAL RECORDS', PAD, y)
    y += 56
    for (const pr of summary.prs.slice(0, 5)) {
      const rowH = 96
      ctx.fillStyle = CARD
      roundRect(ctx, PAD, y, W - PAD * 2, rowH, 24)
      ctx.fill()
      ctx.strokeStyle = BORDER
      ctx.stroke()
      // PR chip
      ctx.fillStyle = 'rgba(212,168,67,0.16)'
      roundRect(ctx, PAD + 28, y + 26, 88, 44, 22)
      ctx.fill()
      ctx.fillStyle = RECORD
      ctx.font = "700 28px 'Onest', sans-serif"
      ctx.fillText('PR', PAD + 54, y + 34)
      // Exercise + value
      ctx.fillStyle = INK
      ctx.font = "600 36px 'Onest', sans-serif"
      const name =
        pr.exercise_name.length > 26 ? `${pr.exercise_name.slice(0, 25)}…` : pr.exercise_name
      ctx.fillText(name, PAD + 148, y + 30)
      ctx.fillStyle = MUTED
      ctx.textAlign = 'right'
      ctx.font = "500 34px 'Onest', sans-serif"
      const value =
        pr.kind === 'weight'
          ? `${pr.value} ${unit} × ${pr.reps}`
          : pr.kind === '1rm'
            ? `est. 1RM ${pr.value} ${unit}`
            : `${pr.value} reps`
      ctx.fillText(value, W - PAD - 32, y + 32)
      ctx.textAlign = 'left'
      y += rowH + 16
    }
  }

  // Footer
  ctx.fillStyle = MUTED
  ctx.font = "500 30px 'Onest', sans-serif"
  ctx.fillText('Tracked with Forge — self-hosted iron tracking', PAD, H - PAD - 30)

  return canvas
}

export async function shareWorkoutCard(summary: FinishResult, unit: string): Promise<void> {
  // Make sure the display fonts are actually loaded before drawing
  try {
    await Promise.all([
      document.fonts.load("700 92px 'Bricolage Grotesque'"),
      document.fonts.load("600 36px 'Onest'"),
    ])
  } catch {
    // system fallback fonts still render fine
  }
  const canvas = drawCard(summary, unit)
  const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/png'))
  if (!blob) throw new Error('Could not render the card')
  const file = new File([blob], 'workout.png', { type: 'image/png' })

  if (navigator.canShare?.({ files: [file] })) {
    try {
      await navigator.share({ files: [file] })
      return
    } catch (e) {
      // user cancelled the sheet — not an error
      if (e instanceof DOMException && e.name === 'AbortError') return
    }
  }
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = 'workout.png'
  a.click()
  setTimeout(() => URL.revokeObjectURL(url), 10_000)
}
