// Shared memory retrieval: one scorer, two callers (2026-11-11).
// Before this, `mem.mjs find` had BM25 and `mind.mjs memHits` had a crude substring match:
// the same question ("which memories are relevant?") had two implementations, and the weak one
// was the one inside the ring. Now both call here.
// Scoring follows the usual combination: BM25 (keyword) x recency half-life x importance x hits,
// stale down-weighted. Prior art: BM25, and Generative Agents' recency+importance+relevance sum.
import { readFileSync, existsSync } from 'node:fs'
import { ROOT } from './root.mjs'
import { join } from 'node:path'
import { signal } from './memsignal.mjs'

export const DOCS = join(ROOT, 'memories.jsonl')

// CJK by bigram, latin/digits by word
export function tokens (s) {
  const t = String(s).toLowerCase()
  const out = []
  for (const w of t.match(/[a-z0-9_.\-]{2,}/g) ?? []) out.push(w)
  const han = t.replace(/[^\u4e00-\u9fa5]/g, '')
  for (let i = 0; i < han.length - 1; i++) out.push(han.slice(i, i + 2))
  return out
}

export function loadDocs (p = DOCS) {
  if (!existsSync(p)) return []
  return readFileSync(p, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l))
}

// returns [{ d, score }] sorted desc, only score > 0, at most k
// `exclude`: seq/id values already read recently — skipped, so the ring does not re-read the same
// few memories every round (2026-11-11: retrieval refinement, "不重复读同一批").
export function search (query, { k = 5, docs = null, docsPath = DOCS, now = Date.now(), exclude = [] } = {}) {
  const all = docs || loadDocs(docsPath)
  if (!all.length) return []
  const ex = new Set(exclude.map((x) => String(x)))
  const q = tokens(query)
  if (!q.length) return []
  const N = all.length
  const docToks = all.map((d) => tokens(`${d.content} ${d.keywords} ${d.project || ''} ${d.zone || ''}`))
  const df = new Map()
  for (const toks of docToks) for (const t of new Set(toks)) df.set(t, (df.get(t) ?? 0) + 1)
  const avgLen = docToks.reduce((a, t) => a + t.length, 0) / N || 1
  const k1 = 1.2, b = 0.75
  const scored = []
  for (let i = 0; i < all.length; i++) {
    const d = all[i]
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
    if (score <= 0) continue
    if (ex.size && (ex.has(String(d.seq)) || ex.has(String(d.id)))) continue // recently read: skip, do not re-feed
    // 四个因子只在 core/memsignal.mjs 里算（2026-11-11 用户：「建一个统一标志表都归纳起来」）：
    // 这里只决定"乘不乘"，不再自己写 30 天/0.15/0.12/0.6 这些数。
    const factor = signal(d, now)
    if (factor <= 0) continue
    score *= factor
    scored.push({ d, score })
  }
  scored.sort((a, b) => b.score - a.score)
  return mmr(scored, k, 0.7)
}

// MMR (maximal marginal relevance, 2026-11-11): pick "relevant but different".
// Without it two near-identical memories can occupy two of k slots (same information twice).
// Adapted to us: lambda 0.7 (relevance weighted higher than diversity), similarity = token jaccard.
function simOf (a, b) {
  const A = new Set(tokens(`${a.content} ${a.keywords || ''}`))
  const B = new Set(tokens(`${b.content} ${b.keywords || ''}`))
  if (!A.size || !B.size) return 0
  let inter = 0
  for (const t of A) if (B.has(t)) inter++
  return inter / (A.size + B.size - inter)
}

function mmr (sorted, k, lambda) {
  if (sorted.length <= 1 || k <= 1) return sorted.slice(0, k)
  const chosen = []
  const rest = sorted.slice()
  const first = rest.shift()
  chosen.push(first)
  while (chosen.length < k && rest.length) {
    let bestI = 0
    let bestV = -Infinity
    for (let i = 0; i < rest.length; i++) {
      const cand = rest[i]
      let maxSim = 0
      for (const c of chosen) maxSim = Math.max(maxSim, simOf(cand.d, c.d))
      const v = lambda * cand.score - (1 - lambda) * maxSim
      if (v > bestV) { bestV = v; bestI = i }
    }
    chosen.push(rest.splice(bestI, 1)[0])
  }
  return chosen
}
