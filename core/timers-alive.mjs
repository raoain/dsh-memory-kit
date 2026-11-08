// core/timers-alive.mjs -- prints how many seconds ago the heartbeat last landed.
//
// One question ("are the timers running?"), one answer (the bus).
// 2026-11-08: the .cmd guard first created its own marker file, which meant the
// same question had two data sources and they disagreed (marker 138s old while
// the bus was 63s old). The bus is the real record; nothing else should decide it.
//
// prints an integer number of seconds (or 9999 when there is no heartbeat at all)
// usage: node core/timers-alive.mjs   输出「多少秒前还有一跳」

import { readFileSync, existsSync } from 'node:fs'
import { join } from 'node:path'
import { ROOT } from './root.mjs'

const BUS = join(ROOT, 'track', 'bus.jsonl')
const MAX_SCAN = 200

if (!existsSync(BUS)) { console.log(9999); process.exit(0) }

const lines = readFileSync(BUS, 'utf8').split('\n').filter(Boolean).slice(-MAX_SCAN)
let last = 0
for (const line of lines) {
  let s
  try { s = JSON.parse(line) } catch { continue }
  if (String(s.src) === '7' && Number(s.ts) > last) last = Number(s.ts)
}
if (!last) { console.log(9999); process.exit(0) }

console.log(Math.max(0, Math.round((Date.now() - last) / 1000)))
