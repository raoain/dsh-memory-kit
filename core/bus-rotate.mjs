// core/bus-rotate.mjs -- rotate the bus by day: archive raw lines, write a daily summary, clear the live file.
//
// Why: the bus grows forever (3978 lines in two days). It is raw material -- never delete it.
// What this does:
//   1. take every line whose day is before today
//   2. append those lines to track/archive/bus-YYYYMMDD.jsonl  (raw, kept)
//   3. write track/archive/bus-YYYYMMDD.summary.json           (counts by src/state, rush max)
//   4. rewrite track/bus.jsonl with only today's lines
//   5. emit one signal on the bus (src 10 is reserved for body; use 9 pulse? no -- use kind 4 record)
//
// usage:
//   node core/bus-rotate.mjs           rotate now
//   node core/bus-rotate.mjs --dry     report only

import { readFileSync, writeFileSync, appendFileSync, existsSync, mkdirSync } from 'node:fs'
import { join } from 'node:path'
import { emit } from './bus.mjs'

// root comes from core/root.mjs -- do not hardcode the path here
import { ROOT } from './root.mjs'
const BUS = join(ROOT, 'track', 'bus.jsonl')
const ARCH = join(ROOT, 'track', 'archive')
const SELF = 9 // pulse reports rotation too

// 归档的格式不是自己定的，是 spec 定的（2026-11-08 spec v5 加了 archive 段）
const spec = JSON.parse(readFileSync(join(ROOT, 'core', 'spec.json'), 'utf8'))
const ARCH_SPEC = spec.archive || {}
const SUMMARY_REQ = ARCH_SPEC.summary_required || ['day', 'count', 'bySrc', 'byState', 'rushMax']
const RAW_NAME = ARCH_SPEC.raw || 'bus-YYYYMMDD.jsonl'
const SUM_NAME = ARCH_SPEC.summary || 'bus-YYYYMMDD.summary.json'

function archiveName(tpl, day) {
  return tpl.replace('YYYYMMDD', day.replace(/-/g, ''))
}

const dry = process.argv.includes('--dry')

function dayOf(ts) {
  const d = new Date(Number(ts))
  if (Number.isNaN(d.getTime())) return null
  return d.toISOString().slice(0, 10)
}

const today = dayOf(Date.now())
const lines = readFileSync(BUS, 'utf8').split('\n').filter(Boolean)

const old = []
const keep = []
for (const line of lines) {
  let s
  try { s = JSON.parse(line) } catch { keep.push(line); continue }
  const d = dayOf(s.ts)
  if (d && d < today) old.push({ day: d, line, sig: s })
  else keep.push(line)
}

const byDay = {}
for (const o of old) {
  if (!byDay[o.day]) byDay[o.day] = []
  byDay[o.day].push(o)
}

const report = []
for (const [day, rows] of Object.entries(byDay)) {
  const bySrc = {}
  const byState = {}
  let rushMax = 0
  for (const r of rows) {
    bySrc[r.sig.src] = (bySrc[r.sig.src] || 0) + 1
    byState[r.sig.state] = (byState[r.sig.state] || 0) + 1
    const ru = Number(r.sig.rush || 0)
    if (ru > rushMax) rushMax = ru
  }
  // 按 spec 的字段名驱动：spec 要哪个字段就算哪个；要了没有计算器的字段就显式失败
  const CALC = {
    day: () => day,
    count: () => rows.length,
    bySrc: () => bySrc,
    byState: () => byState,
    rushMax: () => rushMax,
  }
  const ordered = {}
  for (const k of SUMMARY_REQ) {
    if (!CALC[k]) throw new Error(`spec requires summary field with no calculator: ${k}`)
    ordered[k] = CALC[k]()
  }
  report.push(ordered)
  if (!dry) {
    if (!existsSync(ARCH)) mkdirSync(ARCH, { recursive: true })
    appendFileSync(join(ARCH, archiveName(RAW_NAME, day)), rows.map((r) => r.line).join('\n') + '\n', 'utf8')
    writeFileSync(join(ARCH, archiveName(SUM_NAME, day)), JSON.stringify(ordered, null, 2) + '\n', 'utf8')
  }
}

if (!dry) {
  writeFileSync(BUS, keep.length ? keep.join('\n') + '\n' : '', 'utf8')
  const total = report.reduce((a, r) => a + r.count, 0)
  if (total > 0) {
    // record the rotation itself (kind 4 = record)
    emit(SELF, 4, 0, total, `rotate:${report.map((r) => r.day + '=' + r.count).join(',')}`, { rush: 0 })
  }
}

console.log(JSON.stringify({ dry, today, rotatedDays: report, movedLines: old.length, keptLines: keep.length }, null, 2))
