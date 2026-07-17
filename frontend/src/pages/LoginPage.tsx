import { Flame, KeyRound } from 'lucide-react'
import { useEffect, useState, type FormEvent } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'
import { api } from '../lib/api'

const SSO_ERRORS: Record<string, string> = {
  disabled: 'SSO is not configured on this server.',
  exchange: 'The identity provider rejected the sign-in — try again.',
  claims: 'The identity provider sent an incomplete profile.',
  not_allowed: 'Your account is not allowed to sign in here.',
  no_account: 'No Forge account is linked to that identity.',
  already_linked: 'That identity is already linked to another account.',
}

export default function LoginPage() {
  const { login } = useAuth()
  const navigate = useNavigate()
  const [params] = useSearchParams()
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState(() => {
    const code = params.get('sso_error')
    return code ? (SSO_ERRORS[code] ?? 'SSO sign-in failed.') : ''
  })
  const [busy, setBusy] = useState(false)
  const [sso, setSso] = useState<{ enabled: boolean; button_label: string } | null>(null)

  useEffect(() => {
    api<{ enabled: boolean; button_label: string }>('/auth/oidc/config')
      .then(setSso)
      .catch(() => {})
  }, [])

  const submit = async (e: FormEvent) => {
    e.preventDefault()
    setError('')
    setBusy(true)
    try {
      await login(username, password)
      navigate('/', { replace: true })
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Login failed')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="safe-top safe-bottom overscroll-contain flex h-full items-center justify-center overflow-y-auto px-6">
      <form onSubmit={submit} className="animate-card-appear w-full max-w-sm">
        <div className="mb-8 flex flex-col items-center gap-3">
          <div className="flex h-16 w-16 items-center justify-center rounded-2xl bg-primary text-primary-foreground">
            <Flame size={34} />
          </div>
          <h1 className="text-3xl">Forge</h1>
          <p className="text-sm text-muted-foreground">Sign in to keep lifting</p>
        </div>
        <div className="flex flex-col gap-3">
          <input
            autoFocus
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            placeholder="Username"
            autoComplete="username"
            autoCapitalize="none"
            autoCorrect="off"
            className="h-12 rounded-lg border border-input bg-card px-4 text-base outline-none focus:ring-2 focus:ring-ring"
          />
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="Password"
            autoComplete="current-password"
            className="h-12 rounded-lg border border-input bg-card px-4 text-base outline-none focus:ring-2 focus:ring-ring"
          />
          {error && <p className="text-sm text-destructive">{error}</p>}
          <button
            type="submit"
            disabled={busy || !username || !password}
            className="touch-feedback h-12 rounded-lg bg-primary text-base font-semibold text-primary-foreground disabled:opacity-50"
          >
            {busy ? 'Signing in…' : 'Sign in'}
          </button>
          {sso?.enabled && (
            <>
              <div className="flex items-center gap-3 py-1 text-xs text-muted-foreground">
                <div className="h-px flex-1 bg-border" />
                or
                <div className="h-px flex-1 bg-border" />
              </div>
              <button
                type="button"
                onClick={() => {
                  window.location.href = '/api/auth/oidc/login'
                }}
                className="touch-feedback flex h-12 items-center justify-center gap-2 rounded-lg border bg-card text-base font-semibold"
              >
                <KeyRound size={18} className="text-muted-foreground" />
                {sso.button_label}
              </button>
            </>
          )}
        </div>
      </form>
    </div>
  )
}
