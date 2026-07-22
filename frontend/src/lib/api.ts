import { clearDataCache } from './dataCache'
import type { User } from './types'

const TOKEN_KEY = 'forge_token'
const USER_KEY = 'forge_user'

export function getToken(): string | null {
  return localStorage.getItem(TOKEN_KEY)
}

export function setToken(token: string) {
  localStorage.setItem(TOKEN_KEY, token)
}

export function clearToken() {
  localStorage.removeItem(TOKEN_KEY)
}

/** Last authenticated user, kept so the app stays usable offline where
 *  /auth/me can't be reached. Cleared alongside the token. */
export function getCachedUser(): User | null {
  const raw = localStorage.getItem(USER_KEY)
  if (!raw) return null
  try {
    return JSON.parse(raw) as User
  } catch {
    return null
  }
}

export function setCachedUser(user: User) {
  localStorage.setItem(USER_KEY, JSON.stringify(user))
}

export function clearCachedUser() {
  localStorage.removeItem(USER_KEY)
}

export class ApiError extends Error {
  status: number
  constructor(status: number, detail: string) {
    super(detail)
    this.status = status
  }
}

export async function api<T = unknown>(
  path: string,
  options: { method?: string; body?: unknown } = {},
): Promise<T> {
  const headers: Record<string, string> = {}
  const token = getToken()
  if (token) headers.Authorization = `Bearer ${token}`
  if (options.body !== undefined) headers['Content-Type'] = 'application/json'

  const res = await fetch(`/api${path}`, {
    method: options.method ?? 'GET',
    headers,
    body: options.body !== undefined ? JSON.stringify(options.body) : undefined,
  })

  if (res.status === 401 && !path.startsWith('/auth/login')) {
    clearToken()
    clearCachedUser()
    // Awaited so navigation doesn't abort the IndexedDB clear
    await clearDataCache()
    if (!location.pathname.startsWith('/login')) location.href = '/login'
    throw new ApiError(401, 'Not authenticated')
  }
  if (!res.ok) {
    let detail = res.statusText
    try {
      const data = await res.json()
      if (typeof data.detail === 'string') detail = data.detail
    } catch {
      // non-JSON error body
    }
    throw new ApiError(res.status, detail)
  }
  return res.json() as Promise<T>
}
