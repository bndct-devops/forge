/** Small client-side preferences (per device). */
const RPE_KEY = 'forge_rpe'

export function isRpeEnabled(): boolean {
  return localStorage.getItem(RPE_KEY) === 'on'
}

export function setRpeEnabled(on: boolean) {
  localStorage.setItem(RPE_KEY, on ? 'on' : 'off')
}
