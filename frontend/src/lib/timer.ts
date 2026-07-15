/** Rest timer singleton — survives reloads via localStorage, ticks subscribers,
 *  and fires sound + vibration + notification when time is up. */
import { useEffect, useState } from 'react'
import { syncRestPush } from './push'

const TIMER_KEY = 'forge_rest_timer'
const SOUND_KEY = 'forge_timer_sound'

export function isTimerSoundEnabled(): boolean {
  return localStorage.getItem(SOUND_KEY) !== 'off'
}

export function setTimerSoundEnabled(on: boolean) {
  localStorage.setItem(SOUND_KEY, on ? 'on' : 'off')
}

export interface TimerState {
  endsAt: number
  total: number
}

type Listener = () => void

let state: TimerState | null = null
let interval: ReturnType<typeof setInterval> | null = null
let lastNaturalEnd = 0 // natural completion (not skip) — drives the "go!" state
const listeners = new Set<Listener>()

function load() {
  try {
    const raw = localStorage.getItem(TIMER_KEY)
    if (raw) {
      const parsed = JSON.parse(raw) as TimerState
      if (parsed.endsAt > Date.now()) {
        state = parsed
        ensureTicking()
      } else {
        localStorage.removeItem(TIMER_KEY)
      }
    }
  } catch {
    localStorage.removeItem(TIMER_KEY)
  }
}

function persist() {
  if (state) localStorage.setItem(TIMER_KEY, JSON.stringify(state))
  else localStorage.removeItem(TIMER_KEY)
}

function notify() {
  listeners.forEach((l) => l())
}

function ensureTicking() {
  if (interval == null) {
    interval = setInterval(tick, 250)
  }
}

function stopTicking() {
  if (interval != null) {
    clearInterval(interval)
    interval = null
  }
}

function tick() {
  if (!state) {
    stopTicking()
    return
  }
  if (state.endsAt <= Date.now()) {
    state = null
    lastNaturalEnd = Date.now()
    persist()
    stopTicking()
    fireDone()
  }
  notify()
}

function fireDone() {
  try {
    navigator.vibrate?.([200, 100, 200, 100, 400])
  } catch {
    // vibration unsupported
  }
  beep()
  if (document.hidden && 'Notification' in window && Notification.permission === 'granted') {
    try {
      new Notification('Rest over', { body: 'Time for your next set.' })
    } catch {
      // notification construction can throw on some platforms
    }
  }
}

function beep() {
  if (!isTimerSoundEnabled()) return
  try {
    const Ctx = window.AudioContext ?? (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext
    const ctx = new Ctx()
    const at = (t: number, freq: number) => {
      const osc = ctx.createOscillator()
      const gain = ctx.createGain()
      osc.type = 'sine'
      osc.frequency.value = freq
      gain.gain.setValueAtTime(0.001, ctx.currentTime + t)
      gain.gain.exponentialRampToValueAtTime(0.35, ctx.currentTime + t + 0.02)
      gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + t + 0.28)
      osc.connect(gain).connect(ctx.destination)
      osc.start(ctx.currentTime + t)
      osc.stop(ctx.currentTime + t + 0.3)
    }
    at(0, 880)
    at(0.35, 880)
    at(0.7, 1175)
    setTimeout(() => ctx.close(), 1500)
  } catch {
    // audio unsupported
  }
}

export const restTimer = {
  start(seconds: number) {
    if (seconds <= 0) return
    if ('Notification' in window && Notification.permission === 'default') {
      Notification.requestPermission().catch(() => {})
    }
    state = { endsAt: Date.now() + seconds * 1000, total: seconds }
    persist()
    ensureTicking()
    notify()
    syncRestPush(state.endsAt) // lock-screen alert via server push (HTTPS only)
  },
  adjust(deltaSeconds: number) {
    if (!state) return
    const remaining = Math.max(0, state.endsAt - Date.now()) / 1000
    const next = Math.max(1, remaining + deltaSeconds)
    state = { endsAt: Date.now() + next * 1000, total: Math.max(state.total + deltaSeconds, next) }
    persist()
    notify()
    syncRestPush(state.endsAt)
  },
  skip() {
    state = null
    persist()
    stopTicking()
    notify()
    syncRestPush(null)
  },
  get(): { remaining: number; total: number } | null {
    if (!state) return null
    return { remaining: Math.max(0, (state.endsAt - Date.now()) / 1000), total: state.total }
  },
  lastNaturalEnd(): number {
    return lastNaturalEnd
  },
  subscribe(listener: Listener): () => void {
    listeners.add(listener)
    return () => listeners.delete(listener)
  },
}

load()

export function useRestTimer() {
  const [, setVersion] = useState(0)
  useEffect(() => restTimer.subscribe(() => setVersion((v) => v + 1)), [])
  return restTimer.get()
}
