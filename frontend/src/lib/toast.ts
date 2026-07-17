/** Minimal global toasts — failures that would otherwise be silent, plus
 *  undo-style actions. */
import { useEffect, useState } from 'react'

export interface Toast {
  id: number
  message: string
  kind: 'warn' | 'info'
  action?: { label: string; run: () => void }
}

let nextId = 1
let toasts: Toast[] = []
const listeners = new Set<() => void>()

function notify() {
  listeners.forEach((l) => l())
}

export function dismissToast(id: number) {
  toasts = toasts.filter((t) => t.id !== id)
  notify()
}

export function toast(
  message: string,
  opts?: { kind?: 'warn' | 'info'; action?: { label: string; run: () => void }; duration?: number },
): number {
  const id = nextId++
  toasts = [...toasts, { id, message, kind: opts?.kind ?? 'warn', action: opts?.action }]
  notify()
  setTimeout(() => dismissToast(id), opts?.duration ?? 3200)
  return id
}

export function useToasts(): Toast[] {
  const [, setVersion] = useState(0)
  useEffect(() => {
    const l = () => setVersion((v) => v + 1)
    listeners.add(l)
    return () => {
      listeners.delete(l)
    }
  }, [])
  return toasts
}
