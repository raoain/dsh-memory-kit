// sense.mjs -- organ 11 (sense-hub): the way outside text gets in.
// Contract only: one input in, one signal out. Nothing is interpreted here.
//
// usage: node core/sense.mjs --text "..."        (inline text)
//        node core/sense.mjs --file <path>       (read a file)
//        node core/sense.mjs --stdin             (pipe)
//
// What it does: append the raw text to track/in-raw.jsonl (never rewritten), then emit one
// signal src=11 kind=4 value=byte length evid=sense:<source>. Interpretation belongs to the
// thinking layer, not here.
import { readFileSync, appendFileSync, existsSync, mkdirSync } from 'node:fs'
import { join } from 'node:path'
import { ROOT } from './root.mjs'
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

const rawDir = join(ROOT, 'track')
if (!existsSync(rawDir)) mkdirSync(rawDir, { recursive: true })
const RAW = join(rawDir, 'in-raw.jsonl')
const rec = { at: new Date().toISOString(), source, bytes: Buffer.byteLength(text, 'utf8'), text }
appendFileSync(RAW, JSON.stringify(rec) + '\n', 'utf8')
emit(11, 4, 0, rec.bytes, `sense:${source}`, { rush: 0 })
console.log(`sense: ${rec.bytes} bytes from ${source}`)
console.log(`SIG {"state":0,"counts":[${rec.bytes},1]}`)
