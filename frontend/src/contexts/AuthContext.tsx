import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react'
import { api, clearCachedUser, clearToken, getCachedUser, getToken, setCachedUser, setToken } from '../lib/api'
import { clearDataCache } from '../lib/dataCache'
import type { User } from '../lib/types'

interface AuthContextValue {
  user: User | null
  loading: boolean
  login: (username: string, password: string) => Promise<void>
  loginWithToken: (token: string) => Promise<void>
  setup: (username: string, password: string) => Promise<void>
  logout: () => void
  updateUser: (patch: Partial<Pick<User, 'unit' | 'default_rest_seconds' | 'weekly_goal' | 'gap_nudges' | 'deload_hints' | 'weekly_digest' | 'plate_config' | 'webhook_url'>> & { password?: string; webhook_secret?: string }) => Promise<void>
}

const AuthContext = createContext<AuthContextValue | null>(null)

interface TokenResponse {
  token: string
  user: User
}

export function AuthProvider({ children }: { children: ReactNode }) {
  // Trust the cached user while offline; /auth/me revalidates in the background
  const [user, setUser] = useState<User | null>(() => (getToken() ? getCachedUser() : null))
  const [loading, setLoading] = useState(() => getToken() != null && getCachedUser() == null)

  useEffect(() => {
    if (!getToken()) {
      setLoading(false)
      return
    }
    api<User>('/auth/me')
      .then((me) => {
        setUser(me)
        setCachedUser(me)
      })
      .catch(() => {}) // network error: keep the cached user; 401 clears everything in api()
      .finally(() => setLoading(false))
  }, [])

  // Persist the fresh session; drop the previous account's cached data
  const adoptUser = useCallback(async (u: User) => {
    const prev = getCachedUser()
    if (prev && prev.id !== u.id) await clearDataCache()
    setCachedUser(u)
    setUser(u)
  }, [])

  const login = useCallback(async (username: string, password: string) => {
    const res = await api<TokenResponse>('/auth/login', {
      method: 'POST',
      body: { username, password },
    })
    setToken(res.token)
    await adoptUser(res.user)
  }, [adoptUser])

  const loginWithToken = useCallback(async (token: string) => {
    setToken(token)
    const me = await api<User>('/auth/me')
    await adoptUser(me)
  }, [adoptUser])

  const setup = useCallback(async (username: string, password: string) => {
    const res = await api<TokenResponse>('/auth/setup', {
      method: 'POST',
      body: { username, password },
    })
    setToken(res.token)
    await adoptUser(res.user)
  }, [adoptUser])

  const logout = useCallback(() => {
    clearToken()
    clearCachedUser()
    setUser(null)
    clearDataCache().finally(() => {
      location.href = '/login'
    })
  }, [])

  const updateUser = useCallback<AuthContextValue['updateUser']>(async (patch) => {
    const updated = await api<User>('/auth/me', { method: 'PATCH', body: patch })
    setUser(updated)
    setCachedUser(updated)
  }, [])

  return (
    <AuthContext.Provider value={{ user, loading, login, loginWithToken, setup, logout, updateUser }}>
      {children}
    </AuthContext.Provider>
  )
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth outside AuthProvider')
  return ctx
}
