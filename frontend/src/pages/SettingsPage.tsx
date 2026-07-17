import { DatabaseBackup, Download, KeyRound, LogOut, Minus, Plus, Shield, Tags, Trash2, Upload, UserPlus } from 'lucide-react'
import { useEffect, useRef, useState } from 'react'
import { api, getToken } from '../lib/api'
import { MUSCLE_GROUPS } from '../components/ExerciseForm'
import type { Exercise } from '../lib/types'
import ConfirmSheet from '../components/ConfirmSheet'
import Segmented from '../components/Segmented'
import Sheet from '../components/Sheet'
import { useAuth } from '../contexts/AuthContext'
import { restLabel } from '../lib/format'
import { disableRestPush, enableRestPush, pushEnabled, pushSupported } from '../lib/push'
import { isRpeEnabled, setRpeEnabled } from '../lib/prefs'
import { toast } from '../lib/toast'
import { isTimerSoundEnabled, setTimerSoundEnabled } from '../lib/timer'
import { applyTheme, getStoredTheme, THEMES, type ThemeId } from '../lib/theme'
import type { User } from '../lib/types'

/** Bulk muscle-group fixer — imported exercises mostly land in 'Other'. */
function RecategorizeSheet({ open, onClose }: { open: boolean; onClose: () => void }) {
  const [exercises, setExercises] = useState<Exercise[]>([])
  const [changes, setChanges] = useState<Record<number, string>>({})
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    if (open) {
      setChanges({})
      api<Exercise[]>('/exercises')
        .then((all) =>
          setExercises(
            all
              .filter((e) => e.is_custom)
              .sort((a, b) =>
                a.muscle_group === b.muscle_group
                  ? a.name.localeCompare(b.name)
                  : a.muscle_group === 'Other'
                    ? -1
                    : b.muscle_group === 'Other'
                      ? 1
                      : a.muscle_group.localeCompare(b.muscle_group),
              ),
          ),
        )
        .catch(() => {})
    }
  }, [open])

  const changed = Object.keys(changes).length

  const save = async () => {
    setSaving(true)
    try {
      await api('/exercises/recategorize', {
        method: 'POST',
        body: { items: Object.entries(changes).map(([id, muscle_group]) => ({ id: Number(id), muscle_group })) },
      })
      onClose()
    } finally {
      setSaving(false)
    }
  }

  return (
    <Sheet open={open} onClose={onClose} title="Re-categorize exercises" full>
      {exercises.length === 0 ? (
        <p className="py-8 text-center text-sm text-muted-foreground">
          No custom exercises yet — imported and self-created exercises show up here.
        </p>
      ) : (
        <>
          <p className="mb-2 text-sm text-muted-foreground">
            Fix muscle groups in one pass — imports land in “Other”.
          </p>
          <div className="divide-y divide-border">
            {exercises.map((e) => (
              <div key={e.id} className="flex items-center justify-between gap-3 py-2.5">
                <span className="min-w-0 truncate font-medium">{e.name}</span>
                <select
                  value={changes[e.id] ?? e.muscle_group}
                  onChange={(ev) => setChanges((c) => ({ ...c, [e.id]: ev.target.value }))}
                  className="h-9 shrink-0 rounded-lg border border-input bg-card px-2 text-sm outline-none"
                >
                  {MUSCLE_GROUPS.map((g) => (
                    <option key={g}>{g}</option>
                  ))}
                </select>
              </div>
            ))}
          </div>
          <button
            onClick={save}
            disabled={changed === 0 || saving}
            className="touch-feedback sticky bottom-0 mt-3 h-12 w-full rounded-xl bg-primary font-semibold text-primary-foreground disabled:opacity-50"
          >
            {saving ? 'Saving…' : changed ? `Save ${changed} change${changed > 1 ? 's' : ''}` : 'No changes'}
          </button>
        </>
      )}
    </Sheet>
  )
}

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

function cnAccountRow(afterSso: boolean): string {
  return afterSso
    ? 'touch-feedback flex min-h-12 items-center gap-3 border-t px-4 py-2.5 text-left font-medium hover:bg-secondary'
    : 'touch-feedback flex min-h-12 items-center gap-3 px-4 py-2.5 text-left font-medium hover:bg-secondary'
}

function cnPush(on: boolean): string {
  return on
    ? 'touch-feedback rounded-lg bg-accent-soft px-4 py-2 text-sm font-semibold text-primary'
    : 'touch-feedback rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-50'
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
  const [timerSound, setTimerSound] = useState(isTimerSoundEnabled())
  const [rpe, setRpe] = useState(isRpeEnabled())
  const [restPush, setRestPush] = useState(pushEnabled())
  const [pushBusy, setPushBusy] = useState(false)
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
  const [recategorizing, setRecategorizing] = useState(false)
  const [deleteUserTarget, setDeleteUserTarget] = useState<User | null>(null)
  const [resetTarget, setResetTarget] = useState<User | null>(null)
  const [resetPassword, setResetPassword] = useState('')
  const [serverVersion, setServerVersion] = useState('')
  const [updateInfo, setUpdateInfo] = useState<{ latest: string | null; update_available: boolean } | null>(null)
  const [checkingUpdate, setCheckingUpdate] = useState(false)
  const [upToDate, setUpToDate] = useState(false)
  const [backupInfo, setBackupInfo] = useState<{
    nightly_enabled: boolean
    keep: number
    latest: string | null
  } | null>(null)
  const fileInput = useRef<HTMLInputElement>(null)
  const hevyInput = useRef<HTMLInputElement>(null)
  const [ssoConfig, setSsoConfig] = useState<{ enabled: boolean; button_label: string } | null>(
    null,
  )

  useEffect(() => {
    if (user?.is_admin) {
      api<User[]>('/users').then(setUsers).catch(() => {})
    }
  }, [user?.is_admin])

  useEffect(() => {
    api<{ version: string }>('/health')
      .then((h) => setServerVersion(h.version))
      .catch(() => {})
    api<{ latest: string | null; update_available: boolean }>('/update-check')
      .then(setUpdateInfo)
      .catch(() => {})
  }, [])

  useEffect(() => {
    if (!user?.is_admin) return
    api<{ nightly_enabled: boolean; keep: number; latest: string | null }>('/backup/settings')
      .then(setBackupInfo)
      .catch(() => {})
  }, [user?.is_admin])

  useEffect(() => {
    api<{ enabled: boolean; button_label: string }>('/auth/oidc/config')
      .then(setSsoConfig)
      .catch(() => {})
    const params = new URLSearchParams(window.location.search)
    if (params.get('sso_linked')) setMessage('SSO linked — you can sign in with it from now on')
    if (params.get('sso_error') === 'already_linked')
      setError('That identity is already linked to another account')
    if (params.get('sso_linked') || params.get('sso_error'))
      history.replaceState(null, '', window.location.pathname)
  }, [])

  if (!user) return null

  const changeTheme = (t: ThemeId) => {
    setTheme(t)
    applyTheme(t)
  }

  const checkForUpdates = async () => {
    setCheckingUpdate(true)
    setUpToDate(false)
    try {
      const info = await api<{ latest: string | null; update_available: boolean }>(
        '/update-check?force=true',
      )
      setUpdateInfo(info)
      if (!info.update_available) {
        setUpToDate(true)
        setTimeout(() => setUpToDate(false), 4000)
      }
    } catch {
      // offline or dev build — nothing to report
    }
    setCheckingUpdate(false)
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

  const importCsv = async (source: 'strong' | 'hevy', file: File) => {
    setImporting(true)
    setMessage('')
    setError('')
    try {
      const form = new FormData()
      form.append('file', file)
      const res = await fetch(`/api/import/${source}`, {
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
      if (hevyInput.current) hevyInput.current.value = ''
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
      {error && <p className="mt-2 text-sm text-destructive">{error}</p>}

      {updateInfo?.update_available && (
        <div className="mt-4 flex items-center gap-3 rounded-xl border border-primary/40 bg-accent-soft p-3.5">
          <Download size={18} className="shrink-0 text-primary" />
          <p className="text-sm">
            <span className="font-semibold">{updateInfo.latest}</span> is available — update the
            container to get it (running {serverVersion}).
          </p>
        </div>
      )}

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
        <Row label="Timer sound">
          <Segmented<'on' | 'off'>
            options={[
              { value: 'on', label: 'On' },
              { value: 'off', label: 'Off' },
            ]}
            value={timerSound ? 'on' : 'off'}
            onChange={(v) => {
              setTimerSound(v === 'on')
              setTimerSoundEnabled(v === 'on')
            }}
            className="w-32"
          />
        </Row>
        <Row label="Weekly goal">
          <div className="flex items-center gap-2">
            <button
              onClick={() => updateUser({ weekly_goal: Math.max(1, user.weekly_goal - 1) }).catch(() => {})}
              className="touch-feedback rounded-lg bg-secondary p-2"
              aria-label="Lower goal"
            >
              <Minus size={15} />
            </button>
            <span className="tnum w-16 text-center font-semibold">
              {user.weekly_goal}×/week
            </span>
            <button
              onClick={() => updateUser({ weekly_goal: Math.min(7, user.weekly_goal + 1) }).catch(() => {})}
              className="touch-feedback rounded-lg bg-secondary p-2"
              aria-label="Raise goal"
            >
              <Plus size={15} />
            </button>
          </div>
        </Row>
        <Row label="Training nudges">
          <Segmented<'on' | 'off'>
            options={[
              { value: 'on', label: 'On' },
              { value: 'off', label: 'Off' },
            ]}
            value={user.gap_nudges ? 'on' : 'off'}
            onChange={(v) => updateUser({ gap_nudges: v === 'on' }).catch(() => {})}
            className="w-32"
          />
        </Row>
        <Row label="Deload hints">
          <Segmented<'on' | 'off'>
            options={[
              { value: 'on', label: 'On' },
              { value: 'off', label: 'Off' },
            ]}
            value={user.deload_hints ? 'on' : 'off'}
            onChange={(v) => updateUser({ deload_hints: v === 'on' }).catch(() => {})}
            className="w-32"
          />
        </Row>
        <Row label="Track RPE">
          <Segmented<'on' | 'off'>
            options={[
              { value: 'on', label: 'On' },
              { value: 'off', label: 'Off' },
            ]}
            value={rpe ? 'on' : 'off'}
            onChange={(v) => {
              setRpe(v === 'on')
              setRpeEnabled(v === 'on')
            }}
            className="w-32"
          />
        </Row>
        <Row label="Rest alerts (lock screen)">
          {pushSupported() ? (
            <button
              onClick={async () => {
                setPushBusy(true)
                setError('')
                try {
                  if (restPush) {
                    await disableRestPush()
                    setRestPush(false)
                  } else {
                    const result = await enableRestPush()
                    if (result === 'enabled') setRestPush(true)
                    else if (result === 'denied')
                      setError('Notifications are blocked for Forge in system settings')
                  }
                } catch {
                  setError('Could not set up push notifications')
                } finally {
                  setPushBusy(false)
                }
              }}
              disabled={pushBusy}
              className={cnPush(restPush)}
            >
              {pushBusy ? 'Working…' : restPush ? 'On' : 'Enable'}
            </button>
          ) : (
            <span className="text-sm text-muted-foreground">Needs HTTPS</span>
          )}
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
            if (file) importCsv('strong', file)
          }}
        />
        <button
          onClick={() => hevyInput.current?.click()}
          disabled={importing}
          className="touch-feedback flex min-h-12 items-center gap-3 border-t px-4 py-2.5 text-left font-medium hover:bg-secondary disabled:opacity-50"
        >
          <Upload size={18} className="text-muted-foreground" />
          {importing ? 'Importing…' : 'Import from Hevy (CSV)'}
        </button>
        <input
          ref={hevyInput}
          type="file"
          accept=".csv,text/csv"
          className="hidden"
          onChange={(e) => {
            const file = e.target.files?.[0]
            if (file) importCsv('hevy', file)
          }}
        />
        <button
          onClick={exportCsv}
          className="touch-feedback flex min-h-12 items-center gap-3 border-t px-4 py-2.5 text-left font-medium hover:bg-secondary"
        >
          <Download size={18} className="text-muted-foreground" /> Export workouts (CSV)
        </button>
        <button
          onClick={() => setRecategorizing(true)}
          className="touch-feedback flex min-h-12 items-center gap-3 border-t px-4 py-2.5 text-left font-medium hover:bg-secondary"
        >
          <Tags size={18} className="text-muted-foreground" /> Re-categorize exercises
        </button>
        {user.is_admin && (
          <button
            onClick={async () => {
              const res = await fetch('/api/backup', {
                headers: { Authorization: `Bearer ${getToken()}` },
              })
              if (!res.ok) return
              const blob = await res.blob()
              const url = URL.createObjectURL(blob)
              const a = document.createElement('a')
              a.href = url
              a.download = res.headers.get('content-disposition')?.match(/filename="?([^";]+)/)?.[1] ?? 'forge-backup.db'
              a.click()
              URL.revokeObjectURL(url)
            }}
            className="touch-feedback flex min-h-12 items-center gap-3 border-t px-4 py-2.5 text-left font-medium hover:bg-secondary"
          >
            <DatabaseBackup size={18} className="text-muted-foreground" /> Download database backup
          </button>
        )}
        {user.is_admin && backupInfo && (
          <div className="border-t">
            <Row label="Nightly backups">
              <Segmented<'on' | 'off'>
                options={[
                  { value: 'on', label: 'On' },
                  { value: 'off', label: 'Off' },
                ]}
                value={backupInfo.nightly_enabled ? 'on' : 'off'}
                onChange={(v) => {
                  const nightly_enabled = v === 'on'
                  setBackupInfo({ ...backupInfo, nightly_enabled })
                  api('/backup/settings', { method: 'PUT', body: { nightly_enabled } }).catch(() =>
                    toast('Could not save the backup setting'),
                  )
                }}
                className="w-32"
              />
            </Row>
            <p className="px-4 pb-3 text-xs text-muted-foreground">
              Daily snapshot to <span className="tnum">/data/backups</span>, keeping the last{' '}
              {backupInfo.keep}.
              {backupInfo.latest && (
                <>
                  {' '}
                  Latest: <span className="tnum">{backupInfo.latest}</span>
                </>
              )}
            </p>
          </div>
        )}
      </Section>

      <Section title="Account">
        {ssoConfig?.enabled && (
          <button
            onClick={async () => {
              if (user.oidc_linked) {
                try {
                  await api('/auth/oidc/unlink', { method: 'POST' })
                  await updateUser({})
                  setMessage('SSO unlinked')
                } catch {
                  setError('Could not unlink SSO')
                }
              } else {
                try {
                  await api('/auth/oidc/link/start', { method: 'POST' })
                  window.location.href = '/api/auth/oidc/login'
                } catch {
                  setError('Could not start SSO linking')
                }
              }
            }}
            className="touch-feedback flex min-h-12 items-center gap-3 px-4 py-2.5 text-left font-medium hover:bg-secondary"
          >
            <Shield size={18} className="text-muted-foreground" />
            {user.oidc_linked ? 'Unlink SSO sign-in' : 'Link SSO sign-in'}
          </button>
        )}
        <button
          onClick={() => setPasswordOpen(true)}
          className={cnAccountRow(ssoConfig?.enabled ?? false)}
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
                <span className="flex items-center">
                  <button
                    onClick={() => {
                      setResetTarget(u)
                      setResetPassword('')
                      setError('')
                    }}
                    className="touch-feedback rounded-full p-2 text-muted-foreground"
                    aria-label={`Reset password for ${u.username}`}
                  >
                    <KeyRound size={16} />
                  </button>
                  <button
                    onClick={() => setDeleteUserTarget(u)}
                    className="touch-feedback rounded-full p-2 text-muted-foreground"
                    aria-label={`Delete ${u.username}`}
                  >
                    <Trash2 size={16} />
                  </button>
                </span>
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

      <Sheet open={resetTarget != null} onClose={() => setResetTarget(null)} title={`Reset password — ${resetTarget?.username}`}>
        <div className="flex flex-col gap-3 pt-1">
          <input
            type="password"
            value={resetPassword}
            onChange={(e) => setResetPassword(e.target.value)}
            placeholder="New password (min 8 characters)"
            className="h-12 rounded-lg border border-input bg-card px-4 text-base outline-none focus:ring-2 focus:ring-ring"
          />
          {error && <p className="text-sm text-destructive">{error}</p>}
          <button
            onClick={async () => {
              setError('')
              try {
                await api(`/users/${resetTarget!.id}/password`, {
                  method: 'PATCH',
                  body: { password: resetPassword },
                })
                setResetTarget(null)
                setMessage(`Password reset for ${resetTarget!.username}`)
                setTimeout(() => setMessage(''), 3000)
              } catch (e) {
                setError(e instanceof Error ? e.message : 'Failed to reset password')
              }
            }}
            disabled={resetPassword.length < 8}
            className="touch-feedback h-12 rounded-xl bg-primary font-semibold text-primary-foreground disabled:opacity-50"
          >
            Reset password
          </button>
        </div>
      </Sheet>

      <p className="mt-8 text-center text-xs text-muted-foreground">
        Forge {serverVersion && serverVersion !== 'dev' ? serverVersion : ''} · self-hosted iron tracking · build {__BUILD__}
      </p>
      <button
        onClick={checkForUpdates}
        disabled={checkingUpdate}
        className="touch-feedback mx-auto mt-1 block rounded-md px-3 py-1.5 text-center text-xs font-medium text-primary"
      >
        {checkingUpdate
          ? 'Checking…'
          : updateInfo?.update_available
            ? `${updateInfo.latest} is available`
            : upToDate
              ? "You're on the latest version"
              : 'Check for updates'}
      </button>
      <ViewportDebug />

      <ConfirmSheet
        open={deleteUserTarget != null}
        onClose={() => setDeleteUserTarget(null)}
        title={`Delete ${deleteUserTarget?.username}?`}
        message="This permanently deletes the account with all of its workouts, templates, and history."
        actionLabel="Delete user"
        destructive
        onConfirm={() => {
          if (deleteUserTarget) removeUser(deleteUserTarget.id)
          setDeleteUserTarget(null)
        }}
      />

      <RecategorizeSheet open={recategorizing} onClose={() => setRecategorizing(false)} />

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
            placeholder="Password (min 8 characters)"
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
            disabled={!newUsername.trim() || newUserPassword.length < 8}
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
            placeholder="New password (min 8 characters)"
            className="h-12 rounded-lg border border-input bg-card px-4 text-base outline-none focus:ring-2 focus:ring-ring"
          />
          {error && <p className="text-sm text-destructive">{error}</p>}
          <button
            onClick={changePassword}
            disabled={newPassword.length < 8}
            className="touch-feedback h-12 rounded-xl bg-primary font-semibold text-primary-foreground disabled:opacity-50"
          >
            Update password
          </button>
        </div>
      </Sheet>
    </div>
  )
}
