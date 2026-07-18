import { memo } from 'react'
import { BODY_FRONT, BODY_BACK, type BodyPath, type MuscleRegion } from '../lib/bodyPaths'

const NEUTRAL_BODY = 'color-mix(in oklch, var(--foreground) 5%, transparent)'
const NEUTRAL_MUSCLE = 'color-mix(in oklch, var(--foreground) 9%, transparent)'
const SECONDARY = 'color-mix(in oklch, var(--primary) 35%, transparent)'

function Figure({
  paths,
  viewBox,
  primary,
  secondary,
  label,
}: {
  paths: BodyPath[]
  viewBox: string
  primary: MuscleRegion[]
  secondary: MuscleRegion[]
  label: string
}) {
  return (
    <figure className="flex-1 text-center" style={{ maxWidth: 150 }}>
      <svg viewBox={viewBox} className="block h-auto w-full" aria-label={label}>
        {paths.map((p, i) => (
          <path
            key={i}
            d={p.d}
            style={{ transition: 'fill 0.3s' }}
            fill={
              p.m && primary.includes(p.m)
                ? 'var(--primary)'
                : p.m && secondary.includes(p.m)
                  ? SECONDARY
                  : p.m
                    ? NEUTRAL_MUSCLE
                    : NEUTRAL_BODY
            }
          />
        ))}
      </svg>
      <figcaption className="mt-1.5 text-[10px] tracking-widest text-muted-foreground uppercase">
        {label}
      </figcaption>
    </figure>
  )
}

export default memo(function MuscleMap({
  primary,
  secondary,
}: {
  primary: MuscleRegion[]
  secondary: MuscleRegion[]
}) {
  return (
    <div className="flex justify-center gap-3">
      <Figure paths={BODY_FRONT} viewBox="0 0 724 1448" primary={primary} secondary={secondary} label="Front" />
      <Figure paths={BODY_BACK} viewBox="724 0 724 1448" primary={primary} secondary={secondary} label="Back" />
    </div>
  )
})
