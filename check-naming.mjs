// check-naming.mjs -- is the same concept DEFINED in more than one place?
//
// 2026-11-08 correction: the first version counted every occurrence, so $Root showed 207
// hits even after unifying — but 206 of those are *uses* of the single definition. A use is
// fine; a second definition is the problem. Count definitions only.
//
// usage: node check-naming.mjs

import { readdirSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { ROOT } from './core/root.mjs'

const ps1 = readdirSync(ROOT).filter((f) => f.endsWith('.ps1') || f.endsWith('.vbs'))
const mjs = readdirSync(join(ROOT, 'core')).filter((f) => f.endsWith('.mjs')).map((f) => join('core', f))
const files = [...ps1, ...mjs]

function read(f) {
  try { return readFileSync(join(ROOT, f), 'utf8') } catch { return '' }
}

// concept -> lines that DEFINE it (assignment), not use it
const DEF = {
  root: [
    /^\s*\$Root\s*=\s*'/i,
    /^\s*\$base\s*=\s*'/i,
    /^const ROOT\s*=/,
  ],
  evidence: [
    /^\s*\$Evid\s*=\s*'/i,
  ],
  outputFile: [
    /^\s*\$Out(File)?\s*=/i,
  ],
}

const report = {}
for (const [concept, pats] of Object.entries(DEF)) {
  const hits = []
  for (const f of files) {
    const text = read(f)
    text.split('\n').forEach((line, i) => {
      if (pats.some((p) => p.test(line))) hits.push({ file: f, line: i + 1, text: line.trim() })
    })
  }
  report[concept] = { definitions: hits.length, where: hits }
}

// hardcoded absolute root that is NOT a definition (missed earlier)
const literal = []
for (const f of files) {
  const text = read(f)
  text.split('\n').forEach((line, i) => {
    if (/F:\\Tools\\coo-day1/.test(line) && !/^\s*#/.test(line) && !/^\s*\/\//.test(line)) {
      literal.push({ file: f, line: i + 1, text: line.trim().slice(0, 80) })
    }
  })
}

console.log(JSON.stringify({ definitions: report, hardcodedPathLines: literal.length, samples: literal.slice(0, 12) }, null, 2))
