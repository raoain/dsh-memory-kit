// core/bus.mjs -- bus: every cell speaks one signal format
//
// signal = { at, src, kind, state, value, evid }   (see core/spec.json)
//   at    UTC ISO8601 with Z
//   src   cell id from registry.json
//   kind  1 judge / 2 probe / 3 act / 4 record
//   state 0 pass / 1 warn / 2 fail / 3 unknown
//   value dead value: number or {k:v}, never a sentence
//   evid  evidence code, ASCII only (e.g. verify:47/46/0/0)
//
// usage:
//   node core/bus.mjs emit <src> <kind> <state> <value> [evid]
//   node core/bus.mjs tail [n]

import { appendFileSync, readFileSync, existsSync, mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'

// root comes from core/root.mjs -- do not hardcode the path here
import { ROOT } from './root.mjs'
export const BUS = join(ROOT, 'track', 'bus.jsonl')

// 2026-11-11 用户：「这玩意不是有个自我集吗？都是环环相扣的呀」——
// 所以档位**不靠我手写一张映射表**，而是从已有的 registry 推出来（环环相扣）：
//   感知类（module=sense）→ fast（等身体才有输入）
//   供能类（module=power）或心跳（src 7, reflex）→ steady
//   每日（every >= 1440）→ slow
//   其余有节律的（every > 0）→ slow（它们按节律报到，本身就是事件）
//   按需（every = 0，检查/工具类）→ slow
// spec.channels.map 只当**覆盖表**（个别要手调时才写），不算主映射。
function specOnce () {
  try { return JSON.parse(readFileSync(join(ROOT, 'core', 'spec.json'), 'utf8')) } catch { return {} }
}
const SPEC = specOnce()
function regOnce () {
  try { return JSON.parse(readFileSync(join(ROOT, 'core', 'registry.json'), 'utf8')).cells || {} } catch { return {} }
}
const REG = regOnce()
function deriveChannel (src) {
  const c = REG[String(src)] || {}
  const mod = String(c.module || '')
  if (mod === 'sense') return 'fast'
  if (mod === 'power') return 'steady'
  if (String(src) === '7') return 'steady' // reflex = 心跳，恒定供给那一档
  return 'slow'
}
function channelOf (src) {
  const C = (SPEC.channels || {})
  const map = C.map || {}
  const override = map[String(src)]
  if (override === 'fast' || override === 'steady' || override === 'slow') return override
  return deriveChannel(src) || (C.default || 'slow')
}

export function emit(src, kind, state, value, evid = '', extra = {}) {
  // 2026-11-11 用户：「你自己没按标准写，他能接到就有鬼了」——
  // 我今天按对象调 emit({src:18,...})，函数收下对象、字段全 undefined，**信号静默没进总线**。
  // 所以这里加一道形状检查：签名写错了当场炸，不许静默丢信号。
  // 2026-11-11 第二课：这道检查第一版太严，**把 reflex 的字符串 src 也拒了**，
  // 结果心跳停了 15 分钟（22:43:44 → 22:58）。合法调用必须放行：
  //   - 对象 = 写法错 → 炸；
  //   - 数字字符串（'7'） = 合法，转成数字；
  //   - 其它非数字 → 炸。
  const asNum = (v, name) => {
    if (typeof v === 'number' && Number.isFinite(v)) return v
    if (typeof v === 'string' && v.trim() !== '' && Number.isFinite(Number(v))) return Number(v)
    throw new TypeError(`emit: ${name} must be a number (or a numeric string), got ${typeof v}`)
  }
  if (typeof src === 'object' && src !== null) {
    throw new TypeError('emit(src, kind, state, value, evid, extra): first argument must be a number, got an object (did you mean positional args?)')
  }
  src = asNum(src, 'src')
  kind = asNum(kind, 'kind')
  state = asNum(state, 'state')
  // rush: 0 cosmetic / 1 decays / 2 irreversible (default 0)
  if (typeof value === 'string' && value.trim() !== '' && Number.isFinite(Number(value))) value = Number(value)
  const now = new Date()
  const rec = {
    ts: now.getTime(),
    at: now.toISOString(),
    src: String(src),
    kind: Number(kind),
    state: Number(state),
    value,
    evid: String(evid),
    channel: extra.channel || channelOf(src),
  rush: Number(extra.rush ?? 0),  // always present: record-shape checks it (2026-11-11)
    ...extra,
  }
  const dir = dirname(BUS)
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true })
  appendFileSync(BUS, JSON.stringify(rec) + '\n', 'utf8')
  return rec
}

export function tail(n = 10) {
  if (!existsSync(BUS)) return []
  const lines = readFileSync(BUS, 'utf8').split('\n').filter(Boolean)
  return lines.slice(-n).map((l) => {
    try { return JSON.parse(l) } catch { return { bad: l } }
  })
}

if (process.argv[1] && process.argv[1].endsWith('bus.mjs')) {
  const [cmd, ...rest] = process.argv.slice(2)
  if (cmd === 'emit') {
    const rushIdx = rest.indexOf('--rush')
    const rush = rushIdx >= 0 ? Number(rest[rushIdx + 1]) : 0
    const args = rushIdx >= 0 ? rest.filter((_, i) => i !== rushIdx && i !== rushIdx + 1) : rest
    const [src, kind, state, value, evid] = args
    if (!src || !kind || state === undefined || value === undefined) {
      console.error('usage: node core/bus.mjs emit <src> <kind> <state> <value> [evid]')
      process.exit(2)
    }
    console.log(JSON.stringify(emit(src, kind, state, value, evid, { rush })))
  } else if (cmd === 'tail') {
    for (const r of tail(Number(rest[0]) || 10)) console.log(JSON.stringify(r))
  } else {
    console.error('usage: node core/bus.mjs emit|tail ...')
    process.exit(2)
  }
}