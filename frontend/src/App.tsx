import { useEffect, useState, type ReactNode } from 'react'
import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import Toaster from './components/Toaster'
import { AuthProvider, useAuth } from './contexts/AuthContext'
import { WorkoutProvider } from './contexts/WorkoutContext'
import { api } from './lib/api'
import AppShell from './components/AppShell'
import ActiveWorkoutPage from './pages/ActiveWorkoutPage'
import ExerciseDetailPage from './pages/ExerciseDetailPage'
import ExercisesPage from './pages/ExercisesPage'
import HistoryPage from './pages/HistoryPage'
import LoginPage from './pages/LoginPage'
import RoutineEditorPage from './pages/RoutineEditorPage'
import SettingsPage from './pages/SettingsPage'
import SetupPage from './pages/SetupPage'
import StatsPage from './pages/StatsPage'
import WorkoutDetailPage from './pages/WorkoutDetailPage'
import WorkoutHomePage from './pages/WorkoutHomePage'

function Protected({ children }: { children: ReactNode }) {
  const { user, loading } = useAuth()
  const [needsSetup, setNeedsSetup] = useState<boolean | null>(null)

  useEffect(() => {
    if (!loading && !user) {
      api<{ needs_setup: boolean }>('/auth/setup-status')
        .then((s) => setNeedsSetup(s.needs_setup))
        .catch(() => setNeedsSetup(false))
    }
  }, [loading, user])

  if (loading) {
    return (
      <div className="flex h-full items-center justify-center text-muted-foreground">
        Loading…
      </div>
    )
  }
  if (!user) {
    if (needsSetup === null) return null
    return <Navigate to={needsSetup ? '/setup' : '/login'} replace />
  }
  return <WorkoutProvider>{children}</WorkoutProvider>
}

export default function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <Toaster />
        <Routes>
          <Route path="/login" element={<LoginPage />} />
          <Route path="/setup" element={<SetupPage />} />
          <Route
            path="/workout"
            element={
              <Protected>
                <ActiveWorkoutPage />
              </Protected>
            }
          />
          <Route
            element={
              <Protected>
                <AppShell />
              </Protected>
            }
          >
            <Route path="/" element={<WorkoutHomePage />} />
            <Route path="/routines/new" element={<RoutineEditorPage />} />
            <Route path="/routines/:id" element={<RoutineEditorPage />} />
            <Route path="/history" element={<HistoryPage />} />
            <Route path="/history/:id" element={<WorkoutDetailPage />} />
            <Route path="/exercises" element={<ExercisesPage />} />
            <Route path="/exercises/:id" element={<ExerciseDetailPage />} />
            <Route path="/stats" element={<StatsPage />} />
            <Route path="/settings" element={<SettingsPage />} />
            <Route path="*" element={<Navigate to="/" replace />} />
          </Route>
        </Routes>
      </AuthProvider>
    </BrowserRouter>
  )
}
