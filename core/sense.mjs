// sense.mjs -- organ 11 (sense-hub): the way outside text gets in.
// Contract only: one input in, one signal out. Nothing is interpreted here.
//
// usage: node core/sense.mjs --text "..."        (inline text)
//        node core/sense.mjs --file <path>       (read a file)
//        node core/sense.mjs --stdin             (pipe)
//        add --from user|file|web|self             (who said it; default = the source)
//
// What it does: append the raw text to track/in-raw.jsonl (never rewritten), then emit one
// signal src=11 kind=4 value=byte length evid=sense:<source>. Interpretation belongs to the
// thinking layer, not here.
import { readFileSync, appendFileSync, existsSync, mkdirSync } from 'node:fs'
import { join } from 'node:path'
import { ROOT } from './root.mjs'
import { tokens } from './memsearch.mjs'
import { emit } from './bus.mjs'

const arg = (name) => {
  const i = process.argv.indexOf(name)
  return i >= 0 ? process.argv[i + 1] : undefined
}

let text = ''
let source = 'unknown'
if (process.argv.includes('--stdin')) {
  text = readFileSync(0, 'utf8')
  source = 'stdin'
} else if (arg('--text') !== undefined) {
  text = String(arg('--text'))
  source = 'text'
} else if (arg('--file') !== undefined) {
  const p = String(arg('--file'))
  text = readFileSync(p, 'utf8')
  source = 'file'
} else {
  console.error('usage: node core/sense.mjs --text "..." | --file <path> | --stdin')
  process.exit(2)
}

const speaker = String(arg('--from') || source || 'unknown')  // who said it
const rawDir = join(ROOT, 'track')
if (!existsSync(rawDir)) mkdirSync(rawDir, { recursive: true })
const RAW = join(rawDir, 'in-raw.jsonl')
// 2011-11-11 transducer: text -> numbers (see spec.records.in_raw_jsonl and bus counts)
// 先人两条路：①模型打标（embedding/LLM importance）= 外挂算力；②纯统计 = 不依赖模型。这里先用②。
const toks = tokens(text)
const uniq = new Set(toks).size
const histToks = new Set()
try {
  for (const line of readFileSync(RAW, 'utf8').trim().split(/\r?\n/)) {
    if (!line) continue
    let r; try { r = JSON.parse(line) } catch { continue }
    if (typeof r.text === 'string') for (const k of tokens(r.text)) histToks.add(k)
  }
} catch { /* first input ever */ }
const fresh = toks.filter((k) => !histToks.has(k)).length
const novelty = toks.length ? Math.round((fresh / toks.length) * 100) : 0
const counts = [Buffer.byteLength(text, 'utf8'), toks.length, uniq, novelty]
const rec = { at: new Date().toISOString(), source, speaker, bytes: counts[0], words: toks.length, uniq, novelty_pct: novelty, text }
appendFileSync(RAW, JSON.stringify(rec) + '\n', 'utf8')
emit(11, 4, 0, counts[0], `sense:${source}/from:${speaker}/words:${toks.length}/new:${novelty}pct`, { rush: 0, counts })
console.log(`sense: ${counts[0]} bytes from ${source} (speaker ${speaker}, words ${toks.length}, new ${novelty}%)`)
console.log(`SIG {"state":0,"counts":[${rec.bytes},1]}`)
