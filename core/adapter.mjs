// core/adapter.mjs -- adapters: turn a cell's native output into one standard signal
//
// Organs are not rewritten. Each cell keeps its own output format;
// this layer reads that output and emits { at, src, kind, state, value, evid }.
//
// usage: node core/adapter.mjs <cellId> <nativeOutputFile>

import { readFileSync, existsSync } from 'node:fs'
import { emit } from './bus.mjs'

const cells = JSON.parse(readFileSync(new URL('./registry.json', import.meta.url), 'utf8')).cells
// 映射表（exit→state、state→rush）只在 spec 里定义，不在这儿写死
const SPEC = JSON.parse(readFileSync(new URL('./spec.json', import.meta.url), 'utf8'))

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
    rush: Number(o.rush ?? 0),
    value: counts && counts.length ? counts[0] : 0,
    counts,
    evid: `${cellId}:sig`,
  }
}


const [cellId, file] = process.argv.slice(2)
if (!cellId || !file) {
  console.error('usage: node core/adapter.mjs <cellId> <nativeOutputFile> [--exit N]')
  process.exit(2)
}
const exitIdx = process.argv.indexOf('--exit')
const exitCode = exitIdx >= 0 ? Number(process.argv[exitIdx + 1]) : null
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
// order: SIG line first (the contract). If missing, fall back to the exit code --
// exit code is also a contract, unlike parsing human text.
let parsed = parseSig(text, cell.id)
if (!parsed && exitCode !== null) {
  // 映射表在 spec 里，不在这儿写死（2026-11-08 修：exit 1 = ok-with-warn 曾被错判成 fail）
  const table = SPEC.map?.exit_to_state || { 0: 0, 1: 1, 2: 2, 3: 3 }
  const state = Number(table[String(exitCode)] ?? 3)
  parsed = { kind: cell.kind, state, value: exitCode, evid: `${cell.id}:exit${exitCode}` }
}
if (!parsed) {
  emit(cellId, cell.kind, 3, 0, `${cell.id}:unparsed`, { rush: 1 })
  console.error(`cannot parse native output of ${cell.id} (no SIG line, no --exit given)`)
  process.exit(3)
}
// rush 判据：表也在 spec 里（存续优先 —— 失败=2 不可逆、警告=1 会累积、不知道=1 未知即风险、通过=0）
const rushTable = SPEC.map?.state_to_rush || { 0: 0, 1: 1, 2: 2, 3: 1 }
const derivedRush = Number(rushTable[String(parsed.state)] ?? 1)
const rush = parsed.rush === undefined ? derivedRush : Number(parsed.rush)
// 2026-11-11 用户：「这种表建了你按表来呀」——渠道三档的归属写在 spec.channels.map 里，
// adapter 只查表、不自己判；表里没有的器官落到 spec.channels.default（现在 slow）。
function channelOf (cellId) {
  const C = SPEC.channels || {}
  const one = (C.fast && C.fast.id) || 'fast'
  const map = C.map || {}
  const def = C.default || 'slow'
  const v = map[String(cellId)]
  if (v === one || v === 'steady' || v === 'slow') return v
  return def
}
const channel = channelOf(cellId)
console.log(JSON.stringify(emit(cellId, parsed.kind, parsed.state, parsed.value, parsed.evid, { counts: parsed.counts, rush, channel })))