import type { ReactNode } from 'react'
import Sheet from './Sheet'
import { cn } from '../lib/utils'

interface ConfirmSheetProps {
  open: boolean
  onClose: () => void
  title: string
  message: ReactNode
  actionLabel: string
  onConfirm: () => void
  destructive?: boolean
}

/** One-question confirmation for destructive actions. */
export default function ConfirmSheet({
  open,
  onClose,
  title,
  message,
  actionLabel,
  onConfirm,
  destructive,
}: ConfirmSheetProps) {
  return (
    <Sheet open={open} onClose={onClose} title={title}>
      <div className="flex flex-col gap-3 pt-1">
        <p className="text-sm text-muted-foreground">{message}</p>
        <button
          onClick={onConfirm}
          className={cn(
            'touch-feedback h-12 rounded-xl font-semibold',
            destructive ? 'bg-destructive text-white' : 'bg-primary text-primary-foreground',
          )}
        >
          {actionLabel}
        </button>
        <button
          onClick={onClose}
          className="touch-feedback h-12 rounded-xl bg-secondary font-semibold text-secondary-foreground"
        >
          Keep it
        </button>
      </div>
    </Sheet>
  )
}
