// drift.mjs -- organ 15: the comparison loop (brainstem: measure, compare, adjust).
//
// It does NOT decide, act, or summarize. It measures the gap between the bus and
// spec.expect and reports that gap as a number. Acting on the gap is the immune layer.
//
// 2026-11-08 v2, after checking how the field does it:
//   v1 measured the INSTANT gap (how many ms late right now). That is noisy by nature:
//   restarting the timers made it report state 1 for 21 seconds, then self-clear. The
//   user asked whether to look at prior art first -- the answer was yes, and prior art
//   agrees: SLO burn-rate alerting ([Splunk]) and error-difference rules ([Politecnico di
//   Milano thesis]) both judge a WINDOW, not an instant. An instant is a sample; a window
//   is a signal.
//
// So v2 reports, per expectation, how much of the window was in violation:
//   ratio = violatedSamples / totalSamples   (0..1)
//   value = ratio * 10000                    (basis points, integer -- spec says numbers)
//
// usage: node core/drift.mjs [--dry]

import { readFileSync, existsSync } from 'node:fs'
import { join } from 'node:path'
import { ROOT } from './root.mjs'
import { emit } from './bus.mjs'

const SPEC = JSON.parse(readFileSync(join(ROOT, 'core', 'spec.json'), 'utf8'))
const REG = JSON.parse(readFileSync(join(ROOT, 'core', 'registry.json'), 'utf8'))
const BUS = join(ROOT, 'track', 'bus.jsonl')

const dry = process.argv.includes('--dry')
const now = Date.now()
const WINDOW_MS = 30 * 60 * 1000 // the window prior art calls "short"; long windows need history we rotate away
const SAMPLE_MS = 60 * 1000      // one sample per minute: a heartbeat burst must not drown the mean

function readBus() {
  if (!existsSync(BUS)) return []
  const out = []
  for (const line of readFileSync(BUS, 'utf8').split('\n')) {
    if (!line.trim()) continue
    try { out.push(JSON.parse(line)) } catch { /* skip torn line */ }
  }
  return out
}

const bus = readBus()
const cutoff = now - WINDOW_MS

// group ALL of the bus by src. The window is applied later, per row, because a slow organ
// needs a longer window than the fast one -- building the index from a pre-cut array was a
// real bug (2026-11-08): the per-organ window could not reach data the index had dropped.
const bySrc = new Map()
for (const r of bus) {
  const k = String(r.src)
  if (!bySrc.has(k)) bySrc.set(k, [])
  bySrc.get(k).push(Number(r.ts))
}
const inWindow = bus.filter((r) => Number(r.ts) >= cutoff)

// how many samples were "late"? The window must be longer than the period being observed,
// otherwise the answer measures "the window is too short", not "it is late" (2026-11-08:
// a 30-minute window over a 30-minute organ reported 19% violation that did not exist).
function violatedSamples(stamps, limitMs) {
  if (!stamps.length) return { violated: 0, total: 0, last: null, window_ms: 0 }
  const winMs = Math.max(WINDOW_MS, limitMs * 2)
  const from = now - winMs
  const sorted = [...stamps].sort((a, b) => a - b)
  let violated = 0
  let total = 0
  for (let t = from; t <= now; t += SAMPLE_MS) {
    total++
    let last = null
    for (const s of sorted) { if (s <= t) last = s; else break }
    const age = last === null ? Infinity : t - last
    if (age > limitMs) violated++
  }
  return { violated, total, last: sorted[sorted.length - 1], window_ms: winMs }
}

const esper = SPEC.expect
const rows = []

// 1) heartbeat
const hbLimit = esper.heartbeat.interval_ms * esper.heartbeat.tolerance
const hbStat = violatedSamples(bySrc.get('7') || [], hbLimit)
rows.push({ what: 'heartbeat', limit_ms: hbLimit, ...hbStat })

// 2) organs with a cadence
for (const [id, cell] of Object.entries(REG.cells || {})) {
  if (!cell.path) continue
  const every = Number(cell.every ?? 0)
  if (!(every > 0)) continue
  const limit = every * 60 * 1000 * 2
  const st = violatedSamples(bySrc.get(String(id)) || [], limit)
  rows.push({ what: `organ_${id}_${cell.id}`, limit_ms: limit, ...st })
}

// ratio per row; the reported value is the worst ratio in basis points
let worstBp = 0
for (const r of rows) {
  r.ratio = r.total ? r.violated / r.total : 0
  r.bp = Math.round(r.ratio * 10000)
  if (r.bp > worstBp) worstBp = r.bp
}

// also report the worst change: a row that was fine and just started violating is different
// from one that has been violating the whole window (prior art's "error difference")
const breached = rows.filter((r) => r.ratio > 0)

// severity thresholds live in spec.expect.drift too -- "how much counts as real" is part of
// the expectation, not a number to invent here (2026-11-08).
const th = esper.drift || { state1_bp: 1000, state2_bp: 5000 }
let state = 0
if (!inWindow.length) state = 3
else if (worstBp >= th.state2_bp) state = 2
else if (worstBp >= th.state1_bp) state = 1

const payload = {
  state,
  value: worstBp,
  evid: `drift:${breached.length}/${rows.length}:${worstBp}bp`,
  window_ms: WINDOW_MS,
  rows,
}

if (dry) {
  console.log(JSON.stringify(payload, null, 2))
} else {
  // rush follows the same severity decision as state; mapping it separately here would be a
  // second place where "how urgent is this" gets decided (2026-11-08)
  const rush = SPEC.map.state_to_rush[String(state)] ?? 0
  emit('15', 1, state, worstBp, payload.evid, {
    rush,
    counts: [rows.length, rows.length - breached.length, breached.length, 0],
  })
  console.log(JSON.stringify({ state, value: worstBp, evid: payload.evid, breached: breached.map((b) => `${b.what}:${b.bp}bp`) }))
}
