import { useState, type ReactNode } from 'react'

export const MUSCLE_GROUPS = ['Chest', 'Back', 'Shoulders', 'Arms', 'Legs', 'Core', 'Full Body', 'Other']
export const EQUIPMENT = ['Barbell', 'Dumbbell', 'Machine', 'Cable', 'Bodyweight', 'EZ Bar', 'Trap Bar', 'Kettlebell', 'Other']

export interface ExerciseFields {
  name: string
  muscle_group: string
  equipment: string
}

interface ExerciseFormProps {
  initial?: ExerciseFields
  submitLabel: string
  onSubmit: (fields: ExerciseFields) => void | Promise<void>
  error?: string
  secondaryAction?: ReactNode
}

export default function ExerciseForm({
  initial,
  submitLabel,
  onSubmit,
  error,
  secondaryAction,
}: ExerciseFormProps) {
  const [name, setName] = useState(initial?.name ?? '')
  const [muscleGroup, setMuscleGroup] = useState(initial?.muscle_group ?? MUSCLE_GROUPS[0])
  const [equipment, setEquipment] = useState(initial?.equipment ?? EQUIPMENT[0])

  return (
    <div className="flex flex-col gap-4 pt-2">
      <label className="flex flex-col gap-1.5 text-sm font-medium">
        Name
        <input
          autoFocus={!initial}
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="e.g. Incline Cable Fly"
          className="h-11 rounded-lg border border-input bg-card px-3 text-base outline-none focus:ring-2 focus:ring-ring"
        />
      </label>
      <label className="flex flex-col gap-1.5 text-sm font-medium">
        Muscle group
        <select
          value={muscleGroup}
          onChange={(e) => setMuscleGroup(e.target.value)}
          className="h-11 rounded-lg border border-input bg-card px-3 text-base outline-none focus:ring-2 focus:ring-ring"
        >
          {MUSCLE_GROUPS.map((g) => (
            <option key={g}>{g}</option>
          ))}
        </select>
      </label>
      <label className="flex flex-col gap-1.5 text-sm font-medium">
        Equipment
        <select
          value={equipment}
          onChange={(e) => setEquipment(e.target.value)}
          className="h-11 rounded-lg border border-input bg-card px-3 text-base outline-none focus:ring-2 focus:ring-ring"
        >
          {EQUIPMENT.map((eq) => (
            <option key={eq}>{eq}</option>
          ))}
        </select>
      </label>
      <p className="text-xs text-muted-foreground">
        Bodyweight equipment makes sets complete on reps alone — added weight stays optional.
      </p>
      {error && <p className="text-sm text-destructive">{error}</p>}
      <div className="flex gap-2 pt-1">
        {secondaryAction}
        <button
          onClick={() => onSubmit({ name: name.trim(), muscle_group: muscleGroup, equipment })}
          disabled={!name.trim()}
          className="touch-feedback h-11 flex-1 rounded-lg bg-primary font-semibold text-primary-foreground disabled:opacity-50"
        >
          {submitLabel}
        </button>
      </div>
    </div>
  )
}
