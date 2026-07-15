/** Minimal global toasts — for failures that would otherwise be silent. */
import { useEffect, useState } from 'react'

export interface Toast {
  id: number
  message: string
}

let nextId = 1
let toasts: Toast[] = []
const listeners = new Set<() => void>()

function notify() {
  listeners.forEach((l) => l())
}

export function toast(message: string) {
  const id = nextId++
  toasts = [...toasts, { id, message }]
  notify()
  setTimeout(() => {
    toasts = toasts.filter((t) => t.id !== id)
    notify()
  }, 3200)
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
