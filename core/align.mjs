// align.mjs -- organ 16: daily re-alignment of the pin table (an immune-layer action).
//
// Why: the pin table caches expected values. Reality moves every day (logs grow, files get
// edited), so comparing a frozen snapshot against a living system reports the same drift
// forever. A permanent alarm is not an alarm any more: it trains everyone to skip the check.
// The immune layer's job is therefore: record the drift first, then move the baseline.
//
// Safety (it must never decide that something died):
//   - the old table is copied to track/align/state.before.json before anything else
//   - if the re-resolved table has FEWER pins than before, it is treated as loss:
//     the old table is restored, track/align.red is written, nothing is aligned
//   - values that shrink are recorded (they can be legitimate, e.g. a rotated log),
//     but they never block; only a shrinking pin COUNT blocks
//
// usage:
//   node core/align.mjs            align if the last run is older than 20 hours
//   node core/align.mjs --force    align now
//   node core/align.mjs --dry      report what would change, write nothing

import { readFileSync, writeFileSync, existsSync, copyFileSync, appendFileSync, mkdirSync } from 'node:fs'
import { join } from 'node:path'
import { spawnSync } from 'node:child_process'
import { ROOT } from './root.mjs'
import { emit } from './bus.mjs'

const SELF = '16'
const PIN = join(ROOT, 'pin.ps1')
const STATE = join(ROOT, 'state.json')
const TRACK = join(ROOT, 'track')
const ADIR = join(TRACK, 'align')
const LOG = join(TRACK, 'align.jsonl')
const RED = join(TRACK, 'align.red')
const INTERVAL_H = 20

const dry = process.argv.includes('--dry')
const force = process.argv.includes('--force')

function readPins() {
  if (!existsSync(STATE)) return null
  try {
    const s = JSON.parse(readFileSync(STATE, 'utf8'))
    return s && s.pins ? s.pins : null
  } catch {
    return null
  }
}

function lastRunMs() {
  if (!existsSync(LOG)) return 0
  const lines = readFileSync(LOG, 'utf8').split('\n').filter((l) => l.trim())
  if (!lines.length) return 0
  try {
    return Date.parse(JSON.parse(lines[lines.length - 1]).at) || 0
  } catch {
    return 0
  }
}

function runPin(flag) {
  const r = spawnSync('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', PIN, flag], {
    encoding: 'utf8',
  })
  return { code: r.status, out: String(r.stdout || '') + String(r.stderr || '') }
}

const before = readPins()
if (!before) {
  console.error('align: state.json has no pins table; run pin.ps1 -Init once by hand')
  process.exit(2)
}

const ageH = (Date.now() - lastRunMs()) / 3600000
if (!force && ageH < INTERVAL_H) {
  console.log(`align: last run ${ageH.toFixed(1)}h ago (<${INTERVAL_H}h), nothing to do`)
  process.exit(0)
}

const nBefore = Object.keys(before).length
if (!existsSync(ADIR)) mkdirSync(ADIR, { recursive: true })
copyFileSync(STATE, join(ADIR, 'state.before.json'))

const r = runPin('-Init')
if (r.code !== 0) {
  if (!dry) writeFileSync(RED, `${new Date().toISOString()} pin.ps1 -Init exited ${r.code}\n`, 'utf8')
  console.error(`align: pin.ps1 -Init failed (${r.code}); table left as it was`)
  process.exit(1)
}

const after = readPins()
if (!after) {
  if (!dry) copyFileSync(join(ADIR, 'state.before.json'), STATE)
  console.error('align: state.json unreadable after -Init; restored the old table')
  process.exit(1)
}

const nAfter = Object.keys(after).length
const changed = []
const shrunk = []
for (const k of Object.keys(before)) {
  const a = before[k]
  const b = after[k]
  if (b === undefined) continue
  if (String(a) !== String(b)) {
    changed.push(k)
    const na = Number(a)
    const nb = Number(b)
    if (Number.isFinite(na) && Number.isFinite(nb) && nb < na) shrunk.push(k)
  }
}

const loss = nAfter < nBefore
if (loss) {
  // restore the untouched copy even on a dry run: -Init already rewrote state.json
  copyFileSync(join(ADIR, 'state.before.json'), STATE)
  if (!dry) writeFileSync(RED, `${new Date().toISOString()} pin count ${nBefore} -> ${nAfter}; restored old table\n`, 'utf8')
  console.error(`align: REFUSED, pin count ${nBefore} -> ${nAfter} (loss). Old table restored, see track/align.red`)
  process.exit(1)
}
if (!dry && existsSync(RED)) writeFileSync(RED, '', 'utf8')

const rec = {
  at: new Date().toISOString(),
  pins_before: nBefore,
  pins_after: nAfter,
  changed,
  shrunk,
  dry,
}
console.log(JSON.stringify(rec, null, 1))

if (!dry) {
  appendFileSync(LOG, JSON.stringify(rec) + '\n', 'utf8')
  emit(SELF, 4, 0, changed.length, `align:${nAfter}/${changed.length}`, { rush: 0 })
} else {
  // --dry ran -Init for real, so put the untouched table back: a dry run must not move the baseline
  copyFileSync(join(ADIR, 'state.before.json'), STATE)
  console.log('align: dry run, state.json restored')
}
