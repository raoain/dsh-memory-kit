// core/spec-exceptions.mjs -- 把"个别识别/例外"单独列一条信号，不新增表。
//
// Why (2026-11-11 用户): 「绝大部分都是通用的，除了偶尔一些个别识别需要单独给他列一个信号就好了」。
// 口径：general rules live in core/spec.json; exceptions are FIELDS inside spec (not new tables),
// and this command lists them in one place so nobody has to hunt through the file.
//
// usage: node core/spec-exceptions.mjs [--json]

import { readFileSync, existsSync } from 'node:fs'
import { join } from 'node:path'
import { ROOT } from './root.mjs'

// 只在直接运行时执行（被 import 时什么都不做）；同族教训：没有 main 保护的模块一被 import 就执行主逻辑
const isMain = process.argv[1]?.endsWith('spec-exceptions.mjs')

function j (rel) { try { return JSON.parse(readFileSync(join(ROOT, rel), 'utf8')) } catch { return null } }
function jl (rel) {
  if (!existsSync(join(ROOT, rel))) return []
  return readFileSync(join(ROOT, rel), 'utf8').trim().split(/\r?\n/).filter(Boolean)
    .map((l) => { try { return JSON.parse(l) } catch { return null } }).filter(Boolean)
}

const spec = j('core/spec.json') || {}
const out = []

// 1) data.readers: state files may have several readers only with a written reason
for (const [file, cfg] of Object.entries((spec.data && spec.data.readers && spec.data.readers.files) || {})) {
  if (cfg && cfg.exception) out.push({ kind: 'reader-exception', file, why: cfg.exception })
}

// 2) memory.tier: layers that never sink automatically
const tier = (spec.memory && spec.memory.tier) || {}
for (const layer of (tier.never_cold_layers || [])) {
  out.push({ kind: 'never-cold', layer, why: tier.never_cold_note || '' })
}

// 3) format debt: fields that still break the one-format rule, listed explicitly
// 挂账只有一处：track/known-debt.json（2026-11-11 把 format-debt 并进老件；旧的 jsonl 已删）
for (const d of (j('track/known-debt.json') || [])) {
  if (String(d.kind) === 'format-debt') out.push({ kind: 'format-debt', file: d.where, field: d.field, why: d.why_failed || '', fixed_by: d.fixed_by || '' })
}

// 4) channels override table (registry drives by default; spec only overrides)
const chMap = (spec.channels && spec.channels.map) || {}
for (const [src, ch] of Object.entries(chMap)) out.push({ kind: 'channel-override', src, channel: ch })

if (process.argv.includes('--json')) console.log(JSON.stringify({ n: out.length, items: out }, null, 2))
else {
  console.log(`exceptions: ${out.length}`)
  for (const e of out) console.log(`  [${e.kind}] ${e.file || e.layer || e.src || ''} ${String(e.why || e.channel || '').slice(0, 80)}`)
}
if (isMain) process.exit(0)
