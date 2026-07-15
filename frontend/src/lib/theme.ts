export type ThemeId = 'light' | 'dark' | 'black'

const THEME_KEY = 'forge_theme'

export const THEMES: { id: ThemeId; label: string }[] = [
  { id: 'light', label: 'Light' },
  { id: 'dark', label: 'Dark' },
  { id: 'black', label: 'Black' },
]

export function getStoredTheme(): ThemeId {
  const stored = localStorage.getItem(THEME_KEY)
  if (stored === 'light' || stored === 'dark' || stored === 'black') return stored
  return 'dark'
}

export function applyTheme(theme: ThemeId) {
  localStorage.setItem(THEME_KEY, theme)
  const root = document.documentElement
  root.classList.toggle('dark', theme !== 'light')
  root.classList.toggle('theme-black', theme === 'black')
  const meta = document.querySelector('meta[name="theme-color"]')
  if (meta) {
    meta.setAttribute(
      'content',
      theme === 'light' ? '#f8f7f4' : theme === 'black' ? '#000000' : '#171412',
    )
  }
}
