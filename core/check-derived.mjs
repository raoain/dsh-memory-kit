// core/check-derived.mjs -- 派生表连续性与可复算：有人手改、或有人悄悄删了一行，都要被抓到。
//
// Why (2026-11-11 用户): 「这玩意以后他自己躯体是不会改，要么就是被入侵了之类，加连续性也会被断了，可以查出来的」。
// 四张表各有一条连续性/可复算口径：
//   1. track/index-all.jsonl   —— 编号集合必须正好等于（pages.ids ∪ memories.seq），多一个少一个都算断
//   2. track/mem-tier.jsonl    —— 行数与 seq 集合必须覆盖 memories 全部（快照不许缺条）
//   3. track/mem-cites.jsonl   —— round 严格递增（不许重复、不许回退）
//   4. track/mem-removal.jsonl —— R 编号必须从 R-0001 起连续（删过的号不回收）
// 只读，不改任何文件。usage: node core/check-derived.mjs [--json]

import { readFileSync, existsSync } from 'node:fs'
import { join } from 'node:path'
import { ROOT } from './root.mjs'

// 只在直接运行时执行（被 import 时什么都不做）；同族教训：没有 main 保护的模块一被 import 就执行主逻辑
const isMain = process.argv[1]?.endsWith('check-derived.mjs')

const P = (rel) => join(ROOT, rel)
function jl (rel) {
  const p = P(rel)
  if (!existsSync(p)) return null
  return readFileSync(p, 'utf8').trim().split(/\r?\n/).filter(Boolean)
    .map((l) => { try { return JSON.parse(l) } catch { return undefined } })
}
function j (rel) { try { return JSON.parse(readFileSync(P(rel), 'utf8')) } catch { return {} } }

const spec = j('core/spec.json') || {}
const problems = []
const report = {}

// 1. index-all 的编号集合
const idx = jl('track/index-all.jsonl')
if (idx) {
  const pages = new Set((j('core/pages.json').ids || []).map((i) => `P${i}`))
  const mems = new Set((jl('memories.jsonl') || []).map((r) => `M${r.seq}`))
  const want = new Set([...pages, ...mems])
  const got = new Set(idx.filter(Boolean).map((r) => r.uid))
  const missing = [...want].filter((u) => !got.has(u))
  const extra = [...got].filter((u) => !want.has(u))
  const badRows = (idx || []).length - (got.size)
  report.indexAll = { rows: idx.length, want: want.size, missing: missing.length, extra: extra.length, malformed: Math.max(0, badRows) }
  if (missing.length) problems.push(`index-all missing ${missing.length} ids (e.g. ${missing.slice(0, 3).join(',')})`)
  if (extra.length) problems.push(`index-all has ${extra.length} unknown ids (e.g. ${extra.slice(0, 3).join(',')})`)
  if (report.indexAll.malformed) problems.push(`index-all has ${report.indexAll.malformed} unparsable rows`)
} else report.indexAll = 'absent'

// 2. mem-tier 快照覆盖
const tier = jl('track/mem-tier.jsonl')
if (tier) {
  const mems = new Set((jl('memories.jsonl') || []).map((r) => String(r.seq)))
  const got = new Set(tier.filter(Boolean).map((r) => String(r.seq)))
  const missing = [...mems].filter((s) => !got.has(s))
  report.memTier = { rows: tier.length, mems: mems.size, missing: missing.length }
  if (missing.length) problems.push(`mem-tier snapshot misses ${missing.length} seqs (stale snapshot: rerun --write)`)
} else report.memTier = 'absent'

// 2.5 分区编号覆盖：每条记忆的 zone 必须在 spec.data.zones 里有编号（没有编号的分区会随改名漂走）
const zoneMap = ((spec.data && spec.data.zones && spec.data.zones.map) || {})
const zoneNames = new Set(Object.values(zoneMap).map(String))
const slug = (z) => String(z || '').replace(/\u5168\u5c40/g, 'global')
const memRows = jl('memories.jsonl') || []
const noZoneId = memRows.filter((r) => r.zone && !zoneNames.has(slug(r.zone))).map((r) => r.zone)
const uniqMissing = [...new Set(noZoneId)]
report.zones = { mapped: zoneNames.size, memRows: memRows.length, unmapped: uniqMissing.length }
if (uniqMissing.length) problems.push(`zones without an id in spec.data.zones: ${uniqMissing.slice(0, 3).join(' | ')} (+${Math.max(0, uniqMissing.length - 3)})`)

// 2.6 出处标签：每条记忆必须有 origin，且只能是 stated / observed / inferred
// 词表唯一出处：core/spec.json -> data.origin.levels（2026-11-11：档案页与记忆条目用同一套，翻译名在 spec 里）
const ORIGINS = new Set(((spec.data && spec.data.origin && spec.data.origin.levels) || ['stated', 'observed', 'inferred']).map(String))
const badOrigin = memRows.filter((r) => !ORIGINS.has(String(r.origin || ''))).map((r) => `${r.seq}:${r.origin || 'none'}`)
report.origin = { total: memRows.length, byOrigin: Object.fromEntries([...ORIGINS].map((k) => [k, memRows.filter((r) => r.origin === k).length])), bad: badOrigin.length }
if (badOrigin.length) problems.push(`memories without a valid origin: ${badOrigin.slice(0, 3).join(',')} (+${Math.max(0, badOrigin.length - 3)})`)

// 3. mem-cites 的 round 连续性
const cites = jl('track/mem-cites.jsonl')
if (cites) {
  let prev = -Infinity
  let dup = 0
  let back = 0
  for (const r of cites) {
    const n = Number(r?.round)
    if (!Number.isFinite(n)) continue
    if (n === prev) dup++
    if (n < prev) back++
    prev = Math.max(prev, n)
  }
  report.memCites = { rows: cites.length, duplicateRound: dup, backwardsRound: back }
  if (dup) problems.push(`mem-cites has ${dup} duplicate round numbers`)
  if (back) problems.push(`mem-cites round went backwards ${back} time(s)`)
} else report.memCites = 'absent'

// 4. mem-removal 的 R 编号连续性
const removals = jl('track/mem-removal.jsonl')
if (removals) {
  const nums = removals.map((r) => Number(String(r?.no || '').replace(/^R-/, ''))).filter(Number.isFinite).sort((a, b) => a - b)
  const gap = nums.length && nums[0] !== 1
  let holes = 0
  for (let i = 1; i < nums.length; i++) if (nums[i] !== nums[i - 1] + 1) holes++
  report.memRemoval = { rows: removals.length, first: nums[0] ?? null, last: nums[nums.length - 1] ?? null, holes }
  if (gap) problems.push(`mem-removal starts at R-${nums[0]} instead of R-0001`)
  if (holes) problems.push(`mem-removal has ${holes} hole(s) in its numbering`)
} else report.memRemoval = 'absent'

const out = { problems: problems.length, list: problems, report, verdict: problems.length ? 'BROKEN-CONTINUITY' : 'ok' }
console.log(JSON.stringify(out, null, 2))
if (isMain) process.exit(problems.length ? 1 : 0)
