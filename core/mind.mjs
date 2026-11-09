// mind.mjs -- organ 21: the first prototype of the thinking layers above the brainstem.
//
// Where it sits: the brainstem (15 measure, 18 aggregate, 20 preliminary judge) uploads
// `brain.plan`. This organ is the receiver: it turns that plan into a stated conclusion,
// then a proposed move, then a check of its own conclusion. It writes to its own memory
// location (track/mind/) so the next round can read what it thought last time.
//
// Three layers, deliberately separated (2026-11-09 用户: at least three, plus cerebellum when
// a body exists):
//   L1 conclude  -- one line per item: what happened, with the number it rests on
//   L2 decide    -- a known remedy, or an explicit "cannot decide" (never invented)
//   L3 recheck   -- audit L1/L2 against what is actually on disk; demote what cannot be backed
//
// It is a SKELETON: L1/L2 are template + data, not understanding. L3 is the only part with
// teeth, and it only checks that evidence exists. Nothing here acts; the brainstem dispatches.
//
// usage:
//   node core/mind.mjs          think once
//   node core/mind.mjs --dry    print the thought, write nothing

import { readFileSync, writeFileSync, appendFileSync, existsSync, mkdirSync, readdirSync } from 'node:fs'
import { join } from 'node:path'
import { ROOT } from './root.mjs'
import { emit } from './bus.mjs'

const SELF = '21'
const BUS = join(ROOT, 'track', 'bus.jsonl')
const MIND = join(ROOT, 'track', 'mind')
const STATE = join(MIND, 'state.json')
const dry = process.argv.includes('--dry')

if (!existsSync(MIND)) mkdirSync(MIND, { recursive: true })
const day = new Date().toISOString().slice(0, 10)
const LOG = join(MIND, `${day}.jsonl`)

function newestPlan() {
  if (!existsSync(join(ROOT, 'track', 'brain.jsonl'))) return null
  const lines = readFileSync(join(ROOT, 'track', 'brain.jsonl'), 'utf8').trim().split('\n').filter(Boolean)
  if (!lines.length) return null
  try { return JSON.parse(lines[lines.length - 1]) } catch { return null }
}

function previousState() {
  try { return existsSync(STATE) ? JSON.parse(readFileSync(STATE, 'utf8')) : { rounds: 0, lastThought: null } } catch { return { rounds: 0, lastThought: null } }
}

// 2026-11-09 用户：「判断→动作→痕迹→读回→再判断，就是个精细化」「痕迹再反到记忆里面，这就是诞生出习惯」。
// 所以这里做"读回"与"习惯"：读上几轮的结论，同类问题连续判成一样就记成习惯，下一轮直接复用。
const HABITS = join(MIND, 'habits.json')
const HABIT_AFTER = 3 // 连续 3 轮判成一样 → 习惯

function loadHabits() {
  try { return existsSync(HABITS) ? JSON.parse(readFileSync(HABITS, 'utf8')) : {} } catch { return {} }
}

// 取最近几轮的历史结论（当天 + 前一天），只看 L1 的 kind
function recentKinds(max = HABIT_AFTER) {
  const out = []
  const days = existsSync(MIND)
    ? readdirSync(MIND).filter((f) => /^\d{4}-\d{2}-\d{2}\.jsonl$/.test(f)).sort().slice(-2)
    : []
  for (const f of days) {
    let lines = []
    try { lines = readFileSync(join(MIND, f), 'utf8').trim().split('\n').filter(Boolean) } catch { continue }
    for (const line of lines) {
      try {
        const t = JSON.parse(line)
        if (t && Array.isArray(t.L1)) out.push(t)
      } catch { /* skip broken line */ }
    }
  }
  // 2026-11-09 用户：「需要一个缓冲，也就等待记忆回写之后再重新判」。
  // 所以最近一轮**不进读回**：它刚写完，还没沉淀；下一轮再看它。既有缓冲，也避免
  // 同一轮写完立刻读自己、把噪声当规律。
  if (out.length > 1) out.pop()
  return out.slice(-max)
}

const history = recentKinds()
const habits = loadHabits()

// 2026-11-09 用户：「终于到我们以前讨论的数核了……反正就是套环，然后有复写痕迹回写记忆」。
// 数核不是又一个器官，是**每轮把状态压成一个数向量，下一轮带着它读回来**：
//   cur = 本轮的量；delta = cur - prev；写回 nucleus.json，下一轮读回当 prev。
// 这样环是套着的：上一轮的数 → 这一轮的判断 → 这一轮的数 → 下一轮。
const NUCLEUS = join(MIND, 'nucleus.json')
function loadNucleus() {
  try { return existsSync(NUCLEUS) ? JSON.parse(readFileSync(NUCLEUS, 'utf8')) : null } catch { return null }
}
const prevNucleus = loadNucleus()

const plan = newestPlan()
const prev = previousState()
const thought = {
  at: new Date().toISOString(),
  round: Number(prev.rounds || 0) + 1,
  source: plan ? plan.at : null,
  L1: [],
  L2: [],
  L3: { checked: 0, demoted: [] },
  buffer: { last_trace_excluded: true, read_back: 0 },
}

thought.buffer.read_back = history.length
if (plan) {
  for (const it of plan.items || []) {
    // 2026-11-09 修正（生物学同一条规矩）：**习惯只对良性的重复成立，有害的重复反而要升**。
    // 连续 3 轮同样的"坏了"不能记成习惯——那等于把故障学成常态（教训：基线只学 state 0/3）。
    // 所以分两种：
    //   habit   = 良性重复（kind 正常）→ 可以跳过重判
    //   chronic = 故障重复（broken/silent/late）→ 标成慢性，但不降级、不跳过
    // 结论句已改 ASCII 码（`kind=broken`），这里必须跟着改，否则 streak 永远 0、习惯永远长不出来
    const sameKind = history.filter((t) => (t.L1 || []).some((x) => x.id === it.id && String(x.says || '').includes(`kind=${it.kind}`))).length
    const isBenign = !['broken', 'silent', 'late'].includes(String(it.kind))
    const isHabit = sameKind >= HABIT_AFTER && isBenign
    const isChronic = sameKind >= HABIT_AFTER && !isBenign
    const evid = `bp=${it.bp} tier=${it.tier} kind=${it.kind}`
    if (isHabit) {
      thought.L1.push({ id: it.id, says: `${it.id} kind=${it.kind} habit=true streak=${sameKind}`, evid, habit: true, reused_from: sameKind })
      habits[it.id] = { kind: it.kind, streak: sameKind, since: (habits[it.id] && habits[it.id].since) || thought.at }
    } else if (isChronic) {
      thought.L1.push({ id: it.id, says: `${it.id} kind=${it.kind} chronic=true streak=${sameKind}`, evid, chronic: true, streak: sameKind })
      habits[it.id] = { kind: it.kind, streak: sameKind, since: (habits[it.id] && habits[it.id].since) || thought.at, chronic: true }
      thought.chronic = (thought.chronic || 0) + 1
    } else {
      thought.L1.push({ id: it.id, says: `${it.id} kind=${it.kind} ${evid}`, evid })
    }

    // L2：习惯的情况跳到"用过什么"，其他照旧
    if (it.remedy) thought.L2.push({ id: it.id, move: it.remedy, how: isHabit ? 'dispatch-habitual' : 'dispatch' })
    else thought.L2.push({ id: it.id, move: null, how: 'cannot-decide', why: 'no remedy in spec.brain.mechanical' })
  }

  // L3：复查——每条结论的 evid 必须能在 plan 里对上；对不上的降级，不保留"看起来对"的话
  for (let i = 0; i < thought.L1.length; i++) {
    const item = thought.L1[i]
    const src = (plan.items || []).find((x) => x.id === item.id)
    thought.L3.checked++
    if (!src || !String(item.evid).includes(`bp=${src.bp}`)) {
      thought.L3.demoted.push({ id: item.id, why: 'evidence does not match the plan it came from' })
      item.demoted = true
    }
  }
}

// 2026-11-09 用户：「先排除小脑，我们需要先他自己大脑空想也能转，以后再加小脑的其他变量进去就行」。
// 空想模式（idle）：没有新上报、没有新 plan 时，环也不能停——拿自己的痕迹和自己比，产出"这一轮我注意到什么"。
// 注意：空想只在**已有骨架**上盘自己的状态，不编新事实；每条也要带依据（哪个文件、哪一轮）。
const forceIdle = process.argv.includes('--force-idle')
if (forceIdle || thought.L1.length === 0) {
  thought.mode = 'idle'
  const prior = prevNucleus && prevNucleus.cur ? prevNucleus.cur : null
  const chronicIds = Object.entries(habits).filter(([, v]) => v.chronic).map(([k]) => k)

  thought.L1.push({ id: 'self', says: `idle round=${thought.round} prev=${prior ? prior.round : 'none'} no new report`, evid: `nucleus:${prior ? prior.round : 'none'}` })
  if (chronicIds.length) {
    thought.L1.push({ id: 'chronic', says: `chronic list n=${chronicIds.length} ids=${chronicIds.join('/')}`, evid: `habits:${chronicIds.length}` })
    thought.L2.push({ id: 'chronic', move: null, how: 'cannot-decide', why: 'chronic: no mechanical remedy' })
  } else {
    thought.L1.push({ id: 'chronic', says: 'chronic list empty', evid: 'habits:0' })
  }
  if (prior) {
    const stalled = ['items', 'backed', 'movable'].every((k) => Number(prior[k] || 0) === Number((prior[k] || 0)))
    thought.L1.push({ id: 'delta', says: stalled ? `delta none prev=${prior.round} now=${thought.round}` : `delta changed prev=${prior.round} now=${thought.round}`, evid: `nucleus:${prior.round}` })
  }
  // 空想也要过 L3：这里每条依据都指 nucleus / habits / memory，不走 plan 对齐
  thought.L3.checked = thought.L1.length

  // 2026-11-09 用户：「他没跑记忆吗？就是你读的那个」——空想不能只盘自己的数，要去读记忆库。
  // 拿慢性名单里的器官名去 memories.jsonl 里找同名的旧结论/旧教训，最多 3 条，作为"我想起的事"。
  try {
    const memFile = join(ROOT, 'memories.jsonl')
    if (existsSync(memFile) && chronicIds.length) {
      const keys = chronicIds.map((x) => String(x).toLowerCase())
      const hits = []
      for (const line of readFileSync(memFile, 'utf8').split('\n')) {
        if (!line.trim()) continue
        let m; try { m = JSON.parse(line) } catch { continue }
        // spec.records 记的是真实形状：keywords 是「装着 JSON 数组的字符串」——先解析再用，不猜类型
        const kwRaw = m.keywords
        let kwList = []
        if (Array.isArray(kwRaw)) kwList = kwRaw
        else if (typeof kwRaw === 'string') { try { const p = JSON.parse(kwRaw); if (Array.isArray(p)) kwList = p } catch { kwList = [kwRaw] } }
        const hay = `${m.content || ''} ${kwList.join(' ')}`.toLowerCase()
        if (!keys.some((k) => hay.includes(k))) continue
        hits.push({ id: m.id, content: String(m.content || '').slice(0, 60) })
      }
      const picked = hits.slice(-3)
      for (const h of picked) {
        thought.L1.push({ id: `mem:${h.id}`, says: `recall ${h.id} ${String(h.content).replace(/[^\x20-\x7E]/g, '').slice(0, 40)}`, evid: `memory:${h.id}` })
      }
      if (picked.length) thought.L2.push({ id: 'memory', move: null, how: 'recalled', why: `recall hits=${hits.length}` })
      thought.L3.checked = thought.L1.length
    }
  } catch { /* memory unreadable: idle keeps running on its own traces */ }

  for (const item of thought.L1) {
    if (!item.evid) {
      thought.L3.demoted.push({ id: item.id, why: 'idle thought without evidence' })
      item.demoted = true
    }
  }
}

const backed = thought.L1.filter((x) => !x.demoted).length
const canMove = thought.L2.filter((x) => x.move).length
thought.summary = `L1 ${thought.L1.length} (backed ${backed}) / L2 ${canMove} movable / L3 checked ${thought.L3.checked} demoted ${thought.L3.demoted.length}`

// 数核：把这一轮压成向量，和上一轮比（delta），然后写回，交给下一轮。
const vital = (() => { try { return JSON.parse(readFileSync(join(ROOT, 'track', 'center.json'), 'utf8')).vital || {} } catch { return {} } })()
const cur = {
  at: thought.at,
  round: thought.round,
  items: thought.L1.length,
  backed,
  movable: canMove,
  demoted: thought.L3.demoted.length,
  chronic: thought.chronic || 0,
  habits: Object.keys(habits).length,
  integration: Number(vital.integration || 0),
  differentiation: Number(vital.differentiation || 0),
}
const prior = prevNucleus && prevNucleus.cur ? prevNucleus.cur : null
const delta = prior ? Object.fromEntries(Object.keys(cur).filter((k) => typeof cur[k] === 'number').map((k) => [k, Number((cur[k] - (prior[k] || 0)).toFixed(3))])) : null
const nucleus = { at: cur.at, prev_at: prior ? prior.at : null, cur, delta }
thought.nucleus = nucleus

if (dry) {
  console.log(JSON.stringify(thought, null, 2))
} else {
  appendFileSync(LOG, JSON.stringify(thought) + '\n', 'utf8')
  writeFileSync(NUCLEUS + '.tmp', JSON.stringify(nucleus, null, 2), 'utf8')
  writeFileSync(NUCLEUS, JSON.stringify(nucleus, null, 2), 'utf8')
  writeFileSync(STATE + '.tmp', JSON.stringify({ rounds: thought.round, lastThought: thought.at, summary: thought.summary }, null, 2), 'utf8')
  writeFileSync(STATE, JSON.stringify({ rounds: thought.round, lastThought: thought.at, summary: thought.summary }, null, 2), 'utf8')
  if (plan) emit(SELF, 4, thought.L3.demoted.length ? 1 : 0, thought.L1.length, `mind:${backed}/${thought.L1.length}`, { rush: 0, topic: 'mind.thought', summary: thought.summary })
  writeFileSync(HABITS, JSON.stringify(habits, null, 2), 'utf8')
  console.log(JSON.stringify({ round: thought.round, summary: thought.summary, habits: Object.keys(habits).length, delta }))
}
