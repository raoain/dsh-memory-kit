// core/mem-retire.mjs -- 记忆的"卸载"出口：一条记忆被标死后，必须留下一行可查的判决。
//
// Why (2026-11-11 用户): 「为什么标，工程侧没有留痕。现在能删（标 archived），不能解释"为什么删"。
//   你可以建一种表，然后给他上一个编号，然后就知道是怎么删的，或者说什么数据删的。」
// 规矩（`notebook\5-判据.md` 与记忆定位同源）：飞轮要小，只增不减会让纠偏变慢；
//   但**卸载的唯一出口是墓碑**——不是悄悄从文件里消失。
//
// usage:
//   node core/mem-retire.mjs <seq> --why "原因" [--by user|rule:P35|auto:immunity] [--action archived|tier-down|merge] [--dry]
// 写进 track/mem-removal.jsonl（只追加，不改写）：
//   {no:"R-0001", at, seq, action, why, by, evid}
// 编号只增：R-0001, R-0002 …（删过的号不回收）
//
// import 不执行主逻辑（同族教训：能被 import 的模块必须有 main 保护）。

import { readFileSync, writeFileSync, appendFileSync, existsSync } from 'node:fs'
import { join } from 'node:path'
import { ROOT } from './root.mjs'

// 2026-11-11 用户：「和现在有重叠的，就合成一个吧」——
// 卸载不再自建表：挂账写 track/known-debt.json（老件），作废写 notebook/3-墓碑.md（老件）。
const DEBT = join(ROOT, 'track', 'known-debt.json')
const TOMB = (() => {
  // 2026-11-11: core code strings must stay ASCII - resolve the Chinese filename through the page table
  // (pages.json + locales/zh.json) instead of hardcoding it here.
  try {
    const pages = JSON.parse(readFileSync(join(ROOT, 'core', 'pages.json'), 'utf8')).ids || []
    const zh = JSON.parse(readFileSync(join(ROOT, 'core', 'locales', 'zh.json'), 'utf8'))
    const rel = pages.map((i) => zh['page.' + i]).find((v) => typeof v === 'string' && v.startsWith('3-'))
    return rel ? join(ROOT, rel) : null
  } catch { return null }
})()
const TOMB_TPL = (() => {
  try { return JSON.parse(readFileSync(join(ROOT, 'core', 'locales', 'zh.json'), 'utf8'))['tombstone.memory'] || '' } catch { return '' }
})()

function main (argv) {
  const seq = argv[0]
  const dry = argv.includes('--dry')
  const get = (k, d) => { const i = argv.indexOf(k); return i >= 0 && argv[i + 1] ? argv[i + 1] : d }
  const why = get('--why', '')
  const by = get('--by', 'user')
  const action = get('--action', 'archived')
  if (!seq || !/^\d+$/.test(String(seq))) { console.error('usage: node core/mem-retire.mjs <seq> --why "..." [--by user|rule:P35|auto:x] [--dry]'); return 2 }
  if (!why) { console.error('refused: --why is required (a tombstone must say why it died and what replaces it)'); return 2 }
  const now = new Date()
  const iso = now.toISOString()
  const stamp = iso.slice(0, 10)
  // ① 挂账：一条欠账 + 复查期（known-debt 是老件，字段照它现有的）
  let kd = []
  try { kd = JSON.parse(readFileSync(DEBT, 'utf8')) } catch { kd = [] }
  const reviewAfter = new Date(now.getTime() + 7 * 86400000).toISOString()
  const rec = { at: iso, organ: 'memory', kind: 'retired-memory', why_failed: why, review_after: reviewAfter, from: by, seq: String(seq), action }
  if (dry) { console.log(JSON.stringify({ dry: true, would_write: { known_debt: rec, tombstone: `mem:${seq}` } }, null, 2)); return 0 }
  kd.push(rec)
  writeFileSync(DEBT, JSON.stringify(kd, null, 1) + '\n', 'utf8')
  // ② 墓碑：三行一条（什么时候作废 / 为什么 / 现在按什么来），格式照 3-墓碑.md 现有条目
  const block = String(TOMB_TPL).replace('{seq}', String(seq)).replace('{stamp}', stamp).replace('{why}', String(why)).replace('{action}', String(action))
  if (TOMB && block) appendFileSync(TOMB, block, 'utf8')
  console.log(JSON.stringify({ ok: true, known_debt: rec, tombstone: `mem:${seq}` }))
  return 0
}

if (import.meta.url === `file://${process.argv[1]}` || process.argv[1]?.endsWith('mem-retire.mjs')) {
  process.exit(main(process.argv.slice(2)))
}
