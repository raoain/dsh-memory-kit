// check-inventory.mjs -- which scripts cannot say what they do in one line.
//
// A generated list is only useful if the "what" column says something. Entries that
// just repeat the filename, or say "(no header comment)", are the ones that still need
// a first-line comment. Run: node check-inventory.mjs

import { readFileSync } from 'node:fs'
import { join, basename } from 'node:path'
import { ROOT } from './core/root.mjs'

const text = readFileSync(join(ROOT, 'track', '脚本清单.md'), 'utf8')
const rows = text.split('\n').filter((l) => l.startsWith('| `'))

const bad = []
for (const r of rows) {
  const cells = r.split('|').map((s) => s.trim())
  const file = (cells[1] || '').replace(/`/g, '')
  const what = cells[3] || ''
  const nameOnly = what === file || what === basename(file)
  if (nameOnly || what.includes('no header comment')) bad.push({ file, what })
}

console.log(JSON.stringify({ total: rows.length, unresolved: bad.length, list: bad }, null, 2))
