// damage.mjs -- organ 19: the cheap "is the body hurt" check, meant to run BEFORE an action.
//
// Why: a timed health check only tells you it was fine at the last tick. If something is broken
// now and you are about to write on top of it, the periodic check is already stale. This one is
// built to be cheap enough (no subprocess, no network) to run before every change.
//
// It answers one question only: is there visible damage? It does not judge quality, does not
// repair anything, and does not decide that anything died.
//
// usage:
//   node core/damage.mjs          print one line, exit 0 clean / 1 damaged
//   node core/damage.mjs --json   machine form

import { readFileSync, existsSync, readdirSync } from 'node:fs'
import { join } from 'node:path'
import { ROOT } from './root.mjs'

const json = process.argv.includes('--json')
const problems = []

function readJson(rel, label) {
  const p = join(ROOT, rel)
  if (!existsSync(p)) { problems.push(`${label}:missing`); return null }
  try { return JSON.parse(readFileSync(p, 'utf8')) } catch { problems.push(`${label}:unparsable`); return null }
}

const spec = readJson('core/spec.json', 'spec')
const reg = readJson('core/registry.json', 'registry')
readJson('core/immunity.json', 'immunity')
const state = readJson('state.json', 'state')
const center = readJson('track/center.json', 'center')

if (state && (!state.pins || !Object.keys(state.pins).length)) problems.push('pins:empty')
if (center && Array.isArray(center.overdue) && center.overdue.length) problems.push(`overdue:${center.overdue.join(',')}`)

// registered organs must physically exist
if (reg && reg.cells) {
  for (const c of Object.values(reg.cells)) {
    if (c.enabled === false || !c.path) continue
    if (!existsSync(join(ROOT, c.path))) problems.push(`organ-missing:${c.id}`)
  }
}

// the last verify verdict must exist and be recent (a stale verdict is not a clean verdict)
let lastVerify = null
function scan(rel) {
  const p = join(ROOT, rel)
  if (!existsSync(p)) return
  for (const line of readFileSync(p, 'utf8').split('\n')) {
    if (!line.trim()) continue
    let r
    try { r = JSON.parse(line) } catch { continue }
    if (String(r.src) !== '1') continue
    const ts = Number(r.ts) || Date.parse(r.at) || 0
    if (!lastVerify || ts > lastVerify.ts) lastVerify = { ts, state: Number(r.state) }
  }
}
scan('track/bus.jsonl')
const arch = join(ROOT, 'track', 'archive')
if (existsSync(arch)) for (const f of readdirSync(arch).filter((x) => /^bus-\d{8}\.jsonl$/.test(x)).slice(-2)) scan(join('track', 'archive', f))
if (!lastVerify) problems.push('verify:no-verdict')
else if (Date.now() - lastVerify.ts > 30 * 60000) problems.push('verify:stale')
else if (lastVerify.state === 2) problems.push('verify:red')

const out = { ok: problems.length === 0, problems, checked: ['spec', 'registry', 'immunity', 'state', 'center', 'organs', 'verify'] }
if (json) console.log(JSON.stringify(out))
else console.log(out.ok ? `damage: clean (${out.checked.length} checks)` : `damage: ${problems.join(',')}`)
process.exit(out.ok ? 0 : 1)
