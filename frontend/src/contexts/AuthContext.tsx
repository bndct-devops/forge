import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react'
import { api, clearToken, getToken, setToken } from '../lib/api'
import type { User } from '../lib/types'

interface AuthContextValue {
  user: User | null
  loading: boolean
  login: (username: string, password: string) => Promise<void>
  setup: (username: string, password: string) => Promise<void>
  logout: () => void
  updateUser: (patch: Partial<Pick<User, 'unit' | 'default_rest_seconds' | 'weekly_goal' | 'gap_nudges' | 'deload_hints' | 'plate_config'>> & { password?: string }) => Promise<void>
}

const AuthContext = createContext<AuthContextValue | null>(null)

interface TokenResponse {
  token: string
  user: User
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (!getToken()) {
      setLoading(false)
      return
    }
    api<User>('/auth/me')
      .then(setUser)
      .catch(() => {})
      .finally(() => setLoading(false))
  }, [])

  const login = useCallback(async (username: string, password: string) => {
    const res = await api<TokenResponse>('/auth/login', {
      method: 'POST',
      body: { username, password },
    })
    setToken(res.token)
    setUser(res.user)
  }, [])

  const setup = useCallback(async (username: string, password: string) => {
    const res = await api<TokenResponse>('/auth/setup', {
      method: 'POST',
      body: { username, password },
    })
    setToken(res.token)
    setUser(res.user)
  }, [])

  const logout = useCallback(() => {
    clearToken()
    setUser(null)
    location.href = '/login'
  }, [])

  const updateUser = useCallback<AuthContextValue['updateUser']>(async (patch) => {
    const updated = await api<User>('/auth/me', { method: 'PATCH', body: patch })
    setUser(updated)
  }, [])

  return (
    <AuthContext.Provider value={{ user, loading, login, setup, logout, updateUser }}>
      {children}
    </AuthContext.Provider>
  )
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth outside AuthProvider')
  return ctx
}
