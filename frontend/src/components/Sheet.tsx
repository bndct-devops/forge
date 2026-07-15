import { X } from 'lucide-react'
import { useEffect, useState, type ReactNode } from 'react'
import { cn } from '../lib/utils'
import { getAppHeight } from '../lib/viewport'

interface SheetProps {
  open: boolean
  onClose: () => void
  title?: string
  children: ReactNode
  full?: boolean
}

/** iOS keyboards overlay the layout viewport instead of resizing it — track the
 *  visual viewport so the sheet can lift and shrink above the keyboard. */
function useKeyboardInset(active: boolean): number {
  const [inset, setInset] = useState(0)
  useEffect(() => {
    if (!active) return
    const vv = window.visualViewport
    if (!vv) return
    const update = () =>
      setInset(Math.max(0, getAppHeight() - vv.height - vv.offsetTop))
    update()
    vv.addEventListener('resize', update)
    vv.addEventListener('scroll', update)
    return () => {
      vv.removeEventListener('resize', update)
      vv.removeEventListener('scroll', update)
      setInset(0)
    }
  }, [active])
  return inset
}

/** Bottom sheet on mobile, centered dialog on md+. */
export default function Sheet({ open, onClose, title, children, full }: SheetProps) {
  const keyboardInset = useKeyboardInset(open)

  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose()
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [open, onClose])

  if (!open) return null

  return (
    // Height comes from --app-h, not inset-0 — fixed positioning trusts the
    // layout viewport, which iOS standalone webviews get wrong (see viewport.ts)
    <div
      className="fixed inset-x-0 top-0 z-50 flex items-end justify-center md:items-center md:p-6"
      style={{ height: 'var(--app-h, 100dvh)' }}
    >
      <div className="absolute inset-0 bg-black/50" onClick={onClose} />
      <div
        className={cn(
          'animate-in slide-in-from-bottom md:fade-in md:zoom-in-95 md:slide-in-from-bottom-0 relative flex w-full max-w-lg flex-col rounded-t-2xl bg-popover shadow-2xl duration-300 md:rounded-2xl md:border md:duration-200',
          full ? 'h-[92dvh] md:h-[80dvh]' : 'max-h-[85dvh] md:max-h-[80dvh]',
        )}
        style={{
          animationTimingFunction: 'var(--spring)',
          ...(keyboardInset > 0 && {
            transform: `translateY(-${keyboardInset}px)`,
            height: full ? `calc(92dvh - ${keyboardInset}px)` : undefined,
            maxHeight: `calc(92dvh - ${keyboardInset}px)`,
          }),
        }}
      >
        <div className="mx-auto mt-2 h-1 w-10 shrink-0 rounded-full bg-muted-foreground/30 md:hidden" />
        <div className="flex items-center justify-between px-5 pt-3 pb-1">
          <h2 className="text-lg">{title}</h2>
          <button
            onClick={onClose}
            className="touch-feedback -mr-1 rounded-full p-2 text-muted-foreground hover:bg-secondary"
            aria-label="Close"
          >
            <X size={20} />
          </button>
        </div>
        <div className="overscroll-contain min-h-0 flex-1 overflow-y-auto px-5 pb-8">
          {children}
        </div>
      </div>
    </div>
  )
}
