// count-violations.mjs -- how many contract violations, grouped by kind.
//
// usage: node count-violations.mjs

import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { ROOT } from './core/root.mjs'

const text = readFileSync(join(ROOT, 'track', '脚本清单.md'), 'utf8')
const start = text.indexOf('工具契约违规汇总')
if (start < 0) { console.log('未找到违规汇总段'); process.exit(0) }
const after = text.slice(start + '工具契约违规汇总'.length)
const nextSection = after.search(/\n## /)
const seg = nextSection < 0 ? after : after.slice(0, nextSection)

const rows = seg.split('\n').filter((l) => l.startsWith('| `'))
const byKind = {}
const list = []
for (const r of rows) {
  const cells = r.split('|').map((s) => s.trim())
  const file = (cells[1] || '').replace(/`/g, '')
  const kinds = (cells[2] || '').split('；').map((s) => s.trim()).filter(Boolean)
  list.push({ file, kinds })
  for (const k of kinds) byKind[k] = (byKind[k] || 0) + 1
}

console.log(JSON.stringify({ files: rows.length, byKind, list }, null, 2))
