// Line glyphs per equipment value, Lucide-weight strokes. Eleven equipment
// values fold into seven shapes (Smith -> Machine, EZ/Trap -> Barbell).
const GLYPHS: Record<string, React.ReactNode> = {
  barbell: (
    <>
      <path d="M2.5 12h19" />
      <path d="M5.5 7.5v9M8.5 9.5v5M15.5 9.5v5M18.5 7.5v9" />
    </>
  ),
  dumbbell: (
    <>
      <path d="M8 12h8" />
      <path d="M6 8.5v7M9 7v10M15 7v10M18 8.5v7" />
    </>
  ),
  plate: (
    <>
      <circle cx="12" cy="12" r="8.5" />
      <circle cx="12" cy="12" r="2.6" />
    </>
  ),
  machine: (
    <>
      <rect x="6.5" y="9" width="11" height="11.5" rx="2" />
      <path d="M6.5 13.2h11M6.5 17h11" />
      <path d="M12 3.2v5.8" />
      <circle cx="12" cy="2.6" r="1.1" />
    </>
  ),
  cable: (
    <>
      <circle cx="12" cy="4.5" r="2.2" />
      <path d="M12 7v7.5" />
      <path d="M8 14.5h8M8 14.5v3.5M16 14.5v3.5" />
    </>
  ),
  kettlebell: (
    <>
      <path d="M8 6.5a4 4 0 0 1 8 0" />
      <circle cx="12" cy="14.5" r="5.5" />
    </>
  ),
  bodyweight: (
    <>
      <circle cx="12" cy="4.2" r="2.1" />
      <path d="M12 9.8 6.8 5.4M12 9.8l5.2-4.4" />
      <path d="M12 9.8v5.2" />
      <path d="M12 15 8.2 21M12 15l3.8 6" />
    </>
  ),
  other: <circle cx="12" cy="12" r="5.5" />,
}

function glyphKey(equipment: string | null | undefined): string {
  switch (equipment) {
    case 'Barbell':
    case 'EZ Bar':
    case 'Trap Bar':
      return 'barbell'
    case 'Dumbbell':
      return 'dumbbell'
    case 'Plate-Loaded':
      return 'plate'
    case 'Machine':
    case 'Smith Machine':
      return 'machine'
    case 'Cable':
      return 'cable'
    case 'Kettlebell':
      return 'kettlebell'
    case 'Bodyweight':
      return 'bodyweight'
    default:
      return 'other'
  }
}

export default function EquipmentGlyph({
  equipment,
  size = 18,
  className,
}: {
  equipment: string | null | undefined
  size?: number
  className?: string
}) {
  return (
    <svg
      viewBox="0 0 24 24"
      width={size}
      height={size}
      fill="none"
      stroke="currentColor"
      strokeWidth="1.7"
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
      aria-hidden="true"
    >
      {GLYPHS[glyphKey(equipment)]}
    </svg>
  )
}
