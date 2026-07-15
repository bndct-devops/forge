import { Download, KeyRound, LogOut, Minus, Plus, Shield, Trash2, Upload, UserPlus } from 'lucide-react'
import { useEffect, useRef, useState } from 'react'
import { getToken } from '../lib/api'
import Segmented from '../components/Segmented'
import Sheet from '../components/Sheet'
import { useAuth } from '../contexts/AuthContext'
import { api } from '../lib/api'
import { restLabel } from '../lib/format'
import { applyTheme, getStoredTheme, THEMES, type ThemeId } from '../lib/theme'
import type { User } from '../lib/types'

/** Live viewport readout — diagnoses iOS webview sizing issues on-device. */
function ViewportDebug() {
  const [info, setInfo] = useState('')
  useEffect(() => {
    const update = () => {
      const vv = window.visualViewport
      const standalone =
        window.matchMedia('(display-mode: standalone)').matches ||
        (navigator as unknown as { standalone?: boolean }).standalone
      const appH = document.documentElement.style.getPropertyValue('--app-h') || '—'
      setInfo(
        `${standalone ? 'standalone' : 'browser'} · screen ${screen.height} · inner ${window.innerHeight} · vv ${vv ? Math.round(vv.height) : '—'}+${vv ? Math.round(vv.offsetTop) : 0} · app ${appH}`,
      )
    }
    update()
    window.visualViewport?.addEventListener('resize', update)
    const t = setInterval(update, 2000)
    return () => {
      window.visualViewport?.removeEventListener('resize', update)
      clearInterval(t)
    }
  }, [])
  return <p className="tnum mt-1 text-center text-[10px] text-muted-foreground/60">{info}</p>
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="mt-6">
      <h2 className="mb-2 px-1 text-sm font-semibold tracking-wide text-muted-foreground uppercase">
        {title}
      </h2>
      <div className="flex flex-col gap-px overflow-hidden rounded-xl border bg-card">{children}</div>
    </section>
  )
}

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex min-h-12 items-center justify-between gap-3 px-4 py-2.5">
      <span className="font-medium">{label}</span>
      {children}
    </div>
  )
}

export default function SettingsPage() {
  const { user, logout, updateUser } = useAuth()
  const [theme, setTheme] = useState<ThemeId>(getStoredTheme())
  const [users, setUsers] = useState<User[]>([])
  const [addUserOpen, setAddUserOpen] = useState(false)
  const [passwordOpen, setPasswordOpen] = useState(false)
  const [newUsername, setNewUsername] = useState('')
  const [newUserPassword, setNewUserPassword] = useState('')
  const [newUserAdmin, setNewUserAdmin] = useState(false)
  const [newPassword, setNewPassword] = useState('')
  const [message, setMessage] = useState('')
  const [error, setError] = useState('')
  const [importing, setImporting] = useState(false)
  const fileInput = useRef<HTMLInputElement>(null)

  useEffect(() => {
    if (user?.is_admin) {
      api<User[]>('/users').then(setUsers).catch(() => {})
    }
  }, [user?.is_admin])

  if (!user) return null

  const changeTheme = (t: ThemeId) => {
    setTheme(t)
    applyTheme(t)
  }

  const adjustRest = (delta: number) => {
    const next = Math.max(0, Math.min(600, user.default_rest_seconds + delta))
    updateUser({ default_rest_seconds: next }).catch(() => {})
  }

  const addUser = async () => {
    setError('')
    try {
      const created = await api<User>('/users', {
        method: 'POST',
        body: { username: newUsername, password: newUserPassword, is_admin: newUserAdmin },
      })
      setUsers((us) => [...us, created])
      setAddUserOpen(false)
      setNewUsername('')
      setNewUserPassword('')
      setNewUserAdmin(false)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to create user')
    }
  }

  const removeUser = async (id: number) => {
    await api(`/users/${id}`, { method: 'DELETE' })
    setUsers((us) => us.filter((u) => u.id !== id))
  }

  const importStrong = async (file: File) => {
    setImporting(true)
    setMessage('')
    setError('')
    try {
      const form = new FormData()
      form.append('file', file)
      const res = await fetch('/api/import/strong', {
        method: 'POST',
        headers: { Authorization: `Bearer ${getToken()}` },
        body: form,
      })
      const data = await res.json()
      if (!res.ok) throw new Error(typeof data.detail === 'string' ? data.detail : 'Import failed')
      setMessage(
        `Imported ${data.imported_workouts} workouts (${data.imported_sets} sets, ` +
          `${data.created_exercises} new exercises, ${data.skipped_workouts} duplicates skipped)`,
      )
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Import failed')
    } finally {
      setImporting(false)
      if (fileInput.current) fileInput.current.value = ''
    }
  }

  const exportCsv = async () => {
    const res = await fetch('/api/export/strong', {
      headers: { Authorization: `Bearer ${getToken()}` },
    })
    const blob = await res.blob()
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = 'forge_export.csv'
    a.click()
    URL.revokeObjectURL(url)
  }

  const changePassword = async () => {
    setError('')
    try {
      await updateUser({ password: newPassword })
      setPasswordOpen(false)
      setNewPassword('')
      setMessage('Password updated')
      setTimeout(() => setMessage(''), 3000)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to update password')
    }
  }

  return (
    <div className="safe-top px-4 pb-8 md:max-w-2xl">
      <header className="pt-6 pb-2">
        <h1 className="text-3xl">Settings</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Signed in as <span className="font-medium text-foreground">{user.username}</span>
          {user.is_admin && (
            <span className="ml-2 inline-flex items-center gap-1 rounded-full bg-accent-soft px-2 py-0.5 text-xs font-semibold text-primary">
              <Shield size={11} /> Admin
            </span>
          )}
        </p>
      </header>

      {message && <p className="mt-2 text-sm text-success">{message}</p>}

      <Section title="Appearance">
        <Row label="Theme">
          <Segmented<ThemeId>
            options={THEMES.map((t) => ({ value: t.id, label: t.label }))}
            value={theme}
            onChange={changeTheme}
            className="w-56"
          />
        </Row>
      </Section>

      <Section title="Training">
        <Row label="Unit">
          <Segmented<'kg' | 'lb'>
            options={[
              { value: 'kg', label: 'kg' },
              { value: 'lb', label: 'lb' },
            ]}
            value={user.unit}
            onChange={(unit) => updateUser({ unit }).catch(() => {})}
            className="w-32"
          />
        </Row>
        <Row label="Default rest timer">
          <div className="flex items-center gap-2">
            <button
              onClick={() => adjustRest(-15)}
              className="touch-feedback rounded-lg bg-secondary p-2"
              aria-label="Less rest"
            >
              <Minus size={15} />
            </button>
            <span className="tnum w-12 text-center font-semibold">
              {restLabel(user.default_rest_seconds)}
            </span>
            <button
              onClick={() => adjustRest(15)}
              className="touch-feedback rounded-lg bg-secondary p-2"
              aria-label="More rest"
            >
              <Plus size={15} />
            </button>
          </div>
        </Row>
      </Section>

      <Section title="Data">
        <button
          onClick={() => fileInput.current?.click()}
          disabled={importing}
          className="touch-feedback flex min-h-12 items-center gap-3 px-4 py-2.5 text-left font-medium hover:bg-secondary disabled:opacity-50"
        >
          <Upload size={18} className="text-muted-foreground" />
          {importing ? 'Importing…' : 'Import from Strong (CSV)'}
        </button>
        <input
          ref={fileInput}
          type="file"
          accept=".csv,text/csv"
          className="hidden"
          onChange={(e) => {
            const file = e.target.files?.[0]
            if (file) importStrong(file)
          }}
        />
        <button
          onClick={exportCsv}
          className="touch-feedback flex min-h-12 items-center gap-3 border-t px-4 py-2.5 text-left font-medium hover:bg-secondary"
        >
          <Download size={18} className="text-muted-foreground" /> Export workouts (CSV)
        </button>
      </Section>

      <Section title="Account">
        <button
          onClick={() => setPasswordOpen(true)}
          className="touch-feedback flex min-h-12 items-center gap-3 px-4 py-2.5 text-left font-medium hover:bg-secondary"
        >
          <KeyRound size={18} className="text-muted-foreground" /> Change password
        </button>
        <button
          onClick={logout}
          className="touch-feedback flex min-h-12 items-center gap-3 border-t px-4 py-2.5 text-left font-medium text-destructive hover:bg-secondary"
        >
          <LogOut size={18} /> Sign out
        </button>
      </Section>

      {user.is_admin && (
        <Section title="Users">
          {users.map((u) => (
            <div key={u.id} className="flex min-h-12 items-center justify-between gap-3 border-b px-4 py-2.5 last:border-b-0">
              <span className="font-medium">
                {u.username}
                {u.is_admin && (
                  <span className="ml-2 text-xs font-semibold text-primary">admin</span>
                )}
              </span>
              {u.id !== user.id && (
                <button
                  onClick={() => removeUser(u.id)}
                  className="touch-feedback rounded-full p-2 text-muted-foreground"
                  aria-label={`Delete ${u.username}`}
                >
                  <Trash2 size={16} />
                </button>
              )}
            </div>
          ))}
          <button
            onClick={() => setAddUserOpen(true)}
            className="touch-feedback flex min-h-12 items-center gap-3 px-4 py-2.5 text-left font-medium text-primary hover:bg-secondary"
          >
            <UserPlus size={18} /> Add user
          </button>
        </Section>
      )}

      <p className="mt-8 text-center text-xs text-muted-foreground">
        Forge · self-hosted iron tracking · build {__BUILD__}
      </p>
      <ViewportDebug />

      <Sheet open={addUserOpen} onClose={() => setAddUserOpen(false)} title="Add user">
        <div className="flex flex-col gap-3 pt-1">
          <input
            value={newUsername}
            onChange={(e) => setNewUsername(e.target.value)}
            placeholder="Username"
            autoCapitalize="none"
            className="h-12 rounded-lg border border-input bg-card px-4 text-base outline-none focus:ring-2 focus:ring-ring"
          />
          <input
            type="password"
            value={newUserPassword}
            onChange={(e) => setNewUserPassword(e.target.value)}
            placeholder="Password (min 4 characters)"
            className="h-12 rounded-lg border border-input bg-card px-4 text-base outline-none focus:ring-2 focus:ring-ring"
          />
          <label className="flex items-center gap-2 px-1 text-sm font-medium">
            <input
              type="checkbox"
              checked={newUserAdmin}
              onChange={(e) => setNewUserAdmin(e.target.checked)}
              className="h-4 w-4 accent-[var(--primary)]"
            />
            Admin
          </label>
          {error && <p className="text-sm text-destructive">{error}</p>}
          <button
            onClick={addUser}
            disabled={!newUsername.trim() || newUserPassword.length < 4}
            className="touch-feedback h-12 rounded-xl bg-primary font-semibold text-primary-foreground disabled:opacity-50"
          >
            Create user
          </button>
        </div>
      </Sheet>

      <Sheet open={passwordOpen} onClose={() => setPasswordOpen(false)} title="Change password">
        <div className="flex flex-col gap-3 pt-1">
          <input
            type="password"
            value={newPassword}
            onChange={(e) => setNewPassword(e.target.value)}
            placeholder="New password (min 4 characters)"
            className="h-12 rounded-lg border border-input bg-card px-4 text-base outline-none focus:ring-2 focus:ring-ring"
          />
          {error && <p className="text-sm text-destructive">{error}</p>}
          <button
            onClick={changePassword}
            disabled={newPassword.length < 4}
            className="touch-feedback h-12 rounded-xl bg-primary font-semibold text-primary-foreground disabled:opacity-50"
          >
            Update password
          </button>
        </div>
      </Sheet>
    </div>
  )
}
