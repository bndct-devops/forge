import type { ReactNode } from 'react'

/** Floating barbell — Forge's counterpart to Tome's levitating book. */
export function BarbellAnimation({ className }: { className?: string }) {
  return (
    <div className={`bb-anim ${className ?? ''}`} aria-hidden="true">
      <svg viewBox="0 0 64 40">
        <ellipse className="bb-shadow" cx="32" cy="36" rx="20" ry="2.5" fill="currentColor" />
        <g className="bb-bar" fill="currentColor">
          <rect x="4" y="18.4" width="56" height="3.2" rx="1.6" />
          <rect x="12" y="9" width="4.5" height="22" rx="2.25" />
          <rect x="19" y="12.5" width="4.5" height="15" rx="2.25" />
          <rect x="47.5" y="9" width="4.5" height="22" rx="2.25" />
          <rect x="40.5" y="12.5" width="4.5" height="15" rx="2.25" />
        </g>
      </svg>
    </div>
  )
}

interface EmptyStateProps {
  title: string
  children?: ReactNode
}

export default function EmptyState({ title, children }: EmptyStateProps) {
  return (
    <div className="flex flex-col items-center rounded-xl border border-dashed px-8 py-10 text-center">
      <BarbellAnimation className="mb-4 w-20 text-primary" />
      <p className="font-medium">{title}</p>
      {children && <p className="mt-1 text-sm text-muted-foreground">{children}</p>}
    </div>
  )
}
