// core/adapter.mjs -- adapters: turn a cell's native output into one standard signal
//
// Organs are not rewritten. Each cell keeps its own output format;
// this layer reads that output and emits { at, src, kind, state, value, evid }.
//
// usage: node core/adapter.mjs <cellId> <nativeOutputFile>

import { readFileSync, existsSync } from 'node:fs'
import { emit } from './bus.mjs'

const cells = JSON.parse(readFileSync(new URL('./registry.json', import.meta.url), 'utf8')).cells

function parseVerify(text, exitCode) {
  // native: "47 项：OK 46 / SOFT 1（容差内） / WARN 0 / FAIL 0"
  const m = text.match(/(\d+)\s*项[：:]\s*OK\s*(\d+)[^\d]+SOFT\s*(\d+)[^\d]+WARN\s*(\d+)[^\d]+FAIL\s*(\d+)/)
  if (!m) return null
  const total = Number(m[1]), ok = Number(m[2]), warn = Number(m[4]), fail = Number(m[5])
  const state = fail > 0 ? 2 : warn > 0 ? 1 : 0
  return { kind: 1, state, value: fail, counts: [total, ok, warn, fail], evid: `verify:${total}/${ok}/${warn}/${fail}` }
}

function parsePin(text, exitCode) {
  // native: "3/92 项漂移。确认后跑 -Init 重建..."
  const m = text.match(/(\d+)\s*\/\s*(\d+)\s*项漂移/)
  if (!m) {
    if (/全部已钉|无漂移/.test(text)) return { kind: 1, state: 0, value: 0, evid: 'pin:0/0' }
    return null
  }
  const drift = Number(m[1]), total = Number(m[2])
  return { kind: 1, state: drift > 0 ? 1 : 0, value: drift, evid: `pin:${drift}/${total}` }
}

function readAny(file) {
  // PS 5.1 `*>` writes UTF-16LE with BOM; accept utf16le / utf8-BOM / plain utf8
  const b = readFileSync(file)
  if (b[0] === 0xff && b[1] === 0xfe) return b.toString('utf16le', 2)
  if (b[0] === 0xef && b[1] === 0xbb && b[2] === 0xbf) return b.toString('utf8', 3)
  return b.toString('utf8')
}
// SIG line is the contract: any organ may end its output with
//   SIG {"state":0,"counts":[..]}
// Prefer it over any per-organ text parsing -- layout changes then cannot break the bus.
function parseSig(text, cellId) {
  const m = text.match(/^SIG\s+(\{.*\})\s*$/m)
  if (!m) return null
  let o
  try { o = JSON.parse(m[1]) } catch { return null }
  const counts = Array.isArray(o.counts) ? o.counts.map(Number) : undefined
  return {
    kind: 1,
    state: Number(o.state),
    value: counts && counts.length ? counts[0] : 0,
    counts,
    evid: `${cellId}:sig`,
  }
}

const PARSERS = { '1': parseVerify, '2': parsePin }

const [cellId, file] = process.argv.slice(2)
if (!cellId || !file) {
  console.error('usage: node core/adapter.mjs <cellId> <nativeOutputFile>')
  process.exit(2)
}
const cell = cells[cellId]
if (!cell) {
  console.error(`unknown cell id: ${cellId}`)   // unknown id must error, never ignore
  process.exit(3)
}
if (!existsSync(file)) {
  console.error(`native output not found: ${file}`)
  process.exit(2)
}
const text = readAny(file)
const parser = PARSERS[cellId]
// order: SIG line first (the contract), then the per-organ text parser
const parsed = parseSig(text, cell.id) || (parser ? parser(text, 0) : null) || { kind: cell.kind, state: 3, value: 0, evid: `${cell.id}:unparsed` }
if (parsed.state === 3) {
  emit(cellId, cell.kind, 3, 0, `${cell.id}:unparsed`)
  console.error(`cannot parse native output of ${cell.id}`)
  process.exit(3)
}
console.log(JSON.stringify(emit(cellId, parsed.kind, parsed.state, parsed.value, parsed.evid, parsed.counts ? { counts: parsed.counts } : {})))