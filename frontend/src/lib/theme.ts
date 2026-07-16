export type ThemeId = 'system' | 'light' | 'dark' | 'black'

const THEME_KEY = 'forge_theme'
let systemListener: ((e: MediaQueryListEvent) => void) | null = null

export const THEMES: { id: ThemeId; label: string }[] = [
  { id: 'system', label: 'Auto' },
  { id: 'light', label: 'Light' },
  { id: 'dark', label: 'Dark' },
  { id: 'black', label: 'Black' },
]

export function getStoredTheme(): ThemeId {
  const stored = localStorage.getItem(THEME_KEY)
  if (stored === 'light' || stored === 'dark' || stored === 'black' || stored === 'system') {
    return stored
  }
  return 'dark'
}

function apply(resolved: 'light' | 'dark' | 'black') {
  const root = document.documentElement
  root.classList.toggle('dark', resolved !== 'light')
  root.classList.toggle('theme-black', resolved === 'black')
  const meta = document.querySelector('meta[name="theme-color"]')
  if (meta) {
    meta.setAttribute(
      'content',
      resolved === 'light' ? '#f8f7f4' : resolved === 'black' ? '#000000' : '#171412',
    )
  }
}

export function applyTheme(theme: ThemeId) {
  localStorage.setItem(THEME_KEY, theme)
  const media = window.matchMedia('(prefers-color-scheme: dark)')
  if (systemListener) {
    media.removeEventListener('change', systemListener)
    systemListener = null
  }
  if (theme === 'system') {
    apply(media.matches ? 'dark' : 'light')
    systemListener = (e) => apply(e.matches ? 'dark' : 'light')
    media.addEventListener('change', systemListener)
  } else {
    apply(theme)
  }
}
