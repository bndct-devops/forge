import { X } from 'lucide-react'
import { useEffect, type ReactNode } from 'react'
import { cn } from '../lib/utils'

interface SheetProps {
  open: boolean
  onClose: () => void
  title?: string
  children: ReactNode
  full?: boolean
}

/** Bottom sheet — the mobile-native modal surface. */
export default function Sheet({ open, onClose, title, children, full }: SheetProps) {
  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose()
    document.addEventListener('keydown', onKey)
    document.body.style.overflow = 'hidden'
    return () => {
      document.removeEventListener('keydown', onKey)
      document.body.style.overflow = ''
    }
  }, [open, onClose])

  if (!open) return null

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center">
      <div className="absolute inset-0 bg-black/50" onClick={onClose} />
      <div
        className={cn(
          'animate-in slide-in-from-bottom relative flex w-full max-w-lg flex-col rounded-t-2xl bg-popover shadow-2xl duration-300',
          full ? 'h-[92dvh]' : 'max-h-[85dvh]',
        )}
        style={{ animationTimingFunction: 'var(--spring)' }}
      >
        <div className="mx-auto mt-2 h-1 w-10 shrink-0 rounded-full bg-muted-foreground/30" />
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
