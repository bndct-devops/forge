/** iOS standalone webviews mis-report the layout viewport — a too-short
 *  initial containing block on cold launch, and a stuck scroll offset after
 *  the software keyboard closes. Percentage/dvh heights inherit the wrong
 *  number, which shows up as a dead black bar under the tab bar.
 *
 *  Fix: size the app frame from the *visual* viewport (which iOS keeps
 *  accurate) via the --app-h custom property, and reset the layout viewport
 *  whenever no input is focused. While an input is focused we leave
 *  everything alone so iOS can scroll the field into view. */

let installed = false

function isTyping(): boolean {
  const el = document.activeElement
  return (
    el != null &&
    (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || (el as HTMLElement).isContentEditable)
  )
}

/** The app frame's real height in px (falls back to the layout viewport). */
export function getAppHeight(): number {
  const raw = document.documentElement.style.getPropertyValue('--app-h')
  const parsed = parseFloat(raw)
  return Number.isFinite(parsed) && parsed > 0 ? parsed : window.innerHeight
}

export function installViewportFix() {
  if (installed) return
  installed = true
  const vv = window.visualViewport

  const apply = () => {
    if (isTyping()) return
    if (vv) {
      document.documentElement.style.setProperty(
        '--app-h',
        `${Math.round(vv.height + vv.offsetTop)}px`,
      )
    }
    window.scrollTo(0, 0)
  }

  vv?.addEventListener('resize', apply)
  vv?.addEventListener('scroll', apply)
  window.addEventListener('focusout', () => setTimeout(apply, 60))
  window.addEventListener('orientationchange', () => setTimeout(apply, 250))
  window.addEventListener('pageshow', apply)
  apply()
}
