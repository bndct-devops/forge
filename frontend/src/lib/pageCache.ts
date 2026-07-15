/** Session page cache — render instantly from the last data, revalidate in
 *  the background. Same pattern as the exercise catalogue cache. */
const cache = new Map<string, unknown>()

export function getPageCache<T>(key: string): T | null {
  return (cache.get(key) as T) ?? null
}

export function setPageCache<T>(key: string, value: T) {
  cache.set(key, value)
}
