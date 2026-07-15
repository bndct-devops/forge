/** Offline outbox for set updates — the one mutation that matters mid-workout.
 *  When a PATCH /sets/{id} fails on a network error, the change is applied
 *  optimistically in the UI and queued here; the queue replays in order when
 *  connectivity returns. Patches to the same set coalesce. */
import { useEffect, useState } from 'react'
import { api, ApiError } from './api'

export interface SetPatch {
  weight?: number | null
  reps?: number | null
  is_completed?: boolean
  is_warmup?: boolean
}

interface QueuedPatch {
  setId: number
  patch: SetPatch
}

const KEY = 'forge_outbox'
const listeners = new Set<() => void>()
let queue: QueuedPatch[] = []
let flushing = false

try {
  queue = JSON.parse(localStorage.getItem(KEY) ?? '[]')
} catch {
  queue = []
}

function persist() {
  localStorage.setItem(KEY, JSON.stringify(queue))
  listeners.forEach((l) => l())
}

export const outbox = {
  add(setId: number, patch: SetPatch) {
    const existing = queue.find((q) => q.setId === setId)
    if (existing) existing.patch = { ...existing.patch, ...patch }
    else queue.push({ setId, patch })
    persist()
  },

  size(): number {
    return queue.length
  },

  /** Replay queued patches in order. Returns true when the queue is empty. */
  async flush(): Promise<boolean> {
    if (flushing) return queue.length === 0
    flushing = true
    try {
      while (queue.length > 0) {
        const item = queue[0]
        try {
          await api(`/sets/${item.setId}`, { method: 'PATCH', body: item.patch })
        } catch (e) {
          if (e instanceof ApiError && e.status === 404) {
            // set was deleted elsewhere — drop the orphaned patch
            queue.shift()
            persist()
            continue
          }
          return false // still offline (or server error) — retry later
        }
        queue.shift()
        persist()
      }
      return true
    } finally {
      flushing = false
    }
  },

  subscribe(listener: () => void): () => void {
    listeners.add(listener)
    return () => listeners.delete(listener)
  },
}

export function useOutboxSize(): number {
  const [size, setSize] = useState(outbox.size())
  useEffect(() => outbox.subscribe(() => setSize(outbox.size())), [])
  return size
}

/** Network failure (offline / unreachable) — as opposed to an HTTP error. */
export function isNetworkError(e: unknown): boolean {
  return e instanceof TypeError
}
