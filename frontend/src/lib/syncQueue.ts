/** Queue of whole-workout sync tasks that must survive reloads: workouts
 *  finished (or discarded) while offline. Drained in FIFO order before the
 *  active document syncs, so a finish-then-start-again offline session
 *  replays in the right order. Same localStorage pattern as the outbox. */
import { useSyncExternalStore } from 'react'
import { api, ApiError } from './api'
import type { SyncPayload } from './localWorkout'
import { toast } from './toast'

type SyncTask =
  | { kind: 'finish'; name: string; payload: SyncPayload }
  | { kind: 'discard'; id: number }

const STORAGE_KEY = 'forge_sync_queue'

let queue: SyncTask[] = []
try {
  queue = JSON.parse(localStorage.getItem(STORAGE_KEY) ?? '[]')
} catch {
  queue = []
}

const listeners = new Set<() => void>()
let flushing = false

function persist() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(queue))
  listeners.forEach((l) => l())
}

export const syncQueue = {
  enqueueFinish(payload: SyncPayload, name: string) {
    // Replace a queued finish for the same workout (same client_id) — the
    // latest document wins, replaying both would be redundant
    queue = queue.filter(
      (t) => !(t.kind === 'finish' && t.payload.client_id === payload.client_id),
    )
    queue.push({ kind: 'finish', name, payload })
    persist()
  },

  enqueueDiscard(id: number) {
    queue.push({ kind: 'discard', id })
    persist()
  },

  size(): number {
    return queue.length
  },

  /** Returns true when fully drained. Network errors and 5xx stop the run
   *  (retry later); other API errors drop the task so the queue can't jam. */
  async flush(): Promise<boolean> {
    if (flushing) return queue.length === 0
    flushing = true
    try {
      while (queue.length > 0) {
        const task = queue[0]
        try {
          if (task.kind === 'finish') {
            const res = await api<{ finish: { prs: unknown[] } | null }>('/workouts/sync', {
              method: 'PUT',
              body: task.payload,
            })
            const prCount = res.finish?.prs.length ?? 0
            toast(
              prCount > 0
                ? `"${task.name}" synced — ${prCount} PR${prCount > 1 ? 's' : ''} detected`
                : `"${task.name}" synced`,
              { kind: 'info' },
            )
          } else {
            await api(`/workouts/${task.id}`, { method: 'DELETE' })
          }
        } catch (e) {
          if (e instanceof ApiError && e.status < 500) {
            // 404 discard target already gone, 422 unsyncable document, ... —
            // drop rather than jam the queue forever
            if (task.kind === 'finish') toast(`"${task.name}" could not sync and was skipped`)
          } else {
            return false // offline or server trouble — retry later
          }
        }
        queue.shift()
        persist()
      }
      return true
    } finally {
      flushing = false
    }
  },
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

export function useSyncQueueSize(): number {
  return useSyncExternalStore(subscribe, () => queue.length)
}
