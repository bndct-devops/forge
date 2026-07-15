import { Dumbbell, History, Settings, BicepsFlexed, Play } from 'lucide-react'
import { NavLink, Outlet, useNavigate } from 'react-router-dom'
import { useWorkout } from '../contexts/WorkoutContext'
import { formatClock, parseUTC } from '../lib/format'
import { cn } from '../lib/utils'
import { useEffect, useState } from 'react'

const TABS = [
  { to: '/', label: 'Workout', icon: Dumbbell },
  { to: '/history', label: 'History', icon: History },
  { to: '/exercises', label: 'Exercises', icon: BicepsFlexed },
  { to: '/settings', label: 'Settings', icon: Settings },
]

function ResumeBar() {
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
      className="touch-feedback mx-3 mb-2 flex items-center gap-3 rounded-xl bg-primary px-4 py-3 text-left text-primary-foreground shadow-lg"
    >
      <Play size={18} className="shrink-0 fill-current" />
      <span className="min-w-0 flex-1 truncate font-semibold">{workout.name}</span>
      <span className="tnum text-sm font-medium opacity-90">{formatClock(elapsed)}</span>
    </button>
  )
}

export default function AppShell() {
  return (
    <div className="mx-auto flex min-h-dvh max-w-lg flex-col">
      <main className="flex-1 pb-36">
        <Outlet />
      </main>
      <nav className="fixed inset-x-0 bottom-0 z-40">
        <div className="mx-auto max-w-lg">
          <ResumeBar />
          <div className="safe-bottom border-t bg-card/90 backdrop-blur-lg">
            <div className="grid grid-cols-4">
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
          </div>
        </div>
      </nav>
    </div>
  )
}
