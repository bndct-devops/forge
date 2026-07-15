/** Rest-timer push alerts — the only way a locked iPhone hears the timer.
 *  Needs a secure context (HTTPS or localhost) and the installed PWA on iOS. */
import { api } from './api'

const ENABLED_KEY = 'forge_push_enabled'

export function pushSupported(): boolean {
  return (
    window.isSecureContext &&
    'serviceWorker' in navigator &&
    'PushManager' in window &&
    'Notification' in window
  )
}

export function pushEnabled(): boolean {
  return pushSupported() && localStorage.getItem(ENABLED_KEY) === 'on'
}

function applicationServerKey(b64: string): Uint8Array {
  const padded = b64 + '='.repeat((4 - (b64.length % 4)) % 4)
  const raw = atob(padded.replace(/-/g, '+').replace(/_/g, '/'))
  return Uint8Array.from(raw, (c) => c.charCodeAt(0))
}

export async function enableRestPush(): Promise<'enabled' | 'denied' | 'unsupported'> {
  if (!pushSupported()) return 'unsupported'
  const permission = await Notification.requestPermission()
  if (permission !== 'granted') return 'denied'
  const registration = await navigator.serviceWorker.ready
  const { key } = await api<{ key: string }>('/push/public-key')
  const subscription = await registration.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: applicationServerKey(key) as BufferSource,
  })
  await api('/push/subscribe', { method: 'POST', body: subscription.toJSON() })
  localStorage.setItem(ENABLED_KEY, 'on')
  return 'enabled'
}

export async function disableRestPush(): Promise<void> {
  localStorage.setItem(ENABLED_KEY, 'off')
  try {
    const registration = await navigator.serviceWorker.ready
    const subscription = await registration.pushManager.getSubscription()
    if (subscription) {
      await api('/push/unsubscribe', {
        method: 'POST',
        body: { endpoint: subscription.endpoint },
      })
      await subscription.unsubscribe()
    }
  } catch {
    // best effort
  }
}

/** Mirror the local rest timer to the server so it can push at the end.
 *  Fire-and-forget — a failure only means no lock-screen alert. */
export function syncRestPush(endsAt: number | null) {
  if (!pushEnabled()) return
  api('/push/rest-timer', {
    method: 'POST',
    body: { ends_at: endsAt != null ? new Date(endsAt).toISOString() : null },
  }).catch(() => {})
}
