// consolidate.mjs -- organ 18: the primary center for the signal stream (judge + compress + discharge).
//
// Why: the bus is a stream of impulses, not an archive. A biological signal is either handled
// where it lands or reported upward, and then it is discharged -- it does not stay on the table
// as a record. Keeping every spike and pruning by hand later is the janitor's way.
//
// What this center does, per run:
//   1. JUDGE   read the new spikes, keep the shape: beats, by src, by state, max gap, transitions
//   2. COMPRESS warn/fail/record lines (and state changes of non-heartbeat organs) go to
//              track/events.jsonl -- that is what happened; steady heartbeat does not
//   3. DISCHARGE lines older than WINDOW_MIN are dropped from the live bus (they are already
//              folded into the shape above). The bus stops growing with time.
//
// Deliberate limits: it does not decide that anything died (state 1/2 lines are reported, not
// acted on) and it never touches archived raw files (track/archive is history, not stream).
//
// usage:
//   node core/consolidate.mjs           judge + compress + discharge
//   node core/consolidate.mjs --dry     report what would happen, write nothing

import { readFileSync, writeFileSync, appendFileSync, existsSync, copyFileSync, readdirSync, statSync, renameSync, mkdirSync, openSync, writeSync, closeSync, unlinkSync } from 'node:fs'
import { join } from 'node:path'
import { ROOT } from './root.mjs'
import { emit } from './bus.mjs'

const SELF = '18'
// 2026-11-09 用户：「直接覆盖：它先截断再写，你怎么这么喜欢热插拔？不能先停了再重写再启动嘛？」
// 更根本的是"同一时刻只能有一个写者"：中枢这种会重写状态文件的器官，第二次启动应当直接退出，
// 而不是两个人一起热替换。锁用排他创建（wx），和 loop.mjs 同一套做法；不杀进程，只是不让第二个进来。
const LOCK = join(ROOT, 'track', '.locks', 'consolidate.lock')
let lockHeld = false
try {
  mkdirSync(join(ROOT, 'track', '.locks'), { recursive: true })
  const fd = openSync(LOCK, 'wx')
  writeSync(fd, String(process.pid))
  closeSync(fd)
  lockHeld = true
} catch {
  const holder = existsSync(LOCK) ? Number(readFileSync(LOCK, 'utf8').trim()) : 0
  let alive = false
  try { if (holder) { process.kill(holder, 0); alive = true } } catch { alive = false }
  if (alive) {
    console.log(JSON.stringify({ skipped: 'another consolidate holds the lock', pid: holder }))
    process.exit(0)
  }
  // 死锁（上一个进程已不在）：接管
  writeFileSync(LOCK, String(process.pid), 'utf8')
  lockHeld = true
}
process.on('exit', () => {
  try { if (lockHeld && existsSync(LOCK) && Number(readFileSync(LOCK, 'utf8').trim()) === process.pid) unlinkSync(LOCK) } catch { /* ignore */ }
})
const BUS = join(ROOT, 'track', 'bus.jsonl')
const EVENTS = join(ROOT, 'track', 'events.jsonl')
const CENTER = join(ROOT, 'track', 'center.json')
const CURSOR = join(ROOT, 'track', '.consolidate-cursor.json')
// 环的五步各自的留痕文件（2026-11-09 用户：「依旧加个识别就行」——只识别缺哪步，不判死）
const STEP_FILES = {
  judge: join(ROOT, 'track', 'brain.jsonl'),
  act: join(ROOT, 'track', 'dispatch.jsonl'),
  readback: join(ROOT, 'track', 'drift-raw.json'),
}
// 2026-11-10：放电窗口也以心跳为钟——900 拍 = 45 分钟（3 秒一跳）。
// 注意这个文件里 spec 的变量叫 SPEC_E（在下面才定义），所以这里直接读一次文件，别引用未定义的 SPEC。
const TIME_BASE =
  (JSON.parse(readFileSync(join(ROOT, 'core', 'spec.json'), 'utf8')).expect || {}).time_base ||
  { interval_ms: 3000, beats: {} }
const BEAT_MS = Number(TIME_BASE.interval_ms || 3000)
const WINDOW_MIN = (Number((TIME_BASE.beats || {}).discharge || 900) * BEAT_MS) / 60000
const STRESS = join(ROOT, 'track', '.stress.json')
const dry = process.argv.includes('--dry')

// 2026-11-09 事故：center.json 被并发写截成 0 字节，下一次启动 JSON.parse 直接抛错，
// 中枢整个停摆。读要能扛住空文件，写要原子（tmp + rename）——截断只可能发生在替换前。
function readJsonSafe(p, dflt) {
  try {
    if (!existsSync(p)) return dflt
    const t = readFileSync(p, 'utf8')
    if (!t.trim()) return dflt
    return JSON.parse(t)
  } catch { return dflt }
}
function writeJsonAtomic(p, obj) {
  const tmp = p + '.tmp'
  writeFileSync(tmp, JSON.stringify(obj, null, 2), 'utf8')
  renameSync(tmp, p)
}
const cursor = readJsonSafe(CURSOR, { lastTs: 0, state: {} })
const center = readJsonSafe(CENTER, { beats: 0, bySrc: {}, byState: {}, transitions: 0, maxGapMs: 0, gapAt: null, lastAt: null, events: 0, discharged: 0 })

const busSizeBefore = existsSync(BUS) ? statSync(BUS).size : 0
const raw = existsSync(BUS) ? readFileSync(BUS, 'utf8').split('\n').filter((l) => l.trim()) : []
const rows = []
for (const line of raw) {
  let r
  try { r = JSON.parse(line) } catch { continue }
  const ts = Number(r.ts) || Date.parse(r.at) || 0
  rows.push({ ...r, ts, raw: line })
}
rows.sort((a, b) => a.ts - b.ts)

const state = { ...(cursor.state || {}) }
const events = []
let maxTs = Number(cursor.lastTs || 0)
let beats = 0
let transitions = 0
let lastBeat = 0

for (const r of rows) {
  const src = String(r.src)
  const st = Number(r.state)
  const kind = Number(r.kind)
  const isNew = r.ts > Number(cursor.lastTs || 0)

  if (isNew) {
    beats++
    center.bySrc[src] = (center.bySrc[src] || 0) + 1
    center.byState[st] = (center.byState[st] || 0) + 1
    // 常态基线：每个 src 自己最常出现的 state。常态是稳定的，所以只有偏离它才算"不一样"。
    if (!center.bySrcState) center.bySrcState = {}
    if (!center.bySrcState[src]) center.bySrcState[src] = {}
    center.bySrcState[src][st] = (center.bySrcState[src][st] || 0) + 1
    const counts = center.bySrcState[src]
    // 基线只从"正常态"（state 0 / 3）里取：否则一直坏着的器官会把故障学成常态，
    // 等于把病登记成健康。warn/fail 永远记，永远不参与基线。
    const normal = (counts[0] || 0) + (counts[3] || 0)
    let baseline = null
    if (normal >= 20) baseline = (counts[0] || 0) >= (counts[3] || 0) ? 0 : 3
    const abnormal = st === 1 || st === 2
    const deviated = !abnormal && baseline !== null && st !== baseline && st !== 0 && st !== 3

    if (src === '7') {
      if (lastBeat && r.ts - lastBeat > center.maxGapMs) {
        center.maxGapMs = r.ts - lastBeat
        center.gapAt = new Date(r.ts).toISOString()
      }
      lastBeat = r.ts
    } else {
      if (state[src] !== undefined && state[src] !== st) {
        transitions++
        events.push({ at: r.at, src, kind, state: st, value: r.value, evid: r.evid, why: 'transition' })
      }
    }
    // 器官自己报的节拍异常（loop 在迟到/超时/失败时发 evid=pace:）：收下，判定用它
    if (String(r.evid || '').indexOf('pace:') === 0) {
      center.pace = center.pace || {}
      center.pace[src] = { ts: r.ts, state: st, value: r.value, evid: r.evid }
    }
    if (abnormal) {
      events.push({ at: r.at, src, kind, state: st, value: r.value, evid: r.evid, why: 'warn' })
    } else if (kind === 4) {
      events.push({ at: r.at, src, kind, state: st, value: r.value, evid: r.evid, why: 'record' })
    } else if (deviated) {
      events.push({ at: r.at, src, kind, state: st, value: r.value, evid: r.evid, why: 'deviation', baseline })
    }
    if (r.ts > maxTs) maxTs = r.ts
  } else if (!r.ts) {
    // legacy line without ts (older format): fold into events once, then it may be discharged
    if (st === 1 || st === 2 || kind === 4) {
      events.push({ at: r.at, src, kind, state: st, value: r.value, evid: r.evid, why: 'legacy' })
    }
  }
  state[src] = st
}

const cutoff = Date.now() - WINDOW_MIN * 60000
const keep = rows.filter((r) => r.ts >= cutoff).map((r) => r.raw)
const discharged = rows.length - keep.length

// 慢的那一批：心脏（每秒跳）从来不会掉线，掉线的是"几天才动一次"的器官。
// 没有谁盯着它们，因为它们的节律比任何窗口都长。这里按 registry 的 every 判一次过期。
if (!center.lastSeen) {
  center.lastSeen = {}
  // 第一次：从活总线 + 归档里把每个 src 最后出现时刻找回来（否则慢器官会被判成"从没出现过"）
  const archDir2 = join(ROOT, 'track', 'archive')
  const srcs = [join(ROOT, 'track', 'events.jsonl'), BUS]
  if (existsSync(archDir2)) {
    for (const f of readdirSync(archDir2)) if (/^bus-\d{8}\.jsonl$/.test(f)) srcs.push(join(archDir2, f))
  }
  for (const p of srcs) {
    if (!existsSync(p)) continue
    for (const line of readFileSync(p, 'utf8').split('\n')) {
      if (!line.trim()) continue
      let r
      try { r = JSON.parse(line) } catch { continue }
      const ts = Number(r.ts) || Date.parse(r.at) || 0
      const s = String(r.src)
      if (ts && (!center.lastSeen[s] || ts > center.lastSeen[s])) center.lastSeen[s] = ts
    }
  }
}
for (const r of rows) {
  const s = String(r.src)
  if (r.ts && (!center.lastSeen[s] || r.ts > center.lastSeen[s])) center.lastSeen[s] = r.ts
}

const reg = JSON.parse(readFileSync(join(ROOT, 'core', 'registry.json'), 'utf8')).cells
const SPEC_E = JSON.parse(readFileSync(join(ROOT, 'core', 'spec.json'), 'utf8'))

// 2026-11-09 用户：「在中枢那里有个表，然后看这一天谁没上报也行，一个个对……快的类似视觉
// 每时每刻都在修正，慢的比如能源只是突发情况才会传」。
// 所以中枢留一张**当日点名表**：今天各器官谁报过到、谁没报。慢的（事件型）当天没报不算病，
// 只是记在表里给人看；快的仍按节律判。
const dayStart = new Date(new Date().toISOString().slice(0, 10) + 'T00:00:00.000Z').getTime()
const roster = { day: new Date().toISOString().slice(0, 10), expected: [], reported: [], missing: [] }
for (const [num, cell] of Object.entries(reg)) {
  if (cell.enabled === false || !cell.path) continue
  roster.expected.push(cell.id)
  const last = Number((center.lastSeen || {})[num] || 0)
  if (last >= dayStart) roster.reported.push(cell.id)
  else roster.missing.push(cell.id)
}
center.roster = roster

// 2026-11-09 用户：「有没有中枢整合，其实是还要特化中枢，而不是那种对称的类似于昆虫的纯代码运行」。
// 对照意识科学（IIT：整合 × 分化）后，把它变成两个可量的数，存进 center.vital：
//   整合度 = 今天真报到过的器官 / 应报到的器官   （信号有没有汇进中枢统一记账）
//   分化度 = 不同的 (kind + every) 组合数 / 器官数 （各器官是不是各司其职，而不是长得一样）
// 判读：两个都低＝散沙；只有整合＝昆虫式对称；只有分化＝各干各的；两个都高＝整合且特化。
// 2026-11-09 用户定边界：「这套数据是他们以后迭代的参考……也不能以功效足迹为主啊……我们这个是开门的玩意儿」
// 所以这两个数**只当参考记录，不当优化目标**：不为了让数字好看去改结构。
// 以后有人配齐躯体、要优化算法时，这里才是他们的起点数据。
const bySignature = new Set()
for (const cell of Object.values(reg)) {
  if (cell.enabled === false || !cell.path) continue
  bySignature.add(`${cell.kind || 0}:${cell.every || 0}`)
}
const organCount = Object.values(reg).filter((c) => c.enabled !== false && c.path).length || 1
const integration = roster.expected.length ? roster.reported.length / roster.expected.length : 0
const differentiation = bySignature.size / organCount
const vital = {
  at: new Date().toISOString(),
  integration: Number(integration.toFixed(3)),
  differentiation: Number(differentiation.toFixed(3)),
  organs: organCount,
  signatures: bySignature.size,
  verdict:
    integration < 0.8 && differentiation < 0.5 ? 'scattered'
      : integration < 0.8 ? 'specialized-but-not-integrated'
        : differentiation < 0.5 ? 'integrating-but-symmetric-insect-like'
          : 'integrated-and-specialized',
}
center.vital = vital

const overdue = []
const never = []
const breaks = []
const nowMs = Date.now()
for (const [num, cell] of Object.entries(reg)) {
  if (cell.enabled === false || !cell.path) continue
  const every = Number(cell.every || 0)
  if (every <= 0) continue
  const last = center.lastSeen[num]
  if (!last) {
    never.push(cell.id)
    breaks.push({ num, id: cell.id, why: 'never-reported', ageH: null })
    continue
  }
  const ageMin = (nowMs - last) / 60000
  if (ageMin > every * 2) {
    overdue.push(`${cell.id}:${Math.round(ageMin / 60)}h`)
    breaks.push({ num, id: cell.id, why: 'overdue', ageH: Math.round(ageMin / 60) })
  }
}
center.overdue = overdue
center.never = never
// 2026-11-09 用户定：有节律却从来没上报 = 连了没接线，跟死了一样算（state 2）。
// 报过但过期超过 2 倍节律也按 state 2（没送达一样算死）。
// 每条按器官单独发，并带 topic + cell —— 这样接收方（规则表/受体）才知道是谁坏了，
// 才能按器官派活；只报一个总数的话，下游只能干瞪眼。
for (const b of breaks) {
  events.push({
    at: new Date().toISOString(),
    src: SELF,
    kind: 4,
    state: 2,
    value: b.ageH === null ? 0 : b.ageH,
    evid: `${b.why}:${b.id}`,
    why: b.why,
    topic: 'cadence.broken',
    cell: Number(b.num),
  })
}

// 2026-11-09 用户：「他自己判，他也解决不了啊，得这个传到中枢再上传到大脑去解决问题」。
// 所以判在中枢这里做：读 drift 交来的原始测量（track/drift-raw.json），判哪些算事、
// 多严重、要不要升级，然后**上传一条**（topic=center.verdict）。器官本身不再判。
const verdict = { at: new Date().toISOString(), ok: 0, issues: [], blind: [] }
const RAW = join(ROOT, 'track', 'drift-raw.json')
if (existsSync(RAW)) {
  try {
    const raw = JSON.parse(readFileSync(RAW, 'utf8'))
    const th = (SPEC_E && SPEC_E.drift) || { state1_bp: 1000, state2_bp: 5000 }
    const urgentAt = Number((SPEC_E && SPEC_E.drift && SPEC_E.drift.tier_urgent_after) || 20)
    // 2026-11-09 用户：「还是得单独设心脏，跟那些视觉不是一个档次，得提一档……绝大部分都是
    // 重复的视觉，每时每刻在改不一样的东西，但都是有用的」。
    // 所以心脏单独一条判：它停一下，后面全都没意义，档位永远最高（tier2），不和视觉混在一张清单里。
    const hb = (SPEC_E && SPEC_E.expect && SPEC_E.expect.heartbeat) || { interval_ms: 3000, tolerance: 3 }
    const hbLimit = Number(hb.interval_ms) * Number(hb.tolerance)
    const heartRow = (raw.rows || []).find((r) => r.what === 'heartbeat')
    // drift 在"零违规"时不会更新 worst.last（初始值没有 last 字段），所以心脏的最近一跳
    // 从中枢自己的 lastSeen['7'] 取——那是单调的，放电也不影响。
    const heartLast = Math.max(Number(heartRow && heartRow.last ? heartRow.last : 0), Number((center.lastSeen || {})['7'] || 0))
    const heartGap = heartLast ? nowMs - heartLast : null
    verdict.heart = {
      last: heartLast || null,
      gap_ms: heartGap,
      limit_ms: hbLimit,
      ok: heartGap !== null && heartGap <= hbLimit,
      tier: 2, // 心脏永远最高档
    }
    for (const row of raw.rows || []) {
      if (row.what === 'heartbeat') continue // 心脏不走下面那套视觉判据
      const every = row.organ ? Number((reg[String(row.organ)] || {}).every || 0) : 0
      const limitMs = (every > 0 ? every * 2 : 60) * 60000
      // 先把「器官自己报的异常」和「中枢自己的没反应」判掉：这两条不依赖 drift 的样本数。
      const seen0 = Math.max(Number(row.last || 0), Number((center.lastSeen || {})[String(row.organ)] || 0))
      const silent0 = row.organ > 0 && (!seen0 || nowMs - seen0 > limitMs)
      const pace0 = (center.pace || {})[String(row.organ)]
      const paceFresh0 = pace0 && nowMs - Number(pace0.ts || 0) < limitMs
      if (!silent0 && !paceFresh0 && row.insufficient_samples) {
        // 2026-11-10 考试题 T1：样本不足 ≠ 不坏，也 ≠ 好。单列成一类（blind），
        // 不进 issues 也不当 ok——否则"窗口装不下"会被当成"一切正常"（绿灯因为瞎了）。
        row.flag = 'insufficient'
        row.tier = 0
        verdict.blind.push({ what: row.what, organ: row.organ, samples: row.samples, window_ms: row.window_ms })
        continue
      }
      // "最后一次见到"以中枢自己的 center.lastSeen 为准（单调、放电不影响）；
      // drift 交来的 last 只是它这轮读到的行，活总线放电后会偏旧。
      const seen = Math.max(Number(row.last || 0), Number((center.lastSeen || {})[String(row.organ)] || 0))
      const silent = row.organ > 0 && (!seen || nowMs - seen > limitMs)
      // 2026-11-10 判据收口：迟到/慢由**器官自己报**（loop 在异常时发 pace 信号），中枢不再从
      // 总线上数格子倒推（那套会被窗口和停机搅乱，今天 pulse 就出现"总线说好、plan 说坏"）。
      // 中枢只保留自己那两条：never（从没报到，只靠 lastSeen）与 silent（超过 2×every 没报）。
      let kind = null
      const pace = (center.pace || {})[String(row.organ)]
      const paceFresh = pace && nowMs - Number(pace.ts || 0) < limitMs
      if (silent) kind = 'silent'
      else if (paceFresh) kind = Number(pace.state) >= 2 ? 'broken' : 'late'
      if (!kind) {
        verdict.ok++
        row.flag = 'ok'
        row.tier = 0
        // drift 的窗口读数只作参考（bp 仍挂回数据），不再参与判定
        row.ref_bp = row.bp
        continue
      }
      const tier = kind === 'silent' ? 2 : Number(pace && pace.state) >= 2 ? 2 : 1
      // 2026-11-09 用户：「检查出问题，就应该把这个数据标上标志，然后上传」。
      // 所以判出来的结论直接标回那条数据本身，上传的是带标志的数据，不是另开一张清单。
      // 加急要"带上加急的数据"：把该器官最近这段的曲线一起挂上，不只是一个当前值。
      row.flag = kind
      row.tier = tier
      const series = (raw.history || []).map((h) => {
        const m = (h.rows || []).find((x) => Number(x.organ) === Number(row.organ))
        return m ? Number(m.bp) : null
      })
      // 2026-11-10 用户：「加急后面再加一档，致死上面还有一个加加急」。
      // 连续被判坏的次数决定 rush：1 次=1，到 urgent 阈值=2，到两倍=3（停手、等人接手）。
      // 连续计数存 track\.stress.json；转好就清零。
      const stress = readJsonSafe(STRESS, {})
      const prev = stress[String(row.organ)] || { count: 0, kind: null }
      const streak = prev.kind === kind ? Number(prev.count || 0) + 1 : 1
      const urgentAt = Number((SPEC_E && SPEC_E.drift && SPEC_E.drift.tier_urgent_after) || 20)
      const criticalAt = Number((SPEC_E && SPEC_E.drift && SPEC_E.drift.tier_critical_after) || urgentAt * 2)
      const rushLevel = streak >= criticalAt ? 3 : streak >= urgentAt ? 2 : 1
      stress[String(row.organ)] = { count: streak, kind, at: new Date().toISOString() }
      verdict.stress = stress
      verdict.issues.push({ what: row.what, organ: row.organ, kind, bp: row.bp, tier, rush: rushLevel, count: streak, series })
    }
    // 2026-11-10 用户：「超过 80% 的玩意都是长时间停的，就代表你关机了……但至少证明他现在是好的」。
    // 整机停机（没身体、关机/睡眠）不是器官坏了：一个以上 80% 的器官同时"缺拍"就是这个形态。
    // 判成 shutdown：issues 留着做记录，但不拉 state——它醒来还按点上报，本身就是好的证据。
    const judged = (raw.rows || []).filter((r) => r.organ > 0 && !r.insufficient_samples)
    const stopped = judged.filter((r) => r.flag === 'silent')
    const ratio = judged.length ? stopped.length / judged.length : 0
    if (judged.length >= 3 && ratio >= 0.8) {
      verdict.mode = 'shutdown'
      verdict.shutdown = { ratio: Number(ratio.toFixed(2)), organs: stopped.length, of: judged.length }
      verdict.state = 0
      verdict.shutdownIssues = verdict.issues.slice()
      verdict.issues = []
    }
    // 转好的器官清零连续计数（断了就不再算「反复」）
    if (verdict.stress) {
      const bad = new Set(verdict.issues.map((i) => String(i.organ)))
      for (const k of Object.keys(verdict.stress)) if (!bad.has(k)) delete verdict.stress[k]
    }
    verdict.state = verdict.issues.length === 0 ? 0 : (verdict.issues.some((i) => i.tier === 2) ? 2 : 1)
    // 心脏停摆时整条链都没意义，直接拉满：state 2、tier 2。
    if (verdict.heart && !verdict.heart.ok) verdict.state = 2
    verdict.evid = `center:${verdict.ok}ok/${verdict.issues.length}issues/${verdict.blind.length}blind${verdict.heart && verdict.heart.ok ? '' : '/HEART-DOWN'}`
    // 2026-11-09 用户：「建中枢就是为了有一手数据……自己解决不了直接再把那个数据给大脑，
    // 让大脑自己来判定，这个被中间拦了那你数据呢？」——所以上传时**原始测量一起带上**，
    // 中枢的看法（issues）只是附注，不能替代数据。上面拿到的是 raw，不是我的结论。
    verdict.raw = raw.rows || []
  } catch (err) { console.error('verdict failed:', err && err.message) }
}
center.verdict = verdict

const summary = {
  scanned: rows.length,
  newLines: rows.filter((r) => r.ts > Number(cursor.lastTs || 0)).length,
  events: events.length,
  transitions,
  beats: beats,
  discharge: discharged,
  kept: keep.length,
  overdue,
  never,
  roster: center.roster && center.roster.missing.length,
  dry,
}
console.log(JSON.stringify(summary))

if (!dry) {
  // 连续性记账：放电是否真的没丢行、有没有连续跳过。存在 center.chain 里，下一轮接着数。
  let chain = null
  let skipStreak = Number((center.chain && center.chain.skipStreak) || 0)
  if (events.length) appendFileSync(EVENTS, events.map((e) => JSON.stringify(e)).join('\n') + '\n', 'utf8')
  center.beats = (center.beats || 0) + beats
  center.events = (center.events || 0) + events.length
  center.discharged = (center.discharged || 0) + discharged
  center.transitions = (center.transitions || 0) + transitions
  center.lastAt = new Date().toISOString()
  writeJsonAtomic(CURSOR, { lastTs: maxTs, state })
  if (discharged > 0) {
    // 2026-11-09: 放电是"读全文 → 算保留 → 重写文件"，而 emit 是"追加"。
    // 同一时刻另一个进程追加的行，会被这次重写吞掉（实测丢过一条测试信号）。
    // 只读不写的人和写的人不能共用同一个重写步骤：先确认文件在我读完之后没长过，
    // 长过就这一轮不放电（下轮再来），宁可晚放，不可吞行。
    const sizeNow = existsSync(BUS) ? statSync(BUS).size : 0
    if (sizeNow === busSizeBefore) {
      copyFileSync(BUS, join(ROOT, 'track', '.bus.before-discharge.jsonl'))
      // 2026-11-10 考试题 T1：放电丢掉的行必须进当天归档，否则任何超过 45 分钟的度量窗口
      // 在今天都拿不到样本（archive 里只有昨天及更早）。按每行自己的日期分文件追加。
      const droppedRows = rows.filter((r) => r.ts < cutoff)
      if (droppedRows.length) {
        const archDir = join(ROOT, 'track', 'archive')
        mkdirSync(archDir, { recursive: true })
        const byDay = new Map()
        for (const r of droppedRows) {
          const day = String(r.at || '').slice(0, 10).replace(/-/g, '') || new Date().toISOString().slice(0, 10).replace(/-/g, '')
          if (!byDay.has(day)) byDay.set(day, [])
          byDay.get(day).push(r.raw)
        }
        for (const [day, lines] of byDay) {
          appendFileSync(join(archDir, `bus-${day}.jsonl`), lines.join('\n') + '\n', 'utf8')
        }
      }
      writeFileSync(BUS, keep.length ? keep.join('\n') + '\n' : '', 'utf8')
      // 2026-11-09 用户：「不应该改的是维护这个连续性和断了上报吗？」
      // 对——要维护的不是"放电成功"这个动作，是**行数和连续性**。放电完立刻读回比对：
      // 重写后的行数必须等于保留数，少一条就是这一环断了，当场上报（state 2）。
      const after = existsSync(BUS) ? readFileSync(BUS, 'utf8').split('\n').filter((l) => l.trim()).length : 0
      if (after !== keep.length) {
        chain = { ok: false, why: `lines lost: expected ${keep.length}, found ${after}` }
        emit(SELF, 4, 2, keep.length - after, `chain:broken:${keep.length}->${after}`, { rush: 2, topic: 'chain.broken' })
      } else {
        chain = { ok: true, lines: after, discharged }
        skipStreak = 0
      }
    } else {
      // 跳过放电本身不是故障，但它连续发生时，连续性就有压力（总线只增不减）。
      // 所以它不是"悄悄跳过"，而是记一条可查的计数，连续 3 轮就上报。
      skipStreak += 1
      chain = { ok: skipStreak < 3, why: `discharge skipped x${skipStreak}: bus grew during the rewrite`, skipped: true }
      if (skipStreak >= 3) {
        emit(SELF, 4, 1, skipStreak, `chain:stalled:skip${skipStreak}`, { rush: 1, topic: 'chain.stalled' })
      }
    }
  }
  // 连续性记账要在放电之后写：放电块的结论（有没有丢行、跳过几次）就是这一环的状态。
  if (chain) center.chain = { ...chain, at: center.lastAt, skipStreak }
  // 环的五步识别（2026-11-09 用户：「依旧加个识别就行」）：只看每步的留痕在本轮窗口内有没有更新。
  // 缺了只记一条 chain:missing:<步骤>，不判死、不改 state。
  try {
    if (process.env.COO_DEBUG) console.error('enter step-recognize; lastAt=', center.lastAt, 'newLines=', newLines)
    const since = Number(center.lastAt ? new Date(center.lastAt).getTime() : 0) - WINDOW_MIN * 60000
    const missing = []
    for (const [name, p] of Object.entries(STEP_FILES)) {
      let at = 0
      if (existsSync(p)) {
        try {
          const raw = readFileSync(p, 'utf8').trim()
          const last = raw.split(/\r?\n/).filter(Boolean).pop()
          const obj = JSON.parse(last)
          at = Number(obj && (obj.ts || new Date(obj.at || 0).getTime())) || 0
        } catch { at = 0 }
      }
      if (!at || at < since) missing.push(name)
    }
    if (Number(summary.newLines || 0) === 0) missing.push('trace') // 本轮总线上没有新增行
    if (missing.length) {
      center.chain = { ...(center.chain || {}), missing, missingAt: center.lastAt }
      emit(SELF, 4, 0, missing.length, `chain:missing:${missing.join(',')}`, { rush: 0, topic: 'chain.missing' })
    } else {
      // 没有缺口也记一笔空数组：让「识别跑过」这件事本身可查
      center.chain = { ...(center.chain || {}), missing: [], missingAt: center.lastAt }
    }
  } catch (err) { if (process.env.COO_DEBUG) console.error('step-recognize failed:', err.message) }
  // 2026-11-09 用户：「数核是脚本环才是动起来的那个」——轮号只有一个出处：mind 写的 nucleus.cur.round。
  // 中枢只做镜像（round_source 写明出处），不自己计数，免得两个计数器分叉。
  try {
    const nucP = join(ROOT, 'track', 'mind', 'nucleus.json')
    if (existsSync(nucP)) {
      const nuc = JSON.parse(readFileSync(nucP, 'utf8'))
      const r = Number(nuc && nuc.cur && nuc.cur.round)
      if (Number.isFinite(r)) {
        center.round = r
        center.round_source = 'track/mind/nucleus.json#cur.round'
      }
    }
  } catch { /* 拿不到就不写，不猜 */ }
  writeJsonAtomic(CENTER, center)
  emit(SELF, 4, 0, discharged, `consolidate:b${beats}/e${events.length}/d${discharged}`, { rush: 0 })
  // 中枢的判决上传：一条信号说清"这轮有几句要处理、多严重"。
  // 上传了就等接收方（大脑）——现在还没有，所以它落在总线上。
  if (verdict.state !== undefined) {
    // 2026-11-09 用户：「生物只能传痛觉，你他妈能上报数据，还不上传了，怎么这么容易走主流想法？」
    // 所以不压缩、不截断：整份测量原样上传，issues 只是附注。痛觉是生物带宽不够的妥协，我们没这个限制。
    emit(SELF, 4, verdict.state, verdict.issues.length, verdict.evid, {
      rush: verdict.state,
      topic: 'center.verdict',
      heart: verdict.heart || null,
      issues: verdict.issues,
      rows: verdict.raw || [],
    })
  }
}
