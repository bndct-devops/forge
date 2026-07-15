import { useRef, useState, type CSSProperties, type PointerEvent as ReactPointerEvent } from 'react'

interface DragState {
  from: number
  to: number
  dy: number
}

/** Pointer-based list reordering. Attach `handleProps(i)` to each row's grip
 *  and `itemProps(i)` to the row itself; rows shift live and `onCommit` fires
 *  with the final (from, to) on release. The handle sets touch-action:none so
 *  dragging never fights the page scroll. */
export function useDragReorder(count: number, onCommit: (from: number, to: number) => void) {
  const [drag, setDrag] = useState<DragState | null>(null)
  const itemRefs = useRef<(HTMLElement | null)[]>([])
  const startY = useRef(0)
  const rects = useRef<{ top: number; height: number }[]>([])

  const setItemRef = (index: number) => (el: HTMLElement | null) => {
    itemRefs.current[index] = el
  }

  const targetIndex = (from: number, dy: number): number => {
    const r = rects.current
    if (!r.length) return from
    const center = r[from].top + r[from].height / 2 + dy
    if (center <= r[0].top) return 0
    for (let i = 0; i < r.length; i++) {
      if (center >= r[i].top && center <= r[i].top + r[i].height) return i
    }
    return center > r[r.length - 1].top ? r.length - 1 : from
  }

  const handleProps = (index: number) => ({
    style: { touchAction: 'none', cursor: 'grab' } as CSSProperties,
    onPointerDown: (e: ReactPointerEvent) => {
      e.preventDefault()
      ;(e.currentTarget as HTMLElement).setPointerCapture(e.pointerId)
      startY.current = e.clientY
      rects.current = itemRefs.current.slice(0, count).map((el) => {
        const rect = el?.getBoundingClientRect()
        return { top: rect?.top ?? 0, height: rect?.height ?? 0 }
      })
      setDrag({ from: index, to: index, dy: 0 })
    },
    onPointerMove: (e: ReactPointerEvent) => {
      setDrag((d) => {
        if (!d) return d
        const dy = e.clientY - startY.current
        return { ...d, dy, to: targetIndex(d.from, dy) }
      })
    },
    onPointerUp: () => {
      setDrag((d) => {
        if (d && d.from !== d.to) onCommit(d.from, d.to)
        return null
      })
    },
    onPointerCancel: () => setDrag(null),
  })

  const itemProps = (index: number) => {
    let style: CSSProperties = { transition: 'transform 0.2s var(--spring)' }
    if (drag) {
      if (index === drag.from) {
        style = {
          transform: `translateY(${drag.dy}px) scale(1.02)`,
          zIndex: 20,
          position: 'relative',
          transition: 'none',
          boxShadow: '0 8px 24px rgba(0,0,0,0.35)',
        }
      } else {
        const height = rects.current[drag.from]?.height ?? 0
        let shift = 0
        if (drag.from < index && index <= drag.to) shift = -height
        else if (drag.to <= index && index < drag.from) shift = height
        style = { transform: `translateY(${shift}px)`, transition: 'transform 0.2s var(--spring)' }
      }
    }
    return { ref: setItemRef(index), style }
  }

  return { handleProps, itemProps, dragging: drag != null }
}

/** Move one element of an array, immutably. */
export function moveItem<T>(items: T[], from: number, to: number): T[] {
  const next = [...items]
  const [moved] = next.splice(from, 1)
  next.splice(to, 0, moved)
  return next
}
