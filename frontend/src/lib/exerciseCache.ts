/** Session cache for the exercise catalogue — it changes rarely, so pages
 *  render instantly from the last fetch and revalidate in the background.
 *  Kills the skeleton-then-pop double change inside tab view-transitions. */
import { api } from './api'
import type { Exercise } from './types'

let cache: Exercise[] | null = null

export function getCachedExercises(): Exercise[] | null {
  return cache
}

export async function fetchExercises(): Promise<Exercise[]> {
  const exercises = await api<Exercise[]>('/exercises')
  cache = exercises
  return exercises
}
