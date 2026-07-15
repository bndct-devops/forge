import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App'
import { applyTheme, getStoredTheme } from './lib/theme'
import { installViewportFix } from './lib/viewport'

applyTheme(getStoredTheme())
installViewportFix()

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
