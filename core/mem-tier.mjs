// core/mem-tier.mjs -- 记忆下沉报告：哪些条算热的、哪些条该沉、按哪条规则沉。
//
// Why (2026-11-11 用户): 「哪些条沉了、沉到哪、按什么规则沉，都查不到……建个表，一种记忆的下沉优先级和原因的表」。
// 先人智慧（借骨架不借阈值）：MemGPT 把上下文分成 main / external 两层；操作系统换页用 LRU/ARC——
//   **按"最近 + 频繁"两件事算，不只按最近**；Generative Agents 用 recency x importance x relevance 打分。
// 我们的打分：score = recency(30 天半衰) x importance x status_weight。
// 判据层（rules/soul/user）**永不自动下沉**：一条判据变冷，是系统坏了，不是系统整洁了。
//
// usage:
//   node core/mem-tier.mjs               # 汇总（热/温/冷各多少条 + 冷的前 10 条）
//   node core/mem-tier.mjs --list cold 30
//   node core/mem-tier.mjs --write       # 把每条 tier 写进 track/mem-tier.jsonl（快照，可查）
//
// 只读：默认不写任何文件。

import { readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { ROOT } from './root.mjs'
import { decay, statusFactor } from './memsignal.mjs'

// 2026-11-11 合并进 spec：thresholds live in core/spec.json -> memory.tier
const RULES = (() => {
  try {
    const s = JSON.parse(readFileSync(join(ROOT, 'core', 'spec.json'), 'utf8'))
    return (s.memory && s.memory.tier) || {}
  } catch { return {} }
})()
const MEM = join(ROOT, 'memories.jsonl')
const OUT = join(ROOT, 'track', 'mem-tier.jsonl')

function rows () {
  try {
    return readFileSync(MEM, 'utf8').trim().split(/\r?\n/).filter(Boolean)
      .map((l) => { try { return JSON.parse(l) } catch { return null } }).filter(Boolean)
  } catch { return [] }
}

// updated_at 在导出里是 epoch 毫秒（数字），也可能是 ISO 字符串——两种都要认（只认一种就会全判成"没有时间戳"）。
function tsOf (v) {
  if (v === null || v === undefined) return 0
  const n = Number(v)
  if (Number.isFinite(n) && n > 1e11) return n
  return Date.parse(String(v)) || 0
}

// 时间衰减与状态权重从 core/memsignal.mjs 取（唯一实现）；tier 的阈值仍在本目录的 mem-tier.json。
function recency (updatedAt, now) {
  const t = tsOf(updatedAt)
  if (!t) return 0
  return decay((now - t) / 86400000)
}

function classify (r, now) {
  const layer = String(r.layer || '')
  if ((RULES.never_cold_layers || []).includes(layer)) {
    return { tier: 'hot', score: null, reason: 'never-cold', ageDays: null }
  }
  const imp = Number(r.importance || 1)
  const sw = statusFactor(r.status)
  const rc = recency(r.updated_at, now)
  const score = Number((rc * imp * sw).toFixed(3))
  const t = tsOf(r.updated_at)
  const ageDays = t ? Number(((now - t) / 86400000).toFixed(1)) : null
  if (sw === 0) return { tier: 'cold', score, reason: 'status-archived', ageDays }
  // 没有时间戳就不许下沉：不知道它多老，不等于它很老（同族：数字弧找不到来源时判"不知道"不判"否"）。
  if (ageDays === null) return { tier: 'warm', score, reason: 'no-timestamp', ageDays }
  if (imp >= RULES.hot.min_importance) return { tier: 'hot', score, reason: 'hot-important', ageDays }
  if (ageDays !== null && ageDays <= RULES.hot.max_age_days) return { tier: 'hot', score, reason: 'hot-recent', ageDays }
  const c = RULES.cold || {}
  if (imp <= (c.or_importance_at_most ?? 1) && ageDays !== null && ageDays >= (c.or_age_days ?? 90)) {
    return { tier: 'cold', score, reason: 'cold-old-low', ageDays }
  }
  if (score <= (c.max_score ?? 1.5)) return { tier: 'cold', score, reason: 'cold-score', ageDays }
  return { tier: 'warm', score, reason: 'warm', ageDays }
}

function main (argv) {
  const now = Date.now()
  const data = rows().map((r) => ({ seq: r.seq, layer: r.layer, importance: r.importance, status: r.status, ...classify(r, now) }))
  const count = (t) => data.filter((x) => x.tier === t).length
  const listIdx = argv.indexOf('--list')
  if (listIdx >= 0) {
    const want = argv[listIdx + 1] || 'cold'
    const n = Number(argv[listIdx + 2] || 20)
    const picked = data.filter((x) => x.tier === want).slice(0, n)
    console.log(JSON.stringify({ tier: want, n: picked.length, items: picked }, null, 2))
    return 0
  }
  if (argv.includes('--write')) {
    writeFileSync(OUT, data.map((x) => JSON.stringify(x)).join('\n') + '\n', 'utf8')
    console.log(JSON.stringify({ ok: true, wrote: OUT, total: data.length }))
    return 0
  }
  const coldTop = data.filter((x) => x.tier === 'cold').sort((a, b) => (a.score ?? 0) - (b.score ?? 0)).slice(0, 10)
  console.log(JSON.stringify({
    total: data.length,
    hot: count('hot'), warm: count('warm'), cold: count('cold'),
    byReason: data.reduce((m, x) => { m[x.reason] = (m[x.reason] || 0) + 1; return m }, {}),
    coldest: coldTop,
    rules: { half_life_days: RULES.half_life_days, never_cold: RULES.never_cold_layers },
  }, null, 2))
  return 0
}

if (process.argv[1]?.endsWith('mem-tier.mjs')) process.exit(main(process.argv.slice(2)))
