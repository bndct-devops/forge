import { AlertCircle } from 'lucide-react'
import { dismissToast, useToasts } from '../lib/toast'

export default function Toaster() {
  const toasts = useToasts()
  if (toasts.length === 0) return null
  return (
    <div className="pointer-events-none fixed inset-x-0 bottom-24 z-[60] flex flex-col items-center gap-2 px-4">
      {toasts.map((t) => (
        <div
          key={t.id}
          className="animate-card-appear pointer-events-auto flex max-w-sm items-center gap-2 rounded-xl border bg-popover px-4 py-2.5 text-sm font-medium shadow-2xl"
        >
          {t.kind === 'warn' && <AlertCircle size={16} className="shrink-0 text-warning" />}
          {t.message}
          {t.action && (
            <button
              onClick={() => {
                dismissToast(t.id)
                t.action!.run()
              }}
              className="touch-feedback -my-1 -mr-2 ml-1 rounded-lg px-2.5 py-1.5 font-semibold text-primary"
            >
              {t.action.label}
            </button>
          )}
        </div>
      ))}
    </div>
  )
}
