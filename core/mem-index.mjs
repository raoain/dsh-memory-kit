// core/mem-index.mjs -- 一张统一索引：不管是"页"还是"记忆条目"，都用同一个编号空间查得到。
//
// Why (2026-11-11 用户): 「这个下沉和那个编号表是能统一的吧？」
// 能统一的是**编号与索引**，不是数据本身：一个文件两个写者必翻车（旧教训），所以这里只**生成**一张索引，
// 不搬任何原文。两个来源各管一段：
//   `core/pages.json` + `core/locales/zh.json` → 页：uid = P<id>（101 起，只增）
//   `memories.jsonl` + `track/mem-tier.jsonl` → 记忆条目：uid = M<seq>
// 输出 `track/index-all.jsonl`（只读派生，随时可重生成；不许手改）。
//
// usage: node core/mem-index.mjs [--write]   # 不给 --write 只打印汇总

import { readFileSync, writeFileSync, existsSync } from 'node:fs'
import { join } from 'node:path'
import { ROOT } from './root.mjs'

const PAGES = join(ROOT, 'core', 'pages.json')
const ZH = join(ROOT, 'core', 'locales', 'zh.json')
const MEM = join(ROOT, 'memories.jsonl')
const TIER = join(ROOT, 'track', 'mem-tier.jsonl')
const OUT = join(ROOT, 'track', 'index-all.jsonl')

function jl (p) {
  try {
    return readFileSync(p, 'utf8').trim().split(/\r?\n/).filter(Boolean)
      .map((l) => { try { return JSON.parse(l) } catch { return null } }).filter(Boolean)
  } catch { return [] }
}
function j (p) { try { return JSON.parse(readFileSync(p, 'utf8')) } catch { return {} } }

function main (argv) {
  const rows = []
  // 页：P<id>
  const pages = j(PAGES)
  const zh = j(ZH)
  for (const id of (pages.ids || [])) {
    rows.push({
      uid: `P${id}`, kind: 'page', id: String(id),
      ref: zh[`page.${id}`] || null, tier: 'static', status: 'active',
      importance: null, updated_at: null,  // pages carry no memory weight or timestamp"
    })
  }
  // 记忆条目：M<seq>（tier 来自下沉快照；没有快照就标 unknown，不猜）
  const tiers = new Map(jl(TIER).map((t) => [String(t.seq), t]))
  for (const r of jl(MEM)) {
    const t = tiers.get(String(r.seq))
    rows.push({
      uid: `M${r.seq}`, kind: 'mem', id: String(r.seq),
      ref: r.zone || r.layer || null, tier: t ? t.tier : 'unknown',
      status: r.status || 'active', importance: Number(r.importance || 1), updated_at: r.updated_at || null,
    })
  }
  const uniq = new Set(rows.map((r) => r.uid))
  if (uniq.size !== rows.length) {
    console.error('refused: duplicate uid (one id, two sources)')
    return 2
  }
  if (argv.includes('--write')) {
    writeFileSync(OUT, rows.map((r) => JSON.stringify(r)).join('\n') + '\n', 'utf8')
    console.log(JSON.stringify({ ok: true, wrote: OUT, rows: rows.length }))
    return 0
  }
  const by = {}
  for (const r of rows) { const k = `${r.kind}/${r.tier}`; by[k] = (by[k] || 0) + 1 }
  console.log(JSON.stringify({
    rows: rows.length, by, sample: rows.slice(0, 3), tierSnapshot: existsSync(TIER),
  }, null, 2))
  return 0
}

if (process.argv[1]?.endsWith('mem-index.mjs')) process.exit(main(process.argv.slice(2)))
