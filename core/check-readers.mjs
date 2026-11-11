// core/check-readers.mjs -- 单一受体检查：每个数据文件只该有一个"读它的地方"。
//
// Why (2026-11-11 用户): 「同一个数据文件如果由两个写入方写，必然出问题。你就跟那个信号表一样，
//   有那些全部的编号，但是他们只有单一受体来读取，他们自己需要的不就好了」。
// 做法：把 core/*.mjs 里所有 `readFileSync(...)` 指向的数据文件抽出来，按文件统计"谁在读"。
//   - 0 个读者：这份数据没人要（悬空）
//   - 1 个读者：正好（单一受体）
//   - ≥2 个读者：**报出来**，要么合并读取入口，要么说清为什么两个都要读
// 只读分析，不改任何文件。
//
// usage: node core/check-readers.mjs [--json]

import { readdirSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { ROOT } from './root.mjs'

const isMain = process.argv[1]?.endsWith('check-readers.mjs')  // import 时不执行（同族教训）

const CORE = join(ROOT, 'core')
const files = readdirSync(CORE).filter((f) => f.endsWith('.mjs'))

const READ_RE = /readFileSync\(\s*(?:join\(ROOT,\s*)?((?:'[^']*'|"[^"]*")(?:\s*,\s*(?:'[^']*'|"[^"]*"))*)\s*\)/g

function targets (src) {
  const out = new Set()
  let m
  while ((m = READ_RE.exec(src))) {
    const parts = m[1].split(',').map((s) => s.trim().replace(/^['"]|['"]$/g, '')).filter(Boolean)
    if (parts.length && parts[0] === 'ROOT') parts.shift()
    const path = parts.join('/')
    // 只关心数据文件（track/ 与 core/*.json），代码文件不算
    if (/^(track|core)\//.test(path) && /\.(json|jsonl)$/.test(path)) out.add(path)
  }
  return out
}

const byData = new Map()
for (const f of files) {
  let src = ''
  try { src = readFileSync(join(CORE, f), 'utf8') } catch { continue }
  for (const t of targets(src)) {
    if (!byData.has(t)) byData.set(t, [])
    byData.get(t).push(f)
  }
}

const rows = [...byData.entries()].map(([data, readers]) => ({
  data,
  n: readers.length,
  readers: readers.sort(),
  verdict: readers.length === 1 ? 'single' : readers.length === 0 ? 'orphan' : 'MULTI-READER',
})).sort((a, b) => b.n - a.n || a.data.localeCompare(b.data))

// 2026-11-11：区分"标准"与"状态"——标准（spec/registry）多读是对的，做成单一受体反而不通用；
// 只有"状态"文件才要求单写+单一受体，多读必须在 core/readers.json 里登记理由（例外要写明白）。
let policy = { files: {} }
try {
    // 2026-11-11 合并进 spec：policy lives in core/spec.json -> data.readers
    const s = JSON.parse(readFileSync(join(ROOT, 'core', 'spec.json'), 'utf8'))
    policy = { files: (s.data && s.data.readers && s.data.readers.files) || {} }
  } catch { /* 没有策略表就按旧的严格口径 */ }
const kindOf = (d) => (policy.files?.[d]?.kind) || (/(spec|registry)\.json$/.test(d) ? 'config' : 'state')
const excused = (d) => Boolean(policy.files?.[d]?.exception)
const violations = rows.filter((r) => r.verdict === 'MULTI-READER' && kindOf(r.data) === 'state' && !excused(r.data))
const multi = rows.filter((r) => r.verdict === 'MULTI-READER')
const out = {
  dataFiles: rows.length,
  single: rows.filter((r) => r.verdict === 'single').length,
  multi: multi.length,
  multiList: multi.map((r) => ({ data: r.data, readers: r.readers })),
  verdict: violations.length ? 'MULTI-READER: a STATE file has several readers and no registered exception' : 'ok',
  violations: violations.map((r) => r.data),
  rows,
}
if (process.argv.includes('--json')) console.log(JSON.stringify(out, null, 2))
else {
  console.log(JSON.stringify({ dataFiles: out.dataFiles, single: out.single, multi: out.multi, verdict: out.verdict }, null, 2))
  for (const r of multi.slice(0, 15)) console.log(`  MULTI ${r.data} <- ${r.readers.join(', ')}`)
}
if (isMain) process.exit(violations.length ? 1 : 0)
