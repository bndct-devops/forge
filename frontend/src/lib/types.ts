export interface User {
  id: number
  username: string
  is_admin: boolean
  unit: 'kg' | 'lb'
  default_rest_seconds: number
  weekly_goal: number
}

export interface Exercise {
  id: number
  name: string
  muscle_group: string
  equipment: string
  grip?: string | null
  variant_of_id?: number | null
  is_custom: boolean
  last_used?: string | null
}

export interface Plan {
  key: string
  name: string
  description: string
  routines: { name: string; exercises: { name: string; set_count: number }[] }[]
}

export interface RoutineExercise {
  exercise_id: number
  name: string
  muscle_group: string
  equipment: string
  position: number
  set_count: number
  rest_seconds: number | null
  superset_with_next: boolean
}

export interface Routine {
  id: number
  name: string
  last_performed?: string | null
  exercises: RoutineExercise[]
}

export interface SetEntry {
  id: number
  position: number
  weight: number | null
  reps: number | null
  is_completed: boolean
  is_warmup: boolean
  is_pr: boolean
  rpe?: number | null
}

export interface PastSet {
  weight: number | null
  reps: number | null
  is_pr: boolean
}

export interface WorkoutExercise {
  id: number
  exercise_id: number
  name: string
  muscle_group: string
  equipment: string
  note: string
  position: number
  rest_seconds: number | null
  superset_with_next: boolean
  superset: string | null
  superset_last: boolean
  sets: SetEntry[]
  previous_sets: PastSet[]
}

export interface Workout {
  id: number
  name: string
  notes: string | null
  started_at: string
  finished_at: string | null
  exercises: WorkoutExercise[]
  duration_seconds?: number
  total_volume?: number
  total_sets?: number
  pr_count?: number
}

export interface WorkoutSummary {
  id: number
  name: string
  started_at: string
  finished_at: string
  duration_seconds: number
  total_volume: number
  total_sets: number
  pr_count: number
  exercise_summaries: string[]
}

export interface PR {
  exercise_name: string
  kind: 'weight' | '1rm' | 'reps'
  value: number
  reps: number
}

export interface FinishResult {
  id: number
  name: string
  duration_seconds: number
  total_volume: number
  total_sets: number
  prs: PR[]
  workout_number: number
  week_workouts: number
}

export interface RecordSet {
  weight: number
  reps: number
  date: string
  value?: number
}

export interface ExerciseStats {
  exercise: Exercise
  note: string
  variations: { id: number; name: string; grip: string | null }[]
  records: {
    best_weight: RecordSet | null
    best_1rm: (RecordSet & { value: number }) | null
    best_volume_set: (RecordSet & { value: number }) | null
    best_reps: RecordSet | null
    total_reps: number
    total_volume: number
    times_performed: number
  }
  chart: { date: string; best_1rm: number; best_weight: number; best_reps: number; volume: number }[]
  history: {
    workout_id: number
    workout_name: string
    date: string
    sets: { weight: number; reps: number; is_pr: boolean }[]
  }[]
}
