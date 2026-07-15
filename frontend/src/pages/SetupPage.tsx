import { Flame } from 'lucide-react'
import { useEffect, useState, type FormEvent } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'
import { api } from '../lib/api'

export default function SetupPage() {
  const { setup } = useAuth()
  const navigate = useNavigate()
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [confirm, setConfirm] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    api<{ needs_setup: boolean }>('/auth/setup-status')
      .then((s) => {
        if (!s.needs_setup) navigate('/login', { replace: true })
      })
      .catch(() => {})
  }, [navigate])

  const submit = async (e: FormEvent) => {
    e.preventDefault()
    if (password !== confirm) {
      setError('Passwords do not match')
      return
    }
    setError('')
    setBusy(true)
    try {
      await setup(username, password)
      navigate('/', { replace: true })
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Setup failed')
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
          <h1 className="text-3xl">Welcome to Forge</h1>
          <p className="text-center text-sm text-muted-foreground">
            Create the admin account for this instance
          </p>
        </div>
        <div className="flex flex-col gap-3">
          <input
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            placeholder="Username"
            autoCapitalize="none"
            autoCorrect="off"
            className="h-12 rounded-lg border border-input bg-card px-4 text-base outline-none focus:ring-2 focus:ring-ring"
          />
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="Password (min 4 characters)"
            className="h-12 rounded-lg border border-input bg-card px-4 text-base outline-none focus:ring-2 focus:ring-ring"
          />
          <input
            type="password"
            value={confirm}
            onChange={(e) => setConfirm(e.target.value)}
            placeholder="Confirm password"
            className="h-12 rounded-lg border border-input bg-card px-4 text-base outline-none focus:ring-2 focus:ring-ring"
          />
          {error && <p className="text-sm text-destructive">{error}</p>}
          <button
            type="submit"
            disabled={busy || !username || password.length < 4}
            className="touch-feedback h-12 rounded-lg bg-primary text-base font-semibold text-primary-foreground disabled:opacity-50"
          >
            {busy ? 'Creating…' : 'Create account'}
          </button>
        </div>
      </form>
    </div>
  )
}
