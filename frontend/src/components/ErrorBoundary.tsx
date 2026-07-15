import { Component, type ReactNode } from 'react'
import { RotateCcw } from 'lucide-react'

interface Props {
  children: ReactNode
}

interface State {
  error: Error | null
}

/** Last line of defense — a crash in any page renders a friendly reload
 *  screen instead of a dead white PWA. */
export default class ErrorBoundary extends Component<Props, State> {
  state: State = { error: null }

  static getDerivedStateFromError(error: Error): State {
    return { error }
  }

  render() {
    if (!this.state.error) return this.props.children
    return (
      <div className="flex h-full flex-col items-center justify-center gap-4 px-8 text-center">
        <h1 className="text-2xl">Something broke</h1>
        <p className="text-sm text-muted-foreground">
          Your data is safe on the server — this is just the screen falling over.
        </p>
        <p className="tnum max-w-full overflow-hidden rounded-lg bg-secondary px-3 py-2 text-xs text-ellipsis whitespace-nowrap text-muted-foreground">
          {this.state.error.message}
        </p>
        <button
          onClick={() => location.reload()}
          className="touch-feedback flex items-center gap-2 rounded-xl bg-primary px-5 py-3 font-semibold text-primary-foreground"
        >
          <RotateCcw size={17} /> Reload
        </button>
      </div>
    )
  }
}
