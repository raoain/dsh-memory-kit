// what-remains.mjs -- honest inventory of what is still unsolved.
//
// Written as a file because inline regex through PowerShell keeps losing backslashes.

import { readFileSync, existsSync } from 'node:fs'
import { join } from 'node:path'
import { ROOT } from './core/root.mjs'

const reg = JSON.parse(readFileSync(join(ROOT, 'core', 'registry.json'), 'utf8'))
const empty = Object.entries(reg.cells).filter(([, c]) => !c.path).map(([k, c]) => `${k}:${c.id}`)

const reflex = readFileSync(join(ROOT, 'core', 'reflex.mjs'), 'utf8')
const rules = JSON.parse(readFileSync(join(ROOT, 'core', 'rules.json'), 'utf8'))
const ruleStates = (rules.rules || []).map((r) => r.when?.state ?? r.state ?? null).filter((v) => v !== null)

const out = {
  没实现的器官位: empty,
  'reflex 有比较逻辑': /baseline|expected|threshold|drift/i.test(reflex),
  'rules.json 里的 state 字面量': ruleStates,
  'check-source-language.mjs 存在': existsSync(join(ROOT, 'check-source-language.mjs')),
  'start-timers.vbs 存在': existsSync(join(ROOT, 'start-timers.vbs')),
  'locales 目录存在': existsSync(join(ROOT, 'track', 'locales')),
}
console.log(JSON.stringify(out, null, 2))
