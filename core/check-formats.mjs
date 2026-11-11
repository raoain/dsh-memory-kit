// core/check-formats.mjs -- 时间与数字格式的一致性检查（spec.formats 的执行者）。
//
// Why (2026-11-11 user): 「别搞那么些乱七八糟的玩意，像通用骨架一样，搞个信号表，能统一的话就统一」。
// 规则写在 core/spec.json 的 formats 段（唯一出处，改规则改那里，不在这里）：
//   ts / *_ts   = 整数 epoch 毫秒
//   at / *_at   = ISO-8601 字符串
// 这里只做三件：bus 的信号、dispatch 的记录、cites 的记录；发现混用就点名。
// 已知欠账（不在这里判死）：memories.jsonl 的 updated_at 是毫秒——见 track/format-debt.jsonl。
//
// usage: node core/check-formats.mjs [--n 200]

import { readFileSync, existsSync } from 'node:fs'
import { join } from 'node:path'
import { ROOT } from './root.mjs'

const N = (() => { const i = process.argv.indexOf('--n'); return i > 0 ? Number(process.argv[i + 1]) || 200 : 200 })()

function tail (rel, n) {
  const p = join(ROOT, rel)
  if (!existsSync(p)) return { p, rows: [] }
  const lines = readFileSync(p, 'utf8').trim().split(/\r?\n/).filter(Boolean).slice(-n)
  const rows = []
  for (const l of lines) { try { rows.push(JSON.parse(l)) } catch { rows.push(null) } }
  return { p, rows }
}

const isMs = (v) => typeof v === 'number' && Number.isFinite(v) && v > 1e11
const isIso = (v) => typeof v === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/.test(v) && !Number.isNaN(Date.parse(v))

const bad = []
function check (rel, n, fields) {
  const { rows } = tail(rel, n)
  rows.forEach((r, i) => {
    if (!r) { bad.push({ file: rel, line: `last-${rows.length - i}`, why: 'unparsable json' }); return }
    for (const [field, kind] of Object.entries(fields)) {
      if (r[field] === undefined) continue
      const ok = kind === 'ts' ? isMs(r[field]) : isIso(r[field])
      if (!ok) bad.push({ file: rel, field, value: String(r[field]).slice(0, 40), why: kind === 'ts' ? 'expected integer epoch ms' : 'expected ISO-8601 string' })
    }
  })
}

check('track/bus.jsonl', N, { ts: 'ts', at: 'at' })
check('track/dispatch.jsonl', N, { at: 'at' })
check('track/mem-cites.jsonl', N, { at: 'at' })
check('track/index-all.jsonl', N, { updated_at: 'ts' })

// 2026-11-11 用户：「这个应该是你没用标准写的问题」——
// BOM 是格式问题，就归这一项管：数据文件（core/*.json、track/*.json(l)）不许带 BOM，
// 带了机器解析会当场崩（今天 python json 读 format-debt.jsonl 就崩在 BOM 上）。
import { readdirSync } from 'node:fs'

// 只在直接运行时执行（被 import 时什么都不做）；同族教训：没有 main 保护的模块一被 import 就执行主逻辑
const isMain = process.argv[1]?.endsWith('check-formats.mjs')
const bomFiles = []
for (const dir of ['core', 'track']) {
  let names = []
  try { names = readdirSync(join(ROOT, dir)) } catch { continue }
  for (const n of names) {
    if (!/\.(json|jsonl)$/.test(n)) continue
    try {
      const b = readFileSync(join(ROOT, dir, n)).subarray(0, 3)
      if (b[0] === 0xef && b[1] === 0xbb && b[2] === 0xbf) bomFiles.push(`${dir}/${n}`)
    } catch { /* skip */ }
  }
}
for (const f of bomFiles) bad.push({ file: f, why: 'starts with a UTF-8 BOM: machine parsers break on it' })

// 2026-11-11 用户：「依旧不按标准写导致的」——spec.signal.types 说 src 是 number，
// 而 10 个器官都把 SELF 写成字符串（'7'），一起违反了标准。这条把那类写法钉死。
for (const n of readdirSync(join(ROOT, 'core'))) {
  if (!n.endsWith('.mjs')) continue
  let src = ''
  try { src = readFileSync(join(ROOT, 'core', n), 'utf8') } catch { continue }
  if (/const SELF = '\d+'/.test(src)) bad.push({ file: `core/${n}`, why: "const SELF = 'N' (string): spec.signal.types says src is a number" })
  if (/emit\('\d+'/.test(src)) bad.push({ file: `core/${n}`, why: "emit('N', ...): spec.signal.types says src is a number" })
}

const out = { checked: N, violations: bad.length, sample: bad.slice(0, 10), verdict: bad.length ? 'MIXED-TIME-FORMAT' : 'ok' }
console.log(JSON.stringify(out, null, 2))
if (isMain) process.exit(bad.length ? 1 : 0)
