// brain.mjs -- organ 20: the layer above the center. It receives the center's verdict and
// decides what deserves attention, then says so as data. It never acts.
//
// Why this exists (2026-11-09 用户：「可以接着写大脑了」): the center uploads changes and
// problems (center.verdict), but nothing consumed them -- they landed on the bus and stayed
// there. The brain is the consumer: it reads the verdict, ranks the issues, and separates
//   - what a mechanical rule can handle now (fixed kind, known remedy)
//   - what needs understanding (no rule knows how; must not be faked by a script)
// from:
//   - what is dangerous but still mechanical (a whole region silent)
//
// It does not repair, kill, restart, or rewrite anything. Its output is a ranked plan.
//
// usage:
//   node core/brain.mjs          read the newest verdict, rank, write the plan
//   node core/brain.mjs --dry    print the plan, write nothing

import { readFileSync, writeFileSync, appendFileSync, existsSync } from 'node:fs'
import { join } from 'node:path'
import { ROOT } from './root.mjs'
import { emit } from './bus.mjs'
import { requestSpawn } from './arbiter.mjs'

const SELF = 20
const BUS = join(ROOT, 'track', 'bus.jsonl')
const PLAN = join(ROOT, 'track', 'brain.jsonl')
const dry = process.argv.includes('--dry')

function newestVerdict() {
  if (!existsSync(BUS)) return null
  let best = null
  for (const line of readFileSync(BUS, 'utf8').split('\n')) {
    if (!line.trim() || !line.includes('center.verdict')) continue
    let r
    try { r = JSON.parse(line) } catch { continue }
    if (r.topic !== 'center.verdict') continue
    const ts = Number(r.ts) || Date.parse(r.at) || 0
    if (!best || ts > best.ts) best = { ...r, ts }
  }
  return best
}

// 2026-11-09 查先人后的调整：ComplyEdge 把 EU AI Act 的判定写成 OPA/Rego 策略、刻意不放进引擎——
// 「改规则不该等于改代码」。所以这张决策表搬进 spec.brain，brain.mjs 只负责执行。
const SPEC = JSON.parse(readFileSync(join(ROOT, 'core', 'spec.json'), 'utf8'))
const MECHANICAL = (SPEC.brain && SPEC.brain.mechanical) || {}
const UNDERSTANDING = (SPEC.brain && SPEC.brain.needs_understanding) || []

const verdict = newestVerdict()
const plan = { at: new Date().toISOString(), verdict_at: verdict ? verdict.at : null, heart: verdict ? verdict.heart : null, items: [] }
const REG = JSON.parse(readFileSync(join(ROOT, 'core', 'registry.json'), 'utf8'))
const CELLS = REG.cells || {}

// 2026-11-09 用户：「现在写大脑是一个真正的初步判决的东西」。
// 所以大脑不只看中枢给的 issues，它拿 verdict.rows（一手测量）自己判一次：
// 阈值仍从 spec.expect.drift 读，节律从 registry 读——判据只有一份来源，不在这里写死。
if (verdict && Array.isArray(verdict.rows)) {
  // "最后一次见到"同样以 center.lastSeen 为准（单调、放电不影响）；rows 里的 last 会偏旧。
  let lastSeenMap = {}
  let selfReport = {} // 器官自己报的 pace（异常时才有），判定只认它 + 中枢的 silent
  try {
    const c = JSON.parse(readFileSync(join(ROOT, 'track', 'center.json'), 'utf8'))
    lastSeenMap = c.lastSeen || {}
    selfReport = c.pace || {}
  } catch { lastSeenMap = {} }
  const TH = (SPEC.expect && SPEC.expect.drift) || { state1_bp: 1000, state2_bp: 5000 }
  const byOrgan = {}
  for (const [n, c] of Object.entries(REG)) byOrgan[n] = c.id
  for (const row of verdict.rows) {
    if (String(row.what) === 'heartbeat') continue
    const id = byOrgan[String(row.organ)] || String(row.what || '').replace(/^organ_\d+_/, '')
    const every = Number((CELLS[String(row.organ)] || {}).every || 0)
    const limitMs = (every > 0 ? every * 2 : 60) * 60000
    const lastSeen = Math.max(Number(row.last || 0), Number(lastSeenMap[String(row.organ)] || 0))
    // 按需器官（every=0）不判没反应：它们本来就不按节拍来
    const silent = row.organ > 0 && every > 0 && (!lastSeen || Date.now() - lastSeen > limitMs)
    const bp = Number(row.bp || 0)
    // 2026-11-10 用户：「没来就上报大脑，让他处理」。所以 silent（长时间没报到）一律进上传，
    // 不自动派活——它为什么没来，中枢不知道，也不该猜。
    let kind = null
    if (silent) kind = 'silent'
    else if ((selfReport[String(row.organ)] || {}).state >= 1) kind = Number(selfReport[String(row.organ)].state) >= 2 ? 'broken' : 'late' // 只认它自己报的 pace
    if (!kind) continue // 自己判出来没事的，不进计划
    const tier = kind === 'silent' ? 2 : Number(selfReport[String(row.organ)].state) >= 2 ? 2 : 1
    let bucket = 'observed'
    let remedy = null
    if (kind === 'silent') bucket = 'needs-understanding' // 没来 = 上报，不代它决定
    else if (MECHANICAL[id] && kind === 'broken') { bucket = 'mechanical'; remedy = MECHANICAL[id] }
    else if (UNDERSTANDING.includes(id)) bucket = 'needs-understanding'
    plan.items.push({ organ: row.organ, id, kind, tier, bp, bucket, remedy, judged_by: 'brain' })
  }
}

if (plan.items.length === 0 && verdict) {
  // 自己判不出来东西时，至少不要假装：记下“这轮没判出问题”
  plan.note = 'no issue found from the raw rows'
}

if (verdict) {
  plan.items.sort((a, b) => b.tier - a.tier || b.bp - a.bp)
  plan.counts = plan.items.reduce((acc, x) => { acc[x.bucket] = (acc[x.bucket] || 0) + 1; return acc }, {})
  plan.state = plan.items.length === 0 ? 0 : (plan.items.some((x) => x.tier >= 2) ? 2 : 1)
  plan.evid = `brain:${plan.items.length}items/${Object.entries(plan.counts || {}).map(([k, v]) => k + v).join(',')}`
}

// 2026-11-09 用户：「初判层他完成的就是脑干的判决和下发，然后不理解的上传就行」。
// 下发统一走 `arbiter`（基底节式的闸）：同一器官的冷却和"同一时刻只放一个"都在那里，
// 这里不再自己记冷却、也不再自己 spawn——否则和 reflex 各叫各的。
if (!dry) {
  // 2026-11-09 用户：「两处命令合并成一条；先发的那条做过了，就只做后面那条里没有的」。
  // 所以这里把 mechanical 桶按器官去重后逐个下发，重叠的部分由 arbiter 的 per-cell 冷却挡掉。
  const seen = new Set()
  for (const it of plan.items) {
    if (it.bucket !== 'mechanical' || !it.remedy) continue
    const cell = CELLS[String(it.organ)]
    if (!cell || !cell.path) continue
    if (seen.has(cell.id)) { it.merged = true; continue }
    seen.add(cell.id)
    const v = requestSpawn({ from: SELF, id: cell.id, path: cell.path, reason: it.remedy, rush: 2, tier: it.tier || 0 })
    if (v.ok) it.dispatched = it.remedy
    else it.held = v.why
  }
}

if (dry) {
  console.log(JSON.stringify(plan, null, 2))
} else {
  appendFileSync(PLAN, JSON.stringify(plan) + '\n', 'utf8')
  if (plan.state !== undefined) emit(SELF, 4, plan.state, plan.items.length, plan.evid, { rush: plan.state, topic: 'brain.plan', items: plan.items })
  console.log(JSON.stringify({ items: plan.items.length, counts: plan.counts || {}, state: plan.state, dispatched: plan.items.filter((x) => x.dispatched).length }))
}
