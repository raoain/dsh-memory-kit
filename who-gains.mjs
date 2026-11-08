// who-gains.mjs -- which files actually gain CAPABILITY from a unification, and which
// just gain tidiness. The point (user, 2026-11-08): "内务 / 功能" is a false split. The
// same edit is capability for one file and cosmetics for another, depending on whether
// anything else depends on that behaviour.
//
// usage: node who-gains.mjs

import { readdirSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { ROOT } from './core/root.mjs'

const reg = JSON.parse(readFileSync(join(ROOT, 'core', 'registry.json'), 'utf8'))
const cells = Object.entries(reg.cells || {})
const organs = cells.filter(([, c]) => c.path)

const ps1All = readdirSync(ROOT).filter((f) => f.endsWith('.ps1'))
const organPs1 = new Set(organs.filter(([, c]) => c.path.endsWith('.ps1')).map(([, c]) => c.path))
const tools = ps1All.filter((f) => !organPs1.has(f))

function usesRoot(f) {
  const t = readFileSync(join(ROOT, f), 'utf8')
  return /_root\.ps1/.test(t)
}

console.log(`organs: ${organs.length}  tools: ${tools.length}`)
console.log('')
console.log('root unification, per file:')
for (const [, c] of organs) {
  if (!c.path.endsWith('.ps1')) continue
  console.log(`  organ  ${c.path.padEnd(28)} ${usesRoot(c.path) ? 'unified' : 'not'}   <- capability: the centre spawns this by path`)
}
for (const f of tools) {
  if (!usesRoot(f)) continue
  console.log(`  tool   ${f.padEnd(28)} unified   <- tidiness only: a person calls it, nothing spawns it`)
}

console.log('')
console.log('the same edit changes kind depending on who depends on it. That is why "housekeeping')
console.log('vs feature" was the wrong label: split by "what depends on this", not by the edit.')
