/** Minimal promise wrapper around a single IndexedDB key-value store.
 *  Failures reject; callers (dataCache) decide how to degrade. */

const DB_NAME = 'forge-cache'
const STORE = 'kv'

let dbPromise: Promise<IDBDatabase> | null = null

function openDB(): Promise<IDBDatabase> {
  if (!dbPromise) {
    dbPromise = new Promise((resolve, reject) => {
      const req = indexedDB.open(DB_NAME, 1)
      req.onupgradeneeded = () => req.result.createObjectStore(STORE)
      req.onsuccess = () => resolve(req.result)
      req.onerror = () => reject(req.error)
    })
    // Allow a retry on transient open failures (Safari) instead of caching the rejection
    dbPromise.catch(() => {
      dbPromise = null
    })
  }
  return dbPromise
}

function txDone(tx: IDBTransaction): Promise<void> {
  return new Promise((resolve, reject) => {
    tx.oncomplete = () => resolve()
    tx.onerror = () => reject(tx.error)
    tx.onabort = () => reject(tx.error)
  })
}

export async function idbGetAll(): Promise<Map<string, unknown>> {
  const db = await openDB()
  const store = db.transaction(STORE, 'readonly').objectStore(STORE)
  const [keys, values] = await Promise.all([
    new Promise<IDBValidKey[]>((resolve, reject) => {
      const req = store.getAllKeys()
      req.onsuccess = () => resolve(req.result)
      req.onerror = () => reject(req.error)
    }),
    new Promise<unknown[]>((resolve, reject) => {
      const req = store.getAll()
      req.onsuccess = () => resolve(req.result)
      req.onerror = () => reject(req.error)
    }),
  ])
  const map = new Map<string, unknown>()
  keys.forEach((k, i) => map.set(String(k), values[i]))
  return map
}

export async function idbSet(key: string, value: unknown): Promise<void> {
  const db = await openDB()
  const tx = db.transaction(STORE, 'readwrite')
  tx.objectStore(STORE).put(value, key)
  return txDone(tx)
}

export async function idbDel(key: string): Promise<void> {
  const db = await openDB()
  const tx = db.transaction(STORE, 'readwrite')
  tx.objectStore(STORE).delete(key)
  return txDone(tx)
}

export async function idbClear(): Promise<void> {
  const db = await openDB()
  const tx = db.transaction(STORE, 'readwrite')
  tx.objectStore(STORE).clear()
  return txDone(tx)
}
