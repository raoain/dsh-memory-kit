// core/pulse.mjs -- organ 9: the periodic sweep.
//
// 主路是器官自己上报（SIG）；这里是兜底：定期扫一遍，扫完自己也上报。
//
// 扫三件事：
//   ① 登记的器官文件还在不在          → 缺了 state 2（真的坏了）
//   ② 每个器官多久没上过总线          → 超节律 state 1（饿了，不是死了）
//   ③ 把这次扫描结果自己上总线        → 这样"扫过没扫过"也有记录
//
// 为什么不是心跳检查：器官是脚本，不调用就不存在，饿不死。
// 工程界的 lease/TTL/看门狗是给「一直该在跑的长驻进程」的；
// 按需器官该用的是「节律」——每个器官在 registry 里写自己的 every（分钟）。
//
// usage:
//   node core/pulse.mjs          扫一次并上报
//   node core/pulse.mjs --dry    只打印，不上报

import { readFileSync, existsSync, readdirSync } from 'node:fs'
import { join } from 'node:path'
import { emit } from './bus.mjs'

// root comes from core/root.mjs -- do not hardcode the path here
import { ROOT } from './root.mjs'
const BUS = join(ROOT, 'track', 'bus.jsonl')
const SELF = '9'
const SPEC = JSON.parse(readFileSync(join(ROOT, 'core', 'spec.json'), 'utf8'))
const GRACE = 2 // 超过 every 的 2 倍才算饿

const reg = JSON.parse(readFileSync(join(ROOT, 'core', 'registry.json'), 'utf8'))
const cells = reg.cells || {}

const dry = process.argv.includes('--dry')
const now = Date.now()

// 最近一次信号 —— 读 live + 归档（轮转把历史切走了，不读归档会把「昨天跑过」误判成「从没跑过」）
const lastAt = {}
function scan(text) {
  for (const line of text.split('\n')) {
    if (!line.trim()) continue
    let s
    try { s = JSON.parse(line) } catch { continue }
    if (s.ts) lastAt[s.src] = Math.max(lastAt[s.src] || 0, Number(s.ts))
  }
}
if (existsSync(BUS)) scan(readFileSync(BUS, 'utf8'))
const ARCH = join(ROOT, 'track', 'archive')
if (existsSync(ARCH)) {
  const files = readdirSync(ARCH).filter((f) => /^bus-\d{8}\.jsonl$/.test(f)).sort().slice(-3)
  for (const f of files) scan(readFileSync(join(ARCH, f), 'utf8'))
}

const missing = []
const hungry = []
const never = []

for (const [num, cell] of Object.entries(cells)) {
  if (num === SELF) continue

  // 预留位（2026-11-08）：path null / enabled false 的模块中枢只是位置与接口，还没建，跳过
  if (!cell.path || cell.enabled === false) continue

  // ① 文件在不在
  const p = join(ROOT, cell.path)
  if (!existsSync(p)) { missing.push(`${num}:${cell.id}`); continue }

  // ② 节律：every = 0 表示按需，不检查
  const every = Number(cell.every || 0)
  if (every <= 0) continue

  const last = lastAt[num]
  if (!last) { never.push(`${num}:${cell.id}`); continue }
  const ageMin = (now - last) / 60000
  if (ageMin > every * GRACE) { hungry.push(`${num}:${cell.id}(${Math.round(ageMin)}m/${every}m)`) }
}

// ③ 汇总成一条自己的信号
let state = 0
let why = 'all-fresh'
if (missing.length) { state = 2; why = 'missing' }
else if (never.length) { state = 3; why = 'never-reported' }
else if (hungry.length) { state = 1; why = 'hungry' }

const rush = Number((SPEC.map?.state_to_rush || { 0: 0, 1: 1, 2: 2, 3: 1 })[String(state)] ?? 1)
const evid = `pulse:${why}:m${missing.length}/n${never.length}/h${hungry.length}`
const value = missing.length + never.length + hungry.length

if (dry) {
  console.log(JSON.stringify({ dry: true, state, why, missing, never, hungry }))
} else {
  console.log(JSON.stringify(emit(SELF, 1, state, value, evid, { rush, counts: [Object.keys(cells).length, missing.length, never.length, hungry.length] })))
}
