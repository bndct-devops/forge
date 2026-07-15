import { X } from 'lucide-react'
import { useEffect, useRef, useState, type PointerEvent as ReactPointerEvent, type ReactNode } from 'react'
import { cn } from '../lib/utils'
import { getAppHeight } from '../lib/viewport'

const EXIT_MS = 340
const DISMISS_DISTANCE = 110
const DISMISS_VELOCITY = 0.55 // px/ms

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
    const update = () => setInset(Math.max(0, getAppHeight() - vv.height - vv.offsetTop))
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

/** Bottom sheet on mobile, centered dialog on md+. Behaves like the native
 *  thing it resembles: drag the grabber/header down to dismiss (with velocity),
 *  spring back on an uncommitted drag, animate out on close, backdrop fades
 *  with the gesture. */
export default function Sheet({ open, onClose, title, children, full }: SheetProps) {
  const [mounted, setMounted] = useState(open)
  const [shown, setShown] = useState(false)
  const [dragY, setDragY] = useState(0)
  const [dragging, setDragging] = useState(false)
  const keyboardInset = useKeyboardInset(open)
  const dragStart = useRef(0)
  const lastMove = useRef({ y: 0, t: 0, v: 0 })

  // Mount → two frames later flip to shown so the enter transition runs;
  // open=false → play the exit transition, then unmount.
  useEffect(() => {
    if (open) {
      setMounted(true)
      setDragY(0)
      const raf = requestAnimationFrame(() => requestAnimationFrame(() => setShown(true)))
      return () => cancelAnimationFrame(raf)
    }
    setShown(false)
    const t = setTimeout(() => setMounted(false), EXIT_MS)
    return () => clearTimeout(t)
  }, [open])

  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose()
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [open, onClose])

  if (!mounted) return null

  const onDragStart = (e: ReactPointerEvent) => {
    e.currentTarget.setPointerCapture(e.pointerId)
    dragStart.current = e.clientY
    lastMove.current = { y: e.clientY, t: performance.now(), v: 0 }
    setDragging(true)
  }

  const onDragMove = (e: ReactPointerEvent) => {
    if (!dragging) return
    const dy = Math.max(0, e.clientY - dragStart.current)
    const now = performance.now()
    const dt = now - lastMove.current.t
    if (dt > 0) {
      lastMove.current = { y: e.clientY, t: now, v: (e.clientY - lastMove.current.y) / dt }
    }
    setDragY(dy)
  }

  const onDragEnd = () => {
    if (!dragging) return
    setDragging(false)
    // A pause before release means the flick is over — distance decides alone
    const stale = performance.now() - lastMove.current.t > 80
    const velocity = stale ? 0 : lastMove.current.v
    if (dragY > DISMISS_DISTANCE || velocity > DISMISS_VELOCITY) {
      onClose() // exit transition continues from the current drag position
    } else {
      setDragY(0) // spring back
    }
  }

  const state = shown && open ? 'open' : 'closed'
  const backdropOpacity = dragging || dragY > 0 ? Math.max(0, 1 - dragY / 420) : undefined

  return (
    <div
      className="fixed inset-x-0 top-0 z-50 flex items-end justify-center md:items-center md:p-6"
      style={{ height: 'var(--app-h, 100dvh)', pointerEvents: open ? 'auto' : 'none' }}
    >
      <div
        data-state={state}
        className="sheet-backdrop absolute inset-0 bg-black/50"
        style={backdropOpacity != null ? { opacity: backdropOpacity, transition: 'none' } : undefined}
        onClick={onClose}
      />
      <div
        data-state={state}
        className={cn(
          'sheet-panel relative flex w-full max-w-lg flex-col rounded-t-2xl bg-popover shadow-2xl md:rounded-2xl md:border',
          full ? 'h-[92dvh] md:h-[80dvh]' : 'max-h-[85dvh] md:max-h-[80dvh]',
        )}
        style={{
          ...(state === 'open' && {
            transform: `translateY(${dragY - keyboardInset}px)`,
          }),
          ...(dragging && { transition: 'none' }),
          ...(keyboardInset > 0 && {
            height: full ? `calc(92dvh - ${keyboardInset}px)` : undefined,
            maxHeight: `calc(92dvh - ${keyboardInset}px)`,
          }),
        }}
      >
        {/* Drag surface: grabber + header row */}
        <div
          className="shrink-0 select-none md:cursor-default"
          style={{ touchAction: 'none' }}
          onPointerDown={onDragStart}
          onPointerMove={onDragMove}
          onPointerUp={onDragEnd}
          onPointerCancel={onDragEnd}
        >
          <div className="mx-auto mt-2 h-1 w-10 rounded-full bg-muted-foreground/30 md:hidden" />
          <div className="flex items-center justify-between px-5 pt-3 pb-1">
            <h2 className="text-lg">{title}</h2>
            <button
              onClick={onClose}
              onPointerDown={(e) => e.stopPropagation()}
              className="touch-feedback -mr-1 rounded-full p-2 text-muted-foreground hover:bg-secondary"
              aria-label="Close"
            >
              <X size={20} />
            </button>
          </div>
        </div>
        <div className="overscroll-contain min-h-0 flex-1 overflow-y-auto px-5 pb-8">
          {children}
        </div>
      </div>
    </div>
  )
}
