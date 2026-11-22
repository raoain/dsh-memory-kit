// 修 record-shape 的 53 处：只改形状，不改语义。2026-11-22
// 依据：core/spec.json 的 records 声明；规矩见 2-档案「文本与数据写法：统一标准」七条。
import fs from 'node:fs'
import path from 'node:path'
const ROOT = 'F:/Tools/coo-day1'
const stamp = '20261122'
const log = []

function backup(rel) {
  const src = path.join(ROOT, rel)
  const dst = src + '.bak-' + stamp
  if (!fs.existsSync(dst)) fs.copyFileSync(src, dst)
  return dst
}
function readLines(rel) {
  return fs.readFileSync(path.join(ROOT, rel), 'utf8').split('\n').filter((l) => l.trim())
}
function writeLines(rel, arr) {
  fs.writeFileSync(path.join(ROOT, rel), arr.join('\n') + '\n', 'utf8')
}

// 1) events.jsonl：src 为 number 的行改成十进制字符串
{
  const rel = 'track/events.jsonl'
  backup(rel)
  const lines = readLines(rel)
  let n = 0
  const out = lines.map((l) => {
    const o = JSON.parse(l)
    if (typeof o.src === 'number') { o.src = String(o.src); n++ }
    return JSON.stringify(o)
  })
  writeLines(rel, out)
  log.push(`events.jsonl: src number->string ${n} 行；总行 ${out.length}`)
}

// 2) watchdog.heal.jsonl：缺 note 的补 null（声明允许 string|null）
{
  const rel = 'track/watchdog.heal.jsonl'
  backup(rel)
  const lines = readLines(rel)
  let n = 0
  const out = lines.map((l) => {
    const o = JSON.parse(l)
    if (!('note' in o)) { o.note = null; n++ }
    return JSON.stringify(o)
  })
  writeLines(rel, out)
  log.push(`watchdog.heal.jsonl: 补 note:null ${n} 行；总行 ${out.length}`)
}

// 3) brain.jsonl：缺 counts/state/evid 的补上；state 置 3（unknown，该行本来没有判定）
{
  const rel = 'track/brain.jsonl'
  backup(rel)
  const lines = readLines(rel)
  let n = 0
  const out = lines.map((l) => {
    const o = JSON.parse(l)
    let touched = false
    if (!('counts' in o)) { o.counts = {}; touched = true }
    if (!('state' in o)) { o.state = 3; touched = true }
    if (!('evid' in o)) { o.evid = ''; touched = true }
    if (touched) n++
    return JSON.stringify(o)
  })
  writeLines(rel, out)
  log.push(`brain.jsonl: 补 counts/state(3=unknown)/evid ${n} 行；总行 ${out.length}`)
}

// 4) 写完当场验：每行都能解析，字段类型与 spec 一致
const spec = JSON.parse(fs.readFileSync(path.join(ROOT, 'core/spec.json'), 'utf8'))
const kindOf = (v) => (Array.isArray(v) ? 'array' : v === null ? 'null' : typeof v)
const wantOk = (w, v) => {
  w = String(w).toLowerCase()
  const k = kindOf(v)
  if (k === 'null') return w.includes('null')
  if (w.startsWith('number')) return k === 'number'
  if (w.startsWith('string')) return k === 'string'
  if (w.startsWith('array')) return k === 'array'
  if (w.startsWith('object')) return k === 'object'
  if (w.startsWith('boolean')) return k === 'boolean'
  return true
}
let bad = 0
for (const [key, d] of Object.entries(spec.records || {})) {
  if (key === 'note') continue
  let raw = ''
  try { raw = fs.readFileSync(path.join(ROOT, d.file), 'utf8') } catch { continue }
  const objs = d.one_object ? [JSON.parse(raw)] : raw.split('\n').filter((l) => l.trim()).map((l) => JSON.parse(l))
  for (const o of objs) {
    for (const [f, want] of Object.entries(d.fields || {})) {
      if (!(f in o) || !wantOk(want, o[f])) bad++
    }
  }
}
log.push(bad === 0 ? '复验：形状不符 0 处' : `复验：仍有 ${bad} 处不符`)
console.log(log.join('\n'))
