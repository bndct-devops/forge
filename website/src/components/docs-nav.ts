// Single source of truth for the docs sidebar & prev/next navigation.
// Edit here to add or reorder pages.
export interface DocItem { href: string; title: string }
export interface DocGroup { label: string; items: DocItem[] }

export const DOCS_NAV: DocGroup[] = [
  {
    label: 'Getting started',
    items: [
      { href: '/docs',                    title: 'Welcome' },
      { href: '/docs/installation',       title: 'Installation' },
      { href: '/docs/first-run',          title: 'First-run setup' },
    ],
  },
  {
    label: 'Training',
    items: [
      { href: '/docs/logging',            title: 'Logging workouts' },
      { href: '/docs/routines',           title: 'Routines & progression' },
      { href: '/docs/programs',           title: 'Programs (periodization)' },
      { href: '/docs/supersets-and-rest', title: 'Supersets & the rest timer' },
      { href: '/docs/exercises',          title: 'Exercise library & muscle map' },
    ],
  },
  {
    label: 'Insights',
    items: [
      { href: '/docs/stats',              title: 'Stats & insights' },
      { href: '/docs/the-math',           title: 'The math' },
    ],
  },
  {
    label: 'Data & integrations',
    items: [
      { href: '/docs/import-export',      title: 'Import & export' },
      { href: '/docs/api',                title: 'API reference' },
      { href: '/docs/webhooks-metrics',   title: 'Webhooks & metrics' },
      { href: '/docs/sso',                title: 'Single sign-on (OIDC)' },
      { href: '/docs/https-push',         title: 'HTTPS & push alerts' },
    ],
  },
  {
    label: 'Reference',
    items: [
      { href: '/docs/configuration',      title: 'Configuration & backups' },
    ],
  },
]

// Flat list, in order — used to compute prev/next.
export const DOCS_FLAT: (DocItem & { groupLabel: string })[] = DOCS_NAV.flatMap(g =>
  g.items.map(item => ({ ...item, groupLabel: g.label })),
)

export function findAdjacent(path: string) {
  const idx = DOCS_FLAT.findIndex(item => item.href === path)
  if (idx === -1) return { prev: null, next: null, current: null }
  return {
    prev: idx > 0 ? DOCS_FLAT[idx - 1] : null,
    next: idx < DOCS_FLAT.length - 1 ? DOCS_FLAT[idx + 1] : null,
    current: DOCS_FLAT[idx],
  }
}
