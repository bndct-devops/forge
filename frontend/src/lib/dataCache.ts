/** Durable page-data cache — render instantly from the last synced data,
 *  revalidate in the background, and survive reloads while offline.
 *
 *  Synchronous reads come from an in-memory Map hydrated once from IndexedDB
 *  before first render (see main.tsx); writes go through to IndexedDB
 *  fire-and-forget. A failed or unavailable IndexedDB degrades to the old
 *  session-only cache behavior. */
import { useCallback, useState } from 'react'
import { idbClear, idbDel, idbGetAll, idbSet } from './idb'

// Bump when the shape of cached values changes incompatibly
const CACHE_VERSION = 1
const VERSION_KEY = '__v'

const cache = new Map<string, unknown>()
let hydrated = false

export async function hydrateDataCache(): Promise<void> {
  if (hydrated) return
  hydrated = true
  const timeout = new Promise<null>((resolve) => setTimeout(() => resolve(null), 1500))
  try {
    const stored = await Promise.race([idbGetAll(), timeout])
    if (!stored) return
    if (stored.get(VERSION_KEY) !== CACHE_VERSION) {
      await idbClear()
      idbSet(VERSION_KEY, CACHE_VERSION).catch(() => {})
      return
    }
    for (const [key, value] of stored) {
      if (key !== VERSION_KEY) cache.set(key, value)
    }
  } catch {
    // IndexedDB unavailable (private mode, quota, ...) — start empty
  }
}

export function getCached<T>(key: string): T | null {
  return (cache.get(key) as T) ?? null
}

export function setCached<T>(key: string, value: T) {
  cache.set(key, value)
  idbSet(key, value).catch(() => {})
}

export function delCached(key: string) {
  cache.delete(key)
  idbDel(key).catch(() => {})
}

export async function clearDataCache(): Promise<void> {
  cache.clear()
  // Awaited so callers that navigate right after don't abort the transaction
  await idbClear().catch(() => {})
}

/** Like useState, but initialized from the cache and writing every update
 *  through to it. Pages keep their own fetch effects. */
export function useCachedState<T>(
  key: string,
  fallback: T,
): [T, (next: T | ((prev: T) => T)) => void] {
  const [value, setValue] = useState<T>(() => getCached<T>(key) ?? fallback)
  const set = useCallback(
    (next: T | ((prev: T) => T)) => {
      setValue((prev) => {
        const resolved = typeof next === 'function' ? (next as (p: T) => T)(prev) : next
        setCached(key, resolved)
        return resolved
      })
    },
    [key],
  )
  return [value, set]
}
