// 在会话日志里找「为什么要整体发」的原文（用户提示关键词：起点 / 论道）
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join } from 'node:path'
import { zstdDecompressSync } from 'node:zlib'

const ROOT = process.env.DSH_HOME ? join(process.env.DSH_HOME, 'sessions') : join(process.env.USERPROFILE || '', '.dsh', 'sessions')
const PATS = [/整体.{0,12}发/, /发.{0,12}整体/, /一步接一环/, /一次.{0,6}推完/, /起点.{0,20}(发|给|讲)/]
const hits = []

function walk (dir, depth = 0) {
  if (depth > 3) return
  let ents = []
  try { ents = readdirSync(dir, { withFileTypes: true }) } catch { return }
  for (const e of ents) {
    const p = join(dir, e.name)
    if (e.isDirectory()) { walk(p, depth + 1); continue }
    if (!/session.*\.jsonl\.zstd$/.test(e.name)) continue
    let txt
    try { txt = zstdDecompressSync(readFileSync(p)).toString('utf8') } catch { continue }
    for (const line of txt.split('\n')) {
      if (!line.includes('"user"')) continue
      if (!PATS.some((r) => r.test(line))) continue
      let m
      try { m = JSON.parse(line) } catch { continue }
      const c = m?.data?.content
      const body = Array.isArray(c) ? c.map((x) => x?.text || '').join(' ') : String(c || '')
      if (!body) continue
      if (body.includes('meow-memory') || body.includes('长期记忆') || body.includes('记忆整理任务')) continue
      hits.push({ f: p, t: m.time, body: body.slice(0, 240) })
    }
  }
}
walk(ROOT)
console.log('sessions root:', ROOT, 'hits:', hits.length)
for (const h of hits.slice(-12)) console.log('---', new Date(h.t).toISOString(), h.f.split('\\').slice(-2)[0], '\n', h.body)
