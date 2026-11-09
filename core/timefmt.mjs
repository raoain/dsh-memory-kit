// core/timefmt.mjs -- time converter (inner = UTC, display = any zone)
// usage:
//   node core/timefmt.mjs 1794019044617
//   node core/timefmt.mjs 2026-11-07T02:37:24.617Z --tz Asia/Shanghai
//   node core/timefmt.mjs --tz Asia/Tokyo --all 3     (last 3 bus signals, local display)

import { readFileSync, existsSync } from 'node:fs'
import { join } from 'node:path'

// root comes from core/root.mjs -- do not hardcode the path here
import { ROOT } from './root.mjs'
const BUS = join(ROOT, 'track', 'bus.jsonl')

function toDate(s) {
  if (/^\d+$/.test(s)) return new Date(Number(s))
  const d = new Date(s)
  return Number.isNaN(d.getTime()) ? null : d
}

function fmt(d, tz) {
  const opts = { year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false }
  if (tz) opts.timeZone = tz
  return new Intl.DateTimeFormat('sv-SE', opts).format(d) + (tz ? ` ${tz}` : ' UTC')
}

const argv = process.argv.slice(2)
const tzIdx = argv.indexOf('--tz')
const tz = tzIdx >= 0 ? argv[tzIdx + 1] : 'UTC'
const allIdx = argv.indexOf('--all')
if (allIdx >= 0) {
  const n = Number(argv[allIdx + 1]) || 5
  if (!existsSync(BUS)) { console.error('no bus'); process.exit(2) }
  const lines = readFileSync(BUS, 'utf8').split('\n').filter(Boolean).slice(-n)
  for (const l of lines) {
    try {
      const r = JSON.parse(l)
      console.log(`${fmt(toDate(String(r.ts)), tz)}  src=${r.src} kind=${r.kind} state=${r.state} value=${r.value} ${r.evid}`)
    } catch { console.log('bad line') }
  }
  process.exit(0)
}
const arg = argv.find((a) => !a.startsWith('--') && a !== tz)
if (!arg) { console.error('usage: node core/timefmt.mjs <ts|iso> [--tz Zone] | --all N'); process.exit(2) }
const d = toDate(arg)
if (!d) { console.error('cannot parse time'); process.exit(3) }
console.log(fmt(d, tz))