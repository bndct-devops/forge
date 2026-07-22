import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App'
import { hydrateDataCache } from './lib/dataCache'
import { applyTheme, getStoredTheme } from './lib/theme'
import { installViewportFix } from './lib/viewport'

applyTheme(getStoredTheme())
installViewportFix()

// Load the offline data cache before first render so pages can read it
// synchronously in their state initializers. Bounded internally to 1.5s.
hydrateDataCache().finally(() => {
  createRoot(document.getElementById('root')!).render(
    <StrictMode>
      <App />
    </StrictMode>,
  )
})
