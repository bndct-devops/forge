import { Dumbbell, Flame, History, Settings, BicepsFlexed, Play, TrendingUp } from 'lucide-react'
import { NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom'
import { useWorkout } from '../contexts/WorkoutContext'
import { formatClock, parseUTC } from '../lib/format'
import { cn } from '../lib/utils'
import { useEffect, useRef, useState } from 'react'

const TABS = [
  { to: '/', label: 'Workout', icon: Dumbbell },
  { to: '/history', label: 'History', icon: History },
  { to: '/exercises', label: 'Exercises', icon: BicepsFlexed },
  { to: '/stats', label: 'Stats', icon: TrendingUp },
  { to: '/settings', label: 'Settings', icon: Settings },
]

function ResumeBar({ className }: { className?: string }) {
  const { workout } = useWorkout()
  const navigate = useNavigate()
  const [, setTick] = useState(0)

  useEffect(() => {
    if (!workout) return
    const t = setInterval(() => setTick((v) => v + 1), 1000)
    return () => clearInterval(t)
  }, [workout])

  if (!workout) return null
  const elapsed = (Date.now() - parseUTC(workout.started_at).getTime()) / 1000

  return (
    <button
      onClick={() => navigate('/workout')}
      className={cn(
        'touch-feedback flex items-center gap-3 rounded-xl bg-primary px-4 py-3 text-left text-primary-foreground shadow-lg',
        className,
      )}
    >
      <Play size={18} className="shrink-0 fill-current" />
      <span className="min-w-0 flex-1 truncate font-semibold">{workout.name}</span>
      <span className="tnum text-sm font-medium opacity-90">{formatClock(elapsed)}</span>
    </button>
  )
}

export default function AppShell() {
  const { pathname } = useLocation()
  const scrollRef = useRef<HTMLElement>(null)

  // The document never scrolls, so reset the inner scroller on navigation
  useEffect(() => {
    scrollRef.current?.scrollTo(0, 0)
  }, [pathname])

  return (
    <div className="flex h-full">
      {/* Desktop sidebar */}
      <aside className="hidden w-60 shrink-0 flex-col border-r bg-card px-3 py-5 md:flex">
        <div className="mb-6 flex items-center gap-2.5 px-2">
          <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-primary text-primary-foreground">
            <Flame size={20} />
          </div>
          <span className="font-display text-xl">Forge</span>
        </div>
        <nav className="flex flex-col gap-1">
          {TABS.map(({ to, label, icon: Icon }) => (
            <NavLink
              key={to}
              to={to}
              end={to === '/'}
              className={({ isActive }) =>
                cn(
                  'touch-feedback flex items-center gap-3 rounded-lg px-3 py-2.5 font-medium transition-colors',
                  isActive
                    ? 'bg-accent-soft text-primary'
                    : 'text-muted-foreground hover:bg-secondary hover:text-foreground',
                )
              }
            >
              <Icon size={19} strokeWidth={2} />
              {label}
            </NavLink>
          ))}
        </nav>
        <div className="mt-auto">
          <ResumeBar className="w-full" />
        </div>
      </aside>

      {/* Content column: scrollable main + in-flow mobile tab bar */}
      <div className="flex min-w-0 flex-1 flex-col">
        <main ref={scrollRef} className="overscroll-contain flex-1 overflow-y-auto">
          <div className="mx-auto w-full max-w-lg pb-8 md:max-w-4xl md:px-6">
            <Outlet />
          </div>
        </main>
        <div className="shrink-0 md:hidden">
          <ResumeBar className="mx-3 mb-2 flex w-[calc(100%-1.5rem)]" />
          <nav className="safe-bottom border-t bg-card">
            <div className="grid grid-cols-5">
              {TABS.map(({ to, label, icon: Icon }) => (
                <NavLink
                  key={to}
                  to={to}
                  end={to === '/'}
                  className={({ isActive }) =>
                    cn(
                      'touch-feedback flex flex-col items-center gap-1 py-2 pt-2.5 text-[11px] font-medium',
                      isActive ? 'text-primary' : 'text-muted-foreground',
                    )
                  }
                >
                  <Icon size={22} strokeWidth={2} />
                  {label}
                </NavLink>
              ))}
            </div>
          </nav>
        </div>
      </div>
    </div>
  )
}
