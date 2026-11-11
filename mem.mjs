// mem.mjs — 自己的记忆索引：导出 + 自己的排序（不依赖插件）
//
// 为什么要这个：meow 插件的检索排序我控制不了，它给我什么我就想起什么。
// 这份是「骨」：把库导出成本地 JSONL，用自己的 BM25 排序，可备份、可审计、可替换。
//
// 用法：
//   node mem.mjs dump                  # 从 meow 库导出 -> memories.jsonl
//   node mem.mjs find "引脚 墓碑" 5      # 自己的排序，返回前 5 条
//   node mem.mjs stats                 # 看索引导出情况

import { readFileSync, writeFileSync, appendFileSync, existsSync } from 'node:fs'
import { DatabaseSync } from 'node:sqlite'
import { join } from 'node:path'
import { ROOT } from './core/root.mjs'

// DB 是外部的（meow 数据目录），不属于本项目根，所以它走环境变量 + 显式默认值
const DB = process.env.MEOW_DB || 'C:/Users/Administrator/Documents/deepseek-harness/default-workspace/.dsh-meow/memory.db'
// 导出文件属于本项目，根从 core/root.mjs 拿，不再写死
const OUT = join(ROOT, 'memories.jsonl')
const LAYERS = ['soul', 'user', 'project', 'fact', 'lesson', 'topic', 'rules']

const [cmd, ...rest] = process.argv.slice(2)

// 2026-11-11 用户：「思考层先做记忆，然后再思考运用」——先把存储层做成可读的结构：
//   zone = <project>/<layer>（分区，给人看、给环按区读）
//   seq  = 只增不改的编号，存在 track\mem-seq.json，同一 id 永远同一个号（删号留空，不重排）
const SEQ_FILE = join(ROOT, 'track', 'mem-seq.json')
function loadSeq() { try { return JSON.parse(readFileSync(SEQ_FILE, 'utf8')) } catch { return {} } }
function saveSeq(m) { try { writeFileSync(SEQ_FILE, JSON.stringify(m, null, 2), 'utf8') } catch { /* 写不进不阻断导出 */ } }

function dump() {
  const db = new DatabaseSync(DB, { readOnly: true })
  const seq = loadSeq()
  let maxSeq = Math.max(0, ...Object.values(seq).map((n) => Number(n) || 0))
  const rows = []
  for (const layer of LAYERS) {
    let list = []
    try { list = db.prepare(`select * from ${layer}`).all() } catch { continue }
    for (const r of list) {
      const project = r.project ?? ''
      const zone = project ? `${project}/${layer}` : layer
      if (!seq[r.id]) { maxSeq += 1; seq[r.id] = maxSeq }
      rows.push({
        id: r.id, layer, project, subcategory: r.subcategory ?? '',
        zone, seq: seq[r.id],
        status: r.status ?? 'active', importance: Number(r.importance ?? 1),
        content: r.content ?? '', keywords: r.keywords ?? '',
        updated_at: Number(r.updated_at ?? 0),
      })
    }
  }
  saveSeq(seq)
  const active = rows.filter((r) => r.status === 'active' || r.status === 'stale')
  writeFileSync(OUT, active.map((r) => JSON.stringify(r)).join('\n') + '\n', 'utf8')
  console.log(JSON.stringify({ ok: true, total: rows.length, exported: active.length, seq_assigned: maxSeq, out: OUT }))
}

// 中文按 bigram 切；英文/数字按词切
function tokens(s) {
  const t = String(s).toLowerCase()
  const out = []
  for (const w of t.match(/[a-z0-9_.\-]{2,}/g) ?? []) out.push(w)
  const han = t.replace(/[^\u4e00-\u9fa5]/g, '')
  for (let i = 0; i < han.length - 1; i++) out.push(han.slice(i, i + 2))
  return out
}

function find(query, k = 5) {
  if (!existsSync(OUT)) { console.error('没有索引，先跑 dump'); process.exit(1) }
  const docs = readFileSync(OUT, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l))
  const q = tokens(query)
  const N = docs.length || 1
  // 预计算 df
  const df = new Map()
  const docToks = docs.map((d) => tokens(`${d.content} ${d.keywords} ${d.project}`))
  for (const toks of docToks) {
    for (const t of new Set(toks)) df.set(t, (df.get(t) ?? 0) + 1)
  }
  const avgLen = docToks.reduce((a, t) => a + t.length, 0) / N || 1
  const k1 = 1.2, b = 0.75
  const now = Date.now()
  const scored = docs.map((d, i) => {
    const toks = docToks[i]
    const len = toks.length || 1
    const tf = new Map()
    for (const t of toks) tf.set(t, (tf.get(t) ?? 0) + 1)
    let score = 0
    for (const term of q) {
      const f = tf.get(term) ?? 0
      if (!f) continue
      const idf = Math.log(1 + (N - (df.get(term) ?? 0) + 0.5) / ((df.get(term) ?? 0) + 0.5))
      score += idf * (f * (k1 + 1)) / (f + k1 * (1 - b + b * len / avgLen))
    }
    // 时间衰减（30 天半衰）+ 重要性加成 + 被读次数 + 完结降权
    const days = Math.max(0, (now - d.updated_at) / 86400000)
    score *= Math.pow(0.5, days / 30)
    score *= 1 + 0.15 * Math.min(d.importance, 4)
    // 被读过几次（对数平滑，避免热条目垄断）
    score *= 1 + 0.12 * Math.log(1 + (d.hits || 0))
    if (d.status === 'stale') score *= 0.6
    return { d, score }
  }).filter((x) => x.score > 0).sort((a, b) => b.score - a.score).slice(0, k)

  // 命中即计一次（这就是「被回忆」的凭证）
  if (scored.length) {
    const now2 = Date.now()
    for (const { d } of scored) { d.hits = (d.hits || 0) + 1; d.last_hit = now2 }
    const hitIds = new Set(scored.map((x) => x.d.id))
    const out = docs.map((d) => (hitIds.has(d.id) ? d : d))
    try { writeFileSync(OUT, out.map((d) => JSON.stringify(d)).join('\n') + '\n', 'utf8') } catch (e) { console.error('回写失败: ' + e.message) }
  }
  for (const { d, score } of scored) {
    const head = d.content.replace(/\s+/g, ' ').slice(0, 110)
    console.log(`[${score.toFixed(2)}] ${d.layer}/${d.project || '-'} ${d.id.slice(0, 12)}`)
    console.log(`   ${head}`)
  }
  if (!scored.length) console.log('（没有命中）')
}

function stats() {
  if (!existsSync(OUT)) { console.log('没有索引'); return }
  const docs = readFileSync(OUT, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l))
  const by = {}
  for (const d of docs) by[d.layer] = (by[d.layer] ?? 0) + 1
  console.log(JSON.stringify({ total: docs.length, by }, null, 2))
}

function add(argv) {
  // 用法：node mem.mjs add <layer> <project> "<内容>" ["关键词1,关键词2"]
  const [layer, project, content, kws] = argv
  if (!layer || !content) { console.error('用法：add <layer> <project> "<内容>" ["k1,k2"]'); process.exit(2) }
  const now = Date.now()
  const id = 'local-' + now.toString(36) + Math.random().toString(36).slice(2, 6)
  const rec = {
    id, layer, project: project || '全局', subcategory: '', status: 'active',
    importance: 2, content, keywords: kws || '', updated_at: now, source: 'local',
  }
  appendFileSync(OUT, JSON.stringify(rec) + '\n', 'utf8')
  console.log(JSON.stringify({ ok: true, id, layer, project: rec.project }))
}
if (cmd === 'dump') dump()
else if (cmd === 'find') find(rest[0] ?? '', Number(rest[1] ?? 5))
else if (cmd === 'stats') stats()
else if (cmd === 'add') add(rest)
else console.log('用法：node mem.mjs dump | find "查询" [k] | stats')
