/** Cache for the exercise catalogue — it changes rarely, so pages render
 *  instantly from the last fetch and revalidate in the background.
 *  Kills the skeleton-then-pop double change inside tab view-transitions.
 *  Backed by the durable data cache, so it also survives offline reloads. */
import { api } from './api'
import { getCached, setCached } from './dataCache'
import type { Exercise } from './types'

export function getCachedExercises(): Exercise[] | null {
  return getCached<Exercise[]>('exercises')
}

export async function fetchExercises(): Promise<Exercise[]> {
  const exercises = await api<Exercise[]>('/exercises')
  setCached('exercises', exercises)
  return exercises
}
