// readgap.mjs - turn-level "answered before looking" detector.
// A turn is a gap when it produced a long answer (>=200 chars) while that same
// turn had no tool call before that answer: the conclusion was not written
// next to a fresh read (AGENTS rule 20). Order matters, so we track the first
// long text and whether any tool call preceded it in the same turn.
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join } from 'node:path'
import { zstdDecompressSync } from 'node:zlib'

const SESS = join(process.env.USERPROFILE || '', '.dsh', 'sessions')
const LONG = 200

function sessions() {
  const out = []
  const walk = (d, depth) => {
    if (depth > 3) return
    let ents = []
    try { ents = readdirSync(d, { withFileTypes: true }) } catch { return }
    for (const e of ents) {
      const p = join(d, e.name)
      if (e.isDirectory()) walk(p, depth + 1)
      else if (e.name === 'session.v4.jsonl.zstd') out.push(p)
    }
  }
  walk(SESS, 0)
  return out
}

function analyze(p) {
  const lines = zstdDecompressSync(readFileSync(p)).toString('utf8').split('\n').filter((l) => l.trim())
  const turns = new Map()
  for (const l of lines) {
    let o
    try { o = JSON.parse(l) } catch { continue }
    const t = o.data?.turn
    if (t === undefined) continue
    if (!turns.has(t)) turns.set(t, { toolBefore: 0, long: [], firstLongNoTool: null })
    const rec = turns.get(t)
    if (o.type === 'tool/call') { rec.toolBefore += 1; continue }
    if (o.type === 'assistant/message') {
      const c = o.data?.message?.content
      if (!Array.isArray(c)) continue
      const txt = c.filter((x) => x.type === 'text').map((x) => x.text).join(' ')
      if (txt.length < LONG) continue
      rec.long.push(txt)
      if (rec.firstLongNoTool === null && rec.toolBefore === 0) rec.firstLongNoTool = txt
    }
  }
  let gap = 0
  let ok = 0
  let noToolTurn = 0
  for (const rec of turns.values()) {
    if (!rec.long.length) continue
    if (rec.firstLongNoTool) gap += 1
    else ok += 1
    if (rec.toolBefore === 0) noToolTurn += 1
  }
  return { turns: turns.size, gap, ok, noToolTurn }
}

const rows = sessions().map((p) => ({ p, ...analyze(p) })).sort((a, b) => b.gap - a.gap)
const label = (p) => p.split(/[\\/]/).filter(Boolean).slice(-2)[0].slice(0, 20)
let gap = 0
let ok = 0
for (const r of rows) { gap += r.gap; ok += r.ok }
console.log(`sessions=${rows.length} gap_turns=${gap} ok_turns=${ok}`)
console.log('detail: ' + rows.slice(0, 6).map((r) => `${label(r.p)}(gap=${r.gap}/ok=${r.ok}/turns=${r.turns})`).join(' '))
console.log('SIG ' + JSON.stringify({ state: gap > 0 ? 1 : 0, counts: [gap, ok] }))
