// scripts-inventory.mjs -- regenerate track/脚本清单.md from the actual files.
//
// Why: the user asked "a script has what inside? I don't even know what it contains."
// Hand-written lists go stale the moment a file is added, so this list is generated:
// run it whenever you want the current truth. Nothing here is hand-maintained.
//
// usage: node scripts-inventory.mjs

import { readdirSync, readFileSync, writeFileSync, statSync } from 'node:fs'
import { join, basename } from 'node:path'
import { ROOT } from './core/root.mjs'

const SKIP = new Set(['node_modules', '.git', 'trash', 'archive'])

function firstComment(file) {
  const name = basename(file)
  const text = readFileSync(file, 'utf8').split('\n').slice(0, 10)
  for (const line of text) {
    const t = line.trim()
    let body = null
    if (t.startsWith('//')) body = t.replace(/^\/\/+\s*/, '')
    else if (t.startsWith('#')) body = t.replace(/^#+\s*/, '')
    if (!body) continue
    const b = body.trim()
    if (!b) continue
    // skip noise lines: the filename itself, usage hints, separators
    if (b === name || b === file) continue
    if (/^用法[:：]/.test(b) || /^usage:/i.test(b)) continue
    if (/^[=\-*_]{3,}$/.test(b)) continue
    // prefer the line that carries a description after "name — ..."
    const cleaned = b.replace(new RegExp('^' + name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '\\s*[—-]\\s*'), '')
    return cleaned.slice(0, 90)
  }
  return '(no header comment)'
}

// who references this file: search every script's text for its basename
function callers(allText, name) {
  const hits = new Set()
  for (const [f, text] of allText) {
    if (f.endsWith(name)) continue
    if (text.includes(name)) hits.add(basename(f))
  }
  return [...hits].sort()
}

const files = []
for (const f of readdirSync(ROOT)) {
  if (f.endsWith('.ps1') || (f.endsWith('.mjs') && !f.startsWith('scripts-inventory'))) files.push(f)
}
for (const f of readdirSync(join(ROOT, 'core'))) {
  if (f.endsWith('.mjs') || f.endsWith('.json')) files.push(join('core', f))
}
for (const f of readdirSync(join(ROOT, 'core'))) {
  if (f.endsWith('.mjs')) files.push(join('core', f))
}

const uniq = [...new Set(files)]
const allText = []
for (const f of uniq) {
  try { allText.push([f, readFileSync(join(ROOT, f), 'utf8')]) } catch { /* binary */ }
}

// 「层」不是看文件名决定的，是看两件事：有没有登记进 registry、会不会吐 SIG。
// 器官 = 登记 + 吐 SIG；工具 = 人用的一次性脚本。两层不能混着谈统一。
const reg = JSON.parse(readFileSync(join(ROOT, 'core', 'registry.json'), 'utf8'))
const organPaths = new Set(
  Object.values(reg.cells || {})
    .filter((c) => c.path)
    .map((c) => String(c.path).replace(/\\/g, '/'))
)

const rows = []
for (const f of uniq.sort()) {
  const p = join(ROOT, f)
  let size = 0
  try { size = statSync(p).size } catch { continue }
  const name = basename(f)
  const text = readFileSync(p, 'utf8')
  const isOrgan = organPaths.has(f.replace(/\\/g, '/'))
  // SIG 可能字面输出（'SIG ' + ...）也可能由 emit() 产生；两种都算，别只认行首
  const emitsSig = /^SIG /m.test(text) || /SIG ['"]/.test(text) || /emit\(/.test(text)

  // 工具契约（spec.tools.contract）：按语言分开量，不能一把尺子量所有文件
  //   .ps1  → 必须有 param() 块；必须点源 _root.ps1
  //   .mjs  → 用 process.argv，不要求 param()
  //   .json → 不是脚本，不参与
  const isPs1 = name.endsWith('.ps1')
  const isMjs = name.endsWith('.mjs')
  const isJson = name.endsWith('.json')
  const isRootDef = name === '_root.ps1' || name === 'root.mjs'
  const hasParam = /param\s*\(/.test(text)
  const exitCodes = [...text.matchAll(/exit\s+(-?\d+)/g)].map((m) => Number(m[1]))
  const badExit = exitCodes.filter((c) => c !== 0 && c !== 1 && c !== 2 && c !== 3)
  // 判据统一（2026-11-09）：契约说的不是「必须 import root.mjs」，而是「不许写死项目根」。
  // 有些工具（load/logsearch/fix-double-bom）不碰项目根，硬要求 import 会把它们判成违规，
  // 于是两把尺子给出两个答案。统一成同一条可判规则后，lint 与本表结论一致。
  const usesRoot = isPs1 ? /_root\.ps1/.test(text) : !/F:[\\/]Tools[\\/]coo-day1/.test(text)
  const violations = []
  if (!isOrgan && !isJson) {
    // _root.ps1 是被点源的根定义，没有输入，不该要求 param（lint 一直是这么豁免的；
    // 两处不豁免就永远互相打脸，这是"没全统一"的最后一条）
    if (isPs1 && !hasParam && !isRootDef) violations.push('无param块')
    if (badExit.length) violations.push('退出码越界:' + [...new Set(badExit)].join('/'))
    if (!isRootDef && !usesRoot) violations.push('未用统一根')
  }

  rows.push({
    file: f,
    kind: name.endsWith('.ps1') ? 'ps1' : name.endsWith('.json') ? 'json' : 'mjs',
    bytes: size,
    layer: isOrgan ? '器官' : '工具',
    sig: isOrgan ? (emitsSig ? '吐' : '不吐(检查!)') : '—',
    violations,
    what: name.endsWith('.json') ? '(data file)' : firstComment(p),
    callers: callers(allText, name),
  })
}

const lines = []
lines.push('# 脚本清单（自动生成，别手改）')
lines.push('')
lines.push(`> 生成时间：${new Date().toISOString()}　共 ${rows.length} 个文件。`)
lines.push('> 重新生成：`node scripts-inventory.mjs`')
lines.push('> 作用列取自文件头注释；调用者列是“谁的正文里提到了这个文件名”，仅供参考。')
lines.push('')
lines.push('## 一、按层（器官 / 工具）')
lines.push('')
lines.push('> **器官**＝登记在 `core/registry.json` 且吐 `SIG`，走总线；**工具**＝人叫它才跑，不吐 SIG。')
lines.push('> 两层不能混着谈「统一」：器官的契约是 SIG，工具的契约写在 `core/spec.json` 的 `tools.contract`（call / exit / report / root）。')
lines.push('')
for (const layer of ['器官', '工具']) {
  const sub = rows.filter((r) => r.layer === layer && r.kind !== 'json')
  lines.push(`### ${layer}（${sub.length} 个）`)
  lines.push('')
  lines.push('| 文件 | 字节 | 吐SIG | 契约违规 | 作用 | 谁提到它 |')
  lines.push('|---|---:|---|---|---|---|')
  for (const r of sub) {
    lines.push(`| \`${r.file}\` | ${r.bytes} | ${r.sig} | ${r.violations.join('；') || '—'} | ${r.what} | ${r.callers.slice(0, 3).join(', ') || '—'} |`)
  }
  lines.push('')
}

const violate = rows.filter((r) => r.violations.length)
lines.push('### 工具契约违规汇总（按 spec.tools.contract 查）')
lines.push('')
if (!violate.length) lines.push('（无）')
else {
  lines.push('| 文件 | 违规项 |')
  lines.push('|---|---|')
  for (const r of violate) lines.push(`| \`${r.file}\` | ${r.violations.join('；')} |`)
}
lines.push('')

const badSig = rows.filter((r) => r.sig === '不吐(检查!)')
if (badSig.length) {
  lines.push('### 登记成器官但不吐 SIG（必须修）')
  lines.push('')
  for (const r of badSig) lines.push(`- \`${r.file}\` — ${r.what}`)
  lines.push('')
}

lines.push('## 二、按类型')
lines.push('')
for (const kind of ['ps1', 'mjs', 'json']) {
  const sub = rows.filter((r) => r.kind === kind)
  lines.push(`### ${kind}（${sub.length} 个）`)
  lines.push('')
  lines.push('| 文件 | 字节 | 层 | 作用 | 谁提到它 |')
  lines.push('|---|---:|---|---|---|')
  for (const r of sub) {
    lines.push(`| \`${r.file}\` | ${r.bytes} | ${r.layer} | ${r.what} | ${r.callers.slice(0, 3).join(', ') || '—'} |`)
  }
  lines.push('')
}

// 没人提到的 = 可能是悬空
const orphans = rows.filter((r) => r.callers.length === 0 && r.kind !== 'json')
lines.push('## 三、没人提到的（可能悬空）')
lines.push('')
if (!orphans.length) lines.push('（无）')
else {
  lines.push('| 文件 | 层 | 作用 |')
  lines.push('|---|---|---|')
  for (const r of orphans) lines.push(`| \`${r.file}\` | ${r.layer} | ${r.what} |`)
}
lines.push('')

writeFileSync(join(ROOT, 'track', '脚本清单.md'), lines.join('\n'), 'utf8')
console.log(JSON.stringify({ files: rows.length, orphans: orphans.length, out: 'track/脚本清单.md' }))
