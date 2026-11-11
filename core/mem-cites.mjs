// core/mem-cites.mjs -- 引用登记表的报告与对账：这一轮引用了哪几条记忆、有没有指到不存在的条目。
//
// Why (2026-11-11 用户): 「"引用可追"只做了一半，看来确实得做个记忆的表了，来标明这个和识别了」。
// 表：track/mem-cites.jsonl（`mind` 每轮写一行：{at, round, n, cited:[seq...]}）。
// 这里只读，不改数据；做三件事：
//   ① 哪些 seq 被引用得最多（哪条记忆真的在承重）；
//   ② 有没有引用到**不存在的 seq**（记忆库里没有 → 坏引用，必须点名）；
//   ③ 有多少轮**一条记忆都没引用**（不是错，但说明这一轮没靠记忆）。
//
// usage: node core/mem-cites.mjs [--top 10]

import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { ROOT } from './root.mjs'

const CITES = join(ROOT, 'track', 'mem-cites.jsonl')
const MEM = join(ROOT, 'memories.jsonl')

function jl (p) {
  try {
    return readFileSync(p, 'utf8').trim().split(/\r?\n/).filter(Boolean)
      .map((l) => { try { return JSON.parse(l) } catch { return null } }).filter(Boolean)
  } catch { return [] }
}

function main (argv) {
  const topN = Number(argv[argv.indexOf('--top') + 1] || 10) || 10
  const rounds = jl(CITES)
  const known = new Set(jl(MEM).map((r) => String(r.seq)))
  const freq = {}
  const bad = []
  let emptyRounds = 0
  for (const r of rounds) {
    const cited = Array.isArray(r.cited) ? r.cited : []
    if (!cited.length) emptyRounds++
    for (const s of cited) {
      freq[s] = (freq[s] || 0) + 1
      if (!known.has(String(s))) bad.push({ round: r.round, seq: s })
    }
  }
  const top = Object.entries(freq).sort((a, b) => b[1] - a[1]).slice(0, topN)
  console.log(JSON.stringify({
    rounds: rounds.length,
    distinctCited: Object.keys(freq).length,
    emptyRounds,
    badCitations: bad.slice(0, 20),
    badCount: bad.length,
    top: top.map(([seq, n]) => ({ seq, n })),
    verdict: bad.length ? 'BAD-CITATION: a conclusion points at a memory that does not exist' : 'ok',
  }, null, 2))
  return bad.length ? 1 : 0
}

if (process.argv[1]?.endsWith('mem-cites.mjs')) process.exit(main(process.argv.slice(2)))
