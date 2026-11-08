// core/alt/status-alt.mjs -- 替代实现：不同语言、不同输出格式，只吐 SIG 行
// 目的：证明"换掉一个器官，框架不用改"
import { readFileSync, existsSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = 'F:\\Tools\\coo-day1'
const snapDir = join(ROOT, 'track', 'own')
let fans = 0
let posts = 0
try {
  const files = existsSync(snapDir) ? readFileSync(join(ROOT, 'track', '发布台账.jsonl'), 'utf8').trim().split('\n').filter(Boolean) : []
  posts = files.length
  const latest = readdirSafe(snapDir)
  if (latest) {
    const j = JSON.parse(readFileSync(join(snapDir, latest), 'utf8'))
    fans = Number(j.fans || j.follower || 0)
  }
} catch {}

function readdirSafe(dir) {
  try {
    const fs = require('node:fs')
    const all = fs.readdirSync(dir).filter((f) => f.endsWith('.json')).sort()
    return all.length ? all[all.length - 1] : ''
  } catch { return '' }
}

// 故意用英文、故意换格式：只要最后一行是 SIG，框架就认
console.log(`status-alt: ledger=${posts} fans=${fans} (alt implementation, node)`)
console.log('SIG ' + JSON.stringify({ state: 0, counts: [posts, fans] }))