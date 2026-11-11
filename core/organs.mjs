// The single entry point for organ "number <-> name" conversion (2026-11-11).
// Why: the same lookup `Object.entries(REG.cells).find(([,c]) => String(c.id) === String(name))`
// was hand-copied in 7 places under core/. One missed conversion reads 0 silently
// (real case 2026-11-11: cleared was read as 0 for every organ).
// Rule: core/*.mjs must not hand-write this lookup; use these functions.
// The immunity entry `organ-key-helper` scans for violations.
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { ROOT } from './root.mjs'

let cached = null

export function registry () {
  if (cached) return cached
  try { cached = JSON.parse(readFileSync(join(ROOT, 'core', 'registry.json'), 'utf8')) } catch { cached = { cells: {} } }
  return cached
}

export function cells () { return registry().cells || {} }

// name or number -> the numeric key ('18' / 18 / 'consolidate' all work); null when unknown
export function numOf (x) {
  const c = cells()
  const s = String(x)
  if (c[s]) return s
  const hit = Object.keys(c).find((k) => String(c[k].id) === s)
  return hit || null
}

// name or number -> organ name ('18' -> 'consolidate'); returns the input unchanged when unknown
export function nameOf (x) {
  const k = numOf(x)
  return k ? String(cells()[k].id) : String(x)
}

// name or number -> the registry cell object; null when unknown
export function cellOf (x) {
  const k = numOf(x)
  return k ? cells()[k] : null
}

// name or number -> every (minutes); 0 when unknown
export function everyOf (x) {
  const c = cellOf(x)
  return Number((c && c.every) || 0)
}
