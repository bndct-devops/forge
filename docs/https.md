# Running Forge behind HTTPS

Plain HTTP works fine on your LAN, but a secure context unlocks the full PWA:

- **Rest-timer push alerts with the screen locked** — the killer feature.
  iOS 16.4+ delivers Web Push to installed home-screen apps; Forge's server
  schedules a push for the exact second your rest ends.
- Offline app shell (service worker precache) — the UI loads with no network.
- Faster loads (cached assets served locally).

## Quickest path: Caddy

Caddy gets and renews certificates automatically. On the machine that runs
Forge (or any box that can reach it):

```
# Caddyfile
forge.example.org {
    reverse_proxy 127.0.0.1:8081
}
```

```bash
caddy run --config Caddyfile
```

That's it — point `forge.example.org` (or a DuckDNS/Tailscale-funnel name) at
your server, and Caddy handles TLS.

## Alternatives

- **Tailscale Serve/Funnel**: `tailscale serve https / http://127.0.0.1:8081`
  gives you a trusted `https://<machine>.<tailnet>.ts.net` URL with zero
  certificate work — ideal if your phone is on the tailnet anyway.
- **nginx / Traefik**: any reverse proxy that terminates TLS works; Forge
  needs no special headers.

## After switching to HTTPS

1. Open the HTTPS URL in Safari, **Share → Add to Home Screen** (re-add — the
   HTTP install is a separate app to iOS).
2. Launch the installed app → Settings → Training → **Rest alerts (lock
   screen)** → Enable, and accept the notification prompt.
3. Done: finish a set, lock the phone — a notification arrives when rest ends.

Notes:
- Push keys (VAPID) are auto-generated and persisted in `/data/vapid_private.pem`.
- The in-app beep/vibration still works everywhere; push is additive.
- Pending rest pushes live in memory — restarting the server mid-rest only
  costs that one alert.
