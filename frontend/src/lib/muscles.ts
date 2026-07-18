import type { MuscleRegion } from './bodyPaths'

// POC: primary/secondary regions inferred from the exercise name, falling
// back to the coarse muscle group. The production version would move this
// to a per-movement-family table on the backend.
const GROUP_REGIONS: Record<string, MuscleRegion[]> = {
  Chest: ['chest'],
  Back: ['lats', 'traps', 'lower-back'],
  Shoulders: ['front-delts', 'rear-delts'],
  Arms: ['biceps', 'triceps', 'forearms'],
  Legs: ['quads', 'glutes', 'hamstrings', 'adductors', 'calves'],
  Core: ['abs', 'obliques'],
  'Full Body': ['chest', 'lats', 'front-delts', 'quads', 'glutes', 'hamstrings', 'abs'],
}

interface Pattern {
  re: RegExp
  primary: MuscleRegion[]
  secondary: MuscleRegion[]
}

// Order matters: earlier patterns win (e.g. "leg curl" before "curl",
// "upright row" before "row"). Audited against the full 282-entry catalog.
const PATTERNS: Pattern[] = [
  { re: /leg curl|nordic/i, primary: ['hamstrings'], secondary: ['calves'] },
  { re: /leg extension/i, primary: ['quads'], secondary: [] },
  { re: /calf|calves/i, primary: ['calves'], secondary: [] },
  { re: /glute ham raise/i, primary: ['hamstrings'], secondary: ['glutes', 'calves'] },
  { re: /hip thrust|glute|kickback/i, primary: ['glutes'], secondary: ['hamstrings'] },
  { re: /abduction/i, primary: ['glutes'], secondary: [] },
  { re: /adduction/i, primary: ['adductors'], secondary: [] },
  { re: /rdl|romanian|stiff.?leg/i, primary: ['hamstrings', 'glutes'], secondary: ['lower-back', 'forearms', 'traps'] },
  { re: /good morning/i, primary: ['hamstrings', 'glutes', 'lower-back'], secondary: [] },
  { re: /rack pull/i, primary: ['traps', 'lower-back', 'glutes'], secondary: ['hamstrings', 'forearms', 'lats'] },
  { re: /deadlift/i, primary: ['hamstrings', 'glutes', 'lower-back'], secondary: ['lats', 'traps', 'forearms', 'quads'] },
  { re: /clean|snatch/i, primary: ['quads', 'glutes', 'hamstrings', 'traps'], secondary: ['front-delts', 'lower-back', 'calves', 'forearms'] },
  { re: /kettlebell swing/i, primary: ['glutes', 'hamstrings'], secondary: ['lower-back', 'abs', 'front-delts', 'forearms'] },
  { re: /farmer/i, primary: ['forearms', 'traps'], secondary: ['abs', 'quads', 'glutes', 'calves'] },
  { re: /thruster/i, primary: ['quads', 'glutes', 'front-delts'], secondary: ['triceps', 'hamstrings', 'abs'] },
  { re: /squat|leg press|lunge|hack|step.?up/i, primary: ['quads', 'glutes'], secondary: ['hamstrings', 'adductors', 'lower-back'] },
  { re: /back extension|hyperextension/i, primary: ['lower-back'], secondary: ['glutes', 'hamstrings'] },
  { re: /face pull|rear delt|reverse fly|reverse pec deck/i, primary: ['rear-delts'], secondary: ['traps'] },
  { re: /shrug/i, primary: ['traps'], secondary: [] },
  { re: /upright row/i, primary: ['front-delts', 'traps'], secondary: ['biceps', 'forearms'] },
  { re: /pullover/i, primary: ['lats', 'chest'], secondary: ['triceps'] },
  { re: /straight.?arm/i, primary: ['lats'], secondary: ['triceps'] },
  { re: /pulldown|pull.?up|chin.?up/i, primary: ['lats'], secondary: ['biceps', 'rear-delts'] },
  { re: /row/i, primary: ['lats', 'traps'], secondary: ['biceps', 'rear-delts', 'lower-back'] },
  { re: /front raise/i, primary: ['front-delts'], secondary: [] },
  { re: /lateral raise|side raise|y raise/i, primary: ['front-delts', 'rear-delts'], secondary: [] },
  { re: /push press/i, primary: ['front-delts'], secondary: ['triceps', 'quads', 'glutes'] },
  { re: /landmine press/i, primary: ['front-delts'], secondary: ['chest', 'triceps'] },
  { re: /overhead press|shoulder press|military|arnold|seated (barbell|dumbbell) press/i, primary: ['front-delts'], secondary: ['triceps', 'traps'] },
  { re: /bench dip|machine dip|close.?grip bench/i, primary: ['triceps'], secondary: ['chest', 'front-delts'] },
  { re: /tricep|pushdown|skull|extension/i, primary: ['triceps'], secondary: [] },
  { re: /pec deck/i, primary: ['chest'], secondary: ['front-delts'] },
  { re: /fly/i, primary: ['chest'], secondary: ['front-delts'] },
  { re: /bench|chest press|push.?up|dip|dumbbell press|incline press|decline press/i, primary: ['chest'], secondary: ['front-delts', 'triceps'] },
  { re: /reverse\s.*curl|wrist/i, primary: ['forearms'], secondary: ['biceps'] },
  { re: /curl/i, primary: ['biceps'], secondary: ['forearms'] },
  { re: /side plank/i, primary: ['obliques'], secondary: ['abs'] },
  { re: /woodchop|russian twist|pallof/i, primary: ['obliques'], secondary: ['abs'] },
  { re: /crunch|sit.?up|plank|rollout|leg raise|knee raise|ab wheel|dead bug/i, primary: ['abs'], secondary: ['obliques'] },
]

export function musclesFor(
  name: string,
  muscleGroup: string,
): { primary: MuscleRegion[]; secondary: MuscleRegion[] } {
  for (const p of PATTERNS) {
    if (p.re.test(name)) return { primary: p.primary, secondary: p.secondary }
  }
  return { primary: GROUP_REGIONS[muscleGroup] ?? [], secondary: [] }
}
