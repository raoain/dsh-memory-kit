// core/root.mjs -- the one place that knows where this installation lives.
//
// Why: the path was copied into 8 modules. That is the same disease as the
// state->rush mapping copied three times: the second copy starts drifting from
// the first, and nobody notices until a move breaks one of them.
//
// Order of resolution:
//   1. COO_ROOT environment variable (a body/OS can set it)
//   2. the directory above this file (works as long as core/ sits in the root)
//
// Never hardcode the path anywhere else.
// usage: import { ROOT } from './root.mjs'

import { existsSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const fromEnv = process.env.COO_ROOT

export const ROOT = fromEnv ? resolve(fromEnv) : resolve(here, '..')

// cheap sanity check: a wrong root should fail loudly here, not halfway through
if (!existsSync(resolve(ROOT, 'track'))) {
  throw new Error(`COO_ROOT looks wrong: ${ROOT} (no track/ inside)`)
}

// 2026-11-22: path table (core/paths.json) — modules must not hardcode track file paths.
import { readFileSync as __readFileSync } from 'node:fs'
const __PATHS = JSON.parse(__readFileSync(resolve(ROOT, 'core/paths.json'), 'utf8'))
export function trackPath(key) {
  const rel = __PATHS[key]
  if (!rel) throw new Error(`paths.json has no key: ${key}`)
  return resolve(ROOT, rel)
}