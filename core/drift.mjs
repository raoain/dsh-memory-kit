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
//
// 2026-11-08 v3, after a real fault test: the heartbeat was stopped for 103 seconds
// (completely dead -- it should beat every 3 s) and this reported state=0 value=645bp,
// i.e. it said everything was fine. Cause: a single 30-minute window averages a short
// outage away. 103 s of death inside 1800 s of window is only 6% of samples.
// Fix = what SLO burn-rate alerting actually does: judge SEVERAL windows at once and take
// the worst. A short window catches acute failure; a long one catches slow decay.
function violatedSamples(stamps, limitMs, winMs) {
  if (!stamps.length) return { violated: 0, total: 0, last: null, window_ms: winMs }
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

// window set: the short one guards against acute failure, the long one against slow decay.
// Both must be longer than the observed period (a window shorter than the period measures
// the window, not the organ).
function windowsFor(limitMs) {
  const short = Math.max(5 * 60 * 1000, limitMs * 2)
  const long = Math.max(30 * 60 * 1000, limitMs * 2)
  return short === long ? [long] : [short, long]
}

function judge(what, limitMs, stamps) {
  const wins = windowsFor(limitMs)
  let worst = { violated: 0, total: 0, bp: 0, window_ms: 0 }
  for (const w of wins) {
    const st = violatedSamples(stamps, limitMs, w)
    const bp = st.total ? Math.round((st.violated / st.total) * 10000) : 0
    if (bp > worst.bp) worst = { ...st, bp, window_ms: w }
  }
  // also keep the acute reading separately so a short outage is never hidden by a long window
  const acute = violatedSamples(stamps, limitMs, wins[0])
  const acuteBp = acute.total ? Math.round((acute.violated / acute.total) * 10000) : 0
  return { what, limit_ms: limitMs, bp: worst.bp, window_ms: worst.window_ms, acute_bp: acuteBp, last: worst.last }
}

// 1) heartbeat
const hbLimit = esper.heartbeat.interval_ms * esper.heartbeat.tolerance
rows.push(judge('heartbeat', hbLimit, bySrc.get('7') || []))

// 2) organs with a cadence
for (const [id, cell] of Object.entries(REG.cells || {})) {
  if (!cell.path) continue
  const every = Number(cell.every ?? 0)
  if (!(every > 0)) continue
  const limit = every * 60 * 1000 * 2
  rows.push(judge(`organ_${id}_${cell.id}`, limit, bySrc.get(String(id)) || []))
}

// the reported value is the worst of (worst window bp, acute window bp). The acute reading is
// folded in so a short outage can never be averaged away by the long window.
let worstBp = 0
for (const r of rows) {
  r.bp = Math.max(r.bp || 0, r.acute_bp || 0)
  if (r.bp > worstBp) worstBp = r.bp
}

// a row counts as breached when any window says so
const breached = rows.filter((r) => r.bp > 0)

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
