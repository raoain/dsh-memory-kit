// core/bus.mjs -- bus: every cell speaks one signal format
//
// signal = { at, src, kind, state, value, evid }   (see core/spec.json)
//   at    UTC ISO8601 with Z
//   src   cell id from registry.json
//   kind  1 judge / 2 probe / 3 act / 4 record
//   state 0 pass / 1 warn / 2 fail / 3 unknown
//   value dead value: number or {k:v}, never a sentence
//   evid  evidence code, ASCII only (e.g. verify:47/46/0/0)
//
// usage:
//   node core/bus.mjs emit <src> <kind> <state> <value> [evid]
//   node core/bus.mjs tail [n]

import { appendFileSync, readFileSync, existsSync, mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'

const ROOT = 'F:\\Tools\\coo-day1'
export const BUS = join(ROOT, 'track', 'bus.jsonl')

export function emit(src, kind, state, value, evid = '', extra = {}) {
  if (typeof value === 'string' && value.trim() !== '' && Number.isFinite(Number(value))) value = Number(value)
  const now = new Date()
  const rec = {
    ts: now.getTime(),
    at: now.toISOString(),
    src: String(src),
    kind: Number(kind),
    state: Number(state),
    value,
    evid: String(evid),
    ...extra,
  }
  const dir = dirname(BUS)
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true })
  appendFileSync(BUS, JSON.stringify(rec) + '\n', 'utf8')
  return rec
}

export function tail(n = 10) {
  if (!existsSync(BUS)) return []
  const lines = readFileSync(BUS, 'utf8').split('\n').filter(Boolean)
  return lines.slice(-n).map((l) => {
    try { return JSON.parse(l) } catch { return { bad: l } }
  })
}

if (process.argv[1] && process.argv[1].endsWith('bus.mjs')) {
  const [cmd, ...rest] = process.argv.slice(2)
  if (cmd === 'emit') {
    const [src, kind, state, value, evid] = rest
    if (!src || !kind || state === undefined || value === undefined) {
      console.error('usage: node core/bus.mjs emit <src> <kind> <state> <value> [evid]')
      process.exit(2)
    }
    console.log(JSON.stringify(emit(src, kind, state, value, evid)))
  } else if (cmd === 'tail') {
    for (const r of tail(Number(rest[0]) || 10)) console.log(JSON.stringify(r))
  } else {
    console.error('usage: node core/bus.mjs emit|tail ...')
    process.exit(2)
  }
}