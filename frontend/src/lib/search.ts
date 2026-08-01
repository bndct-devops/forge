// Exercise names carry punctuation nobody types: "Plate-Loaded",
// "Single-Arm", "(Volume)". A plain substring match makes the hyphen
// mandatory, so "plate loaded" finds nothing. Matching normalises both sides
// and requires every query word to appear somewhere in the name, in any
// order — "plate loaded", "plateloaded" and "plate chest" all find
// "Plate-Loaded Incline Chest Press".

const COMBINING_MARKS = /[̀-ͯ]/g

const normalize = (s: string) =>
  s
    .toLowerCase()
    .normalize('NFD')
    .replace(COMBINING_MARKS, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()

/** Precompiles the query so a list filter normalises it once, not per row. */
export function makeMatcher(query: string): (name: string) => boolean {
  const tokens = normalize(query).split(' ').filter(Boolean)
  if (tokens.length === 0) return () => true
  return (name) => {
    const spaced = normalize(name)
    // Squashed lets a token span a separator the user left out ("plateloaded")
    const squashed = spaced.replace(/ /g, '')
    return tokens.every((t) => spaced.includes(t) || squashed.includes(t))
  }
}

export const matchesSearch = (name: string, query: string) => makeMatcher(query)(name)
