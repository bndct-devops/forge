/// <reference lib="webworker" />
/** Forge service worker: app-shell precache + rest-timer push alerts. */
import { createHandlerBoundToURL, precacheAndRoute } from 'workbox-precaching'
import { NavigationRoute, registerRoute } from 'workbox-routing'

declare let self: ServiceWorkerGlobalScope & { __WB_MANIFEST: Array<string | { url: string; revision: string | null }> }

precacheAndRoute(self.__WB_MANIFEST)

// SPA navigation fallback — API and asset requests hit the network
registerRoute(
  new NavigationRoute(createHandlerBoundToURL('index.html'), {
    denylist: [/^\/api\//],
  }),
)

self.addEventListener('install', () => self.skipWaiting())
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()))

self.addEventListener('push', (event) => {
  const data = (() => {
    try {
      return event.data?.json() ?? {}
    } catch {
      return {}
    }
  })()

  event.waitUntil(
    (async () => {
      // If the app is open and focused, the in-app timer bar already handles it
      const clients = await self.clients.matchAll({ type: 'window' })
      if (clients.some((c) => c.focused)) return
      await self.registration.showNotification(data.title ?? 'Forge', {
        body: data.body ?? '',
        tag: data.tag ?? 'forge',
        icon: '/pwa-192.png',
        badge: '/pwa-192.png',
      })
    })(),
  )
})

self.addEventListener('notificationclick', (event) => {
  event.notification.close()
  event.waitUntil(
    (async () => {
      const clients = await self.clients.matchAll({ type: 'window' })
      if (clients.length > 0) await clients[0].focus()
      else await self.clients.openWindow('/workout')
    })(),
  )
})
