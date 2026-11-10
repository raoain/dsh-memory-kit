// replay.mjs -- backtest: re-judge the archived bus with TODAY'S rules.
//
// Why (2026-11-10 用户：「要么去把以前记忆跑一遍？」): the archive holds ~13k raw lines; replaying
// says one honest thing: **would today's rules have judged differently?** Not "what was true then".
//
// First version counted "archived rows that saw a violation" -- a number biased by how chatty the
// bus was, not by elapsed time (2460 for a daily organ proves it: 48h window cannot trip in 4 days).
// So this version walks a fixed 60 s time grid: silent MINUTES, not row-events.
//
// usage: node core/replay.mjs [--out track/replay.json] [--step 60]
import { readFileSync, writeFileSync, appendFileSync, existsSync, readdirSync } from 'node:fs'
import { join } from 'node:path'
import { ROOT } from './root.mjs'

const ARCH = join(ROOT, 'track', 'archive')
const REG = JSON.parse(readFileSync(join(ROOT, 'core', 'registry.json'), 'utf8'))
const BRAIN = join(ROOT, 'track', 'brain.jsonl')
const argOf = (name, dflt) => {
  const i = process.argv.indexOf(name)
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : dflt
}
const OUT = join(ROOT, argOf('--out', 'track/replay.json'))
const STEP = Math.max(10, Number(argOf('--step', '60'))) * 1000

const rows = []
for (const f of readdirSync(ARCH).filter((x) => /^bus-\d{8}\.jsonl$/.test(x)).sort()) {
  for (const line of readFileSync(join(ARCH, f), 'utf8').split(/\r?\n/)) {
    if (!line.trim()) continue
    try { rows.push(JSON.parse(line)) } catch { /* torn line */ }
  }
}
rows.sort((a, b) => Number(a.ts) - Number(b.ts))
if (!rows.length) {
  console.log('no archived rows')
  process.exit(0)
}

// last report time per src, advanced as we walk the grid
const stamps = {}
for (const r of rows) {
  const s = String(r.src)
  stamps[s] = stamps[s] || []
  stamps[s].push(Number(r.ts))
}
for (const k of Object.keys(stamps)) stamps[k].sort((a, b) => a - b)

function lastAtOrBefore(arr, t) {
  let lo = 0
  let hi = arr.length - 1
  let ans = null
  while (lo <= hi) {
    const mid = (lo + hi) >> 1
    if (arr[mid] <= t) { ans = arr[mid]; lo = mid + 1 } else hi = mid - 1
  }
  return ans
}

const from = Number(rows[0].ts)
const to = Number(rows[rows.length - 1].ts)
// 2026-11-10 用户：「要拿它当结论，得先补一个数据完整性检查」。
// 某一天该器官在归档里一条都没有，那天的「没反应」不能算它的账（归档缺 ≠ 它没报）。
const dayOf = (ts) => new Date(Number(ts)).toISOString().slice(0, 10)
const coverage = {}
for (const r2 of rows) {
  const d = dayOf(r2.ts)
  const s = String(r2.src)
  coverage[d] = coverage[d] || {}
  coverage[d][s] = (coverage[d][s] || 0) + 1
}
const uncoveredMinutes = {}

const silentMinutes = {}
const monitored = {}
for (let t = from; t <= to; t += STEP) {
  for (const [id, cell] of Object.entries(REG.cells || {})) {
    const every = Number(cell.every || 0)
    if (!(every > 0)) continue
    const arr = stamps[id]
    if (!arr || !arr.length) continue
    const last = lastAtOrBefore(arr, t)
    if (last === null) continue
    // 只在"这个器官已经存在"之后才判：第一条信号之前不记账
    monitored[id] = true
    if (t - last > every * 2 * 60000) {
      const d = dayOf(t)
      if (!coverage[d] || !coverage[d][id]) { uncoveredMinutes[id] = (uncoveredMinutes[id] || 0) + STEP / 60000; continue }
      silentMinutes[id] = (silentMinutes[id] || 0) + STEP / 60000
    }
  }
}

const actual = {}
if (existsSync(BRAIN)) {
  for (const line of readFileSync(BRAIN, 'utf8').split(/\r?\n/)) {
    if (!line.trim()) continue
    let rec; try { rec = JSON.parse(line) } catch { continue }
    for (const it of rec.items || []) {
      const k = String(it.organ)
      actual[k] = actual[k] || { id: it.id, rounds: 0, kinds: {} }
      actual[k].rounds += 1
      actual[k].kinds[it.kind] = (actual[k].kinds[it.kind] || 0) + 1
    }
  }
}

// 把"今天规则会判成什么"写成一份 plan（只在状态变化时写，最多 200 条），供 mind --plan 读：
// 这样回放不只比规则，还能让环真的想一遍（不写回 track/brain.jsonl）。
const PLAN_OUT = join(ROOT, "track", "replay-plan.jsonl")
writeFileSync(PLAN_OUT, "", "utf8")
let wrote = 0
let prevSig = ""
for (let t = from; t <= to && wrote < 200; t += STEP) {
  const items = []
  for (const [id, cell] of Object.entries(REG.cells || {})) {
    const every = Number(cell.every || 0)
    if (!(every > 0)) continue
    const arr = stamps[id]
    if (!arr || !arr.length) continue
    const last = lastAtOrBefore(arr, t)
    if (last === null) continue
    if (t - last > every * 2 * 60000) items.push({ organ: Number(id), id: cell.id, kind: "silent", tier: 2, bp: 0, bucket: "observed", remedy: null, judged_by: "replay" })
  }
  if (!items.length) continue
  const sig = items.map((x) => x.id).sort().join(",")
  if (sig === prevSig) continue
  prevSig = sig
  appendFileSync(PLAN_OUT, JSON.stringify({ at: new Date(t).toISOString(), items, counts: { observed: items.length }, state: 1, dispatched: 0, replayed: true }) + "\n", "utf8")
  wrote += 1
}

const report = {
  at: new Date().toISOString(),
  caveat: 'backtest: today\'s registry every + today\'s silent rule over archived rows, on a fixed 60s grid; silentMinutes is the honest metric, not a count of rows',
  span_hours: Number(((to - from) / 3600000).toFixed(1)),
  rows: rows.length,
  days: readdirSync(ARCH).filter((x) => /^bus-\d{8}\.jsonl$/.test(x)).sort(),
  silentMinutes,
  uncoveredMinutes,
  dayCoverage: coverage,
  monitoredOrgans: Object.keys(monitored),
  brainHistory: actual,
}
writeFileSync(OUT, JSON.stringify(report, null, 2) + '\n', 'utf8')
console.log(JSON.stringify({ span_hours: report.span_hours, rows: report.rows, silentMinutes: report.silentMinutes, out: OUT }))
console.log(`SIG {"state":0,"counts":[${Object.keys(silentMinutes).length},${report.rows}]}`)
