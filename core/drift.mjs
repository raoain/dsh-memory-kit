// drift.mjs -- organ 15: the general center (brainstem): measures every organ, judges nothing by itself.
//
// It does NOT decide, act, or summarize. It measures the gap between the bus and
// spec.expect and reports that gap as a number. Acting on the gap is the immune layer.
//
// 2026-11-08 v2, after checking how the field does it:
//   v1 measured the INSTANT gap (how many ms late right now). That is noisy by nature:
//   restarting the timers made it report state 1 for 21 seconds, then self-clear. The
//   user asked whether to look at prior art first -- the answer was yes, and prior art
//   agrees: SLO burn-rate alerting ([Splunk]) and error-difference rules ([Politecnico di
//   Milano thesis]) both judge a WINDOW, not an instant. An instant is a sample; a window
//   is a signal.
//
// So v2 reports, per expectation, how much of the window was in violation:
//   ratio = violatedSamples / totalSamples   (0..1)
//   value = ratio * 10000                    (basis points, integer -- spec says numbers)
//
// usage: node core/drift.mjs [--dry]

import { readFileSync, writeFileSync, existsSync, readdirSync, renameSync } from 'node:fs'
import { join } from 'node:path'
import { ROOT } from './root.mjs'
import { emit } from './bus.mjs'

const SPEC = JSON.parse(readFileSync(join(ROOT, 'core', 'spec.json'), 'utf8'))
const REG = JSON.parse(readFileSync(join(ROOT, 'core', 'registry.json'), 'utf8'))
const BUS = join(ROOT, 'track', 'bus.jsonl')

const dry = process.argv.includes('--dry')
const now = Date.now()
// 2026-11-10 用户：「它还是全系统唯一的时钟，那标准就可以以心跳为主」。
// 所有时间量都用「拍」表示（1 拍 = spec.expect.time_base.interval_ms），
// 心跳频率一改，窗口/采样/停机阈值全部跟着改，不用各处再改常量。
const TIME_BASE = (SPEC.expect && SPEC.expect.time_base) || { interval_ms: 3000, beats: {} }
const BEAT_MS = Number(TIME_BASE.interval_ms || 3000)
const BEATS = TIME_BASE.beats || {}
const WINDOW_MS = Number(BEATS.short_window || 600) * BEAT_MS // 短窗口 = 600 拍
const SAMPLE_MS = Number(BEATS.sample || 20) * BEAT_MS // 每个采样点 20 拍

function readBus() {
  const out = []
  if (existsSync(BUS)) {
    for (const line of readFileSync(BUS, 'utf8').split('\n')) {
      if (!line.trim()) continue
      try { out.push(JSON.parse(line)) } catch { /* skip torn line */ }
    }
  }
  // 2026-11-09: the live bus is now discharged after 45 minutes (consolidate), but this loop
  // measures windows of up to 4 days. Reading the live file alone would count "discharged" as
  // "never reported". History lives in track/archive, so the measurement must read both.
  const ARCH = join(ROOT, 'track', 'archive')
  if (existsSync(ARCH)) {
    for (const f of readdirSync(ARCH).filter((x) => /^bus-\d{8}\.jsonl$/.test(x))) {
      for (const line of readFileSync(join(ARCH, f), 'utf8').split('\n')) {
        if (!line.trim()) continue
        try { out.push(JSON.parse(line)) } catch { /* skip torn line */ }
      }
    }
  }
  return out
}

const bus = readBus()
const cutoff = now - WINDOW_MS

// group ALL of the bus by src. The window is applied later, per row, because a slow organ
// needs a longer window than the fast one -- building the index from a pre-cut array was a
// real bug (2026-11-08): the per-organ window could not reach data the index had dropped.
const DATA_START = bus.reduce((m, r) => { const v = Number(r.ts); return v && (m === 0 || v < m) ? v : m }, 0)
// 2026-11-10 去重：放电会把行追加进当天归档，而 bus-rotate 跨天也会写同一个归档文件，
// 同一条信号可能出现两次。ts 相同就只算一次，否则样本数与「缺拍比例」都会被放大。
const bySrc = new Map()
const seenTs = new Set()
for (const r of bus) {
  const ts = Number(r.ts)
  const key = String(r.src) + '|' + ts
  if (seenTs.has(key)) continue
  seenTs.add(key)
  const k = String(r.src)
  if (!bySrc.has(k)) bySrc.set(k, [])
  bySrc.get(k).push(ts)
}
const inWindow = bus.filter((r) => Number(r.ts) >= cutoff)

// how many samples were "late"? The window must be longer than the period being observed,
// otherwise the answer measures "the window is too short", not "it is late" (2026-11-08:
// a 30-minute window over a 30-minute organ reported 19% violation that did not exist).
//
// 2026-11-08 v3, after a real fault test: the heartbeat was stopped for 103 seconds
// (completely dead -- it should beat every 3 s) and this reported state=0 value=645bp,
// i.e. it said everything was fine. Cause: a single 30-minute window averages a short
// outage away. 103 s of death inside 1800 s of window is only 6% of samples.
// Fix = what SLO burn-rate alerting actually does: judge SEVERAL windows at once and take
// the worst. A short window catches acute failure; a long one catches slow decay.
// 2026-11-10 用户：「自己对比一下，两方面记录不就好了吗？一方面有记录就代表肯定坏了，
// 但这两方面都是差不多时间停的，这代表肯定是关机了」。
// 所以判据不是固定阈值，而是**两边对比**：
//   心跳停 且 器官也停，同一时间 → 关机/宿主停摆（不算器官的错）；
//   心跳在跳 而器官停 → 才是器官真坏了。
// 心跳 3 秒一跳，所以任何 >9 秒的缺口都说明"宿主没在跑"；>30 分钟的算关机，其余算宿主停顿。
const HB_LIMIT_MS = Number((SPEC.expect && SPEC.expect.heartbeat && SPEC.expect.heartbeat.interval_ms) || 3000) *
  Number((SPEC.expect && SPEC.expect.heartbeat && SPEC.expect.heartbeat.tolerance) || 3)
const SHUTDOWN_MIN_MS = Number(BEATS.shutdown || 600) * BEAT_MS // 关机阈值 = 600 拍
// busyStamps = 除心跳外所有器官的时间戳。一个心跳缺口如果**别的器官在里面报过**
// 就不是关机（整机在跑，停的只是心跳），标记成 heart-stall，且不拿它去替器官开脱。
function hostPauses(hbStamps, busyStamps = []) {
  const s = [...hbStamps].sort((a, b) => a - b)
  const out = []
  for (let i = 1; i < s.length; i++) {
    const gap = s[i] - s[i - 1]
    if (gap <= HB_LIMIT_MS) continue
    const alive = busyStamps.some((t) => t > s[i - 1] && t < s[i])
    out.push({
      from: s[i - 1],
      to: s[i],
      ms: gap,
      kind: alive ? 'heart-stall' : gap > SHUTDOWN_MIN_MS ? 'shutdown' : 'stall',
      organs_alive: alive,
    })
  }
  return out
}

function violatedSamples(stamps, limitMs, winMs, dataStart, pauses = []) {
  if (!stamps.length) return { violated: 0, total: 0, last: null, window_ms: winMs, paused: 0 }
  const from = now - winMs
  const sorted = [...stamps].sort((a, b) => a - b)
  let violated = 0
  let total = 0
  let paused = 0
  for (let t = from; t <= now; t += SAMPLE_MS) {
    // 2026-11-09: the stream is discharged after ~1 hour, so the oldest part of a 2-hour or
    // 4-day window has no data at all. "No data" is not "no signal": only judge a sample when
    // the observation window could actually have contained one.
    if (t - limitMs < dataStart) continue
    // 两边对比（2026-11-10 用户：「心脏都停了，其他的玩意儿还有记录在表，坏得很彻底；
    // 或者心跳一般有记录、其他的没有」）：
    //   心跳停 + 这个器官**在这个区间里也没有记录** → 关机，不算它违约；
    //   心跳停 + 这个器官**有记录** → 不是关机，是心跳自己坏了，剩下照判，不能替它开脱。
    const p = pauses.find((x) => t > x.from && t < x.to)
    if (p) {
      const organAliveInPause = sorted.some((s) => s > p.from && s < p.to)
      if (!organAliveInPause) { paused++; continue }
    }
    total++
    let last = null
    for (const s of sorted) { if (s <= t) last = s; else break }
    const age = last === null ? Infinity : t - last
    if (age > limitMs) violated++
  }
  return { violated, total, last: sorted[sorted.length - 1], window_ms: winMs, paused }
}

const MIN_SAMPLES = Number(BEATS.min_samples || 8)
const esper = SPEC.expect
const rows = []

// window set: the short one guards against acute failure, the long one against slow decay.
// Both must be longer than the observed period (a window shorter than the period measures
// the window, not the organ).
function windowsFor(limitMs, everyMs = 0) {
  // 2026-11-10 修（考试题 T1）：窗口必须装得下足够多的拍，否则量的是"格子太少"不是"器官坏了"。
  // pulse(every=30min) 原来只拿到 2 小时窗口 = 4 格，缺两拍就 50% → broken，而它自报 state 0。
  const minBySamples = everyMs > 0 ? everyMs * MIN_SAMPLES : 0
  const short = Math.max(5 * 60 * 1000, limitMs * 2, minBySamples)
  const long = Math.max(30 * 60 * 1000, limitMs * 2, minBySamples)
  return short === long ? [long] : [short, long]
}

function judge(what, limitMs, stamps, everyMs = 0, pauses = []) {
  const wins = windowsFor(limitMs, everyMs)
  let worst = { violated: 0, total: 0, bp: 0, window_ms: 0 }
  for (const w of wins) {
    const st = violatedSamples(stamps, limitMs, w, DATA_START, pauses)
    const bp = st.total ? Math.round((st.violated / st.total) * 10000) : 0
    if (bp > worst.bp) worst = { ...st, bp, window_ms: w }
  }
  // also keep the acute reading separately so a short outage is never hidden by a long window
  const acute = violatedSamples(stamps, limitMs, wins[0], DATA_START, pauses)
  const acuteBp = acute.total ? Math.round((acute.violated / acute.total) * 10000) : 0
  // 样本数 = 窗口内**真实信号条数**，不是网格点数：网格点永远够，用它判会永远"够"
  const from = now - (worst.window_ms || wins[0])
  const observed = [...stamps].filter((t) => t >= from).length
  const insufficient = everyMs > 0 && observed < MIN_SAMPLES
  return {
    what,
    limit_ms: limitMs,
    bp: insufficient ? null : worst.bp,
    window_ms: worst.window_ms,
    acute_bp: insufficient ? null : acuteBp,
    samples: observed,
    // 这一轮有多少采样点是因为"宿主没在跑"而被跳过——它是"关机不算违约"的账
    paused_skipped: Number(worst.paused || 0),
    insufficient_samples: insufficient || undefined,
    last: worst.last,
  }
}

// 1) heartbeat —— 只测量，不判（2026-11-10 用户：「以前是没中枢，现在有总中枢了，就该给他管」）。
// 限值、tier、state 全由 consolidate 的 verdict.heart 判；这里只交 last / gap_ms。
// 原来这里也用 spec.expect.heartbeat 算了一遍 limit 和 bp，同一条规则在两个地方各读一次 spec。
const hbStamps = (bySrc.get('7') || []).slice().sort((a, b) => a - b)
const hbLast = hbStamps.length ? hbStamps[hbStamps.length - 1] : null
// 反向证据（2026-11-10 用户）：「心跳一般有记录、其他的没有」是别人坏了；
// 反过来「心跳停、其他还有记录」就是心跳自己坏了。所以这里数一下：
// 在心跳的停顿区间里，别的器官是否还在报。
const busyStamps = bus.filter((r) => String(r.src) !== '7').map((r) => Number(r.ts))
const hbPauses = hostPauses(hbStamps, busyStamps)
let aliveDuringPause = 0
for (const p of hbPauses) {
  for (const r of bus) {
    if (String(r.src) === '7') continue
    const ts = Number(r.ts)
    if (ts > p.from && ts < p.to) aliveDuringPause++
  }
}
rows.push({
  what: 'heartbeat',
  last: hbLast,
  gap_ms: hbLast ? now - hbLast : null,
  window_ms: 0,
  samples: hbStamps.length,
  // >0 说明心跳停的时候别人还在报 → 停的是心跳，不是整机
  alive_during_pause: aliveDuringPause,
})

// 2) organs with a cadence
for (const [id, cell] of Object.entries(REG.cells || {})) {
  if (!cell.path) continue
  const every = Number(cell.every ?? 0)
  if (!(every > 0)) continue
  const limit = every * 60 * 1000 * 2
  // 两边对比：只有「心跳停 且 这个器官在里面也没报」的区间才算关机，可以用来免它的违约；
  // 心跳停但器官在报（heart-stall）不能拿来替器官开脱。
  const hostPauseList = hbPauses.filter((p) => p.kind !== 'heart-stall')
  // 把该器官自己的节律传进去：窗口要装得下至少 MIN_SAMPLES 拍（2026-11-10 T1）
  rows.push(judge(`organ_${id}_${cell.id}`, limit, bySrc.get(String(id)) || [], every * 60 * 1000, hostPauseList))
}

// the reported value is the worst of (worst window bp, acute window bp). The acute reading is
// folded in so a short outage can never be averaged away by the long window.
let worstBp = 0
for (const r of rows) {
  r.bp = Math.max(r.bp || 0, r.acute_bp || 0)
  if (r.bp > worstBp) worstBp = r.bp
}

// a row counts as breached when any window says so
const breached = rows.filter((r) => r.bp > 0)

// severity thresholds live in spec.expect.drift too -- "how much counts as real" is part of
// the expectation, not a number to invent here (2026-11-08).
const th = esper.drift || { state1_bp: 1000, state2_bp: 5000 }
let state = 0
if (!inWindow.length) state = 3
else if (worstBp >= th.state2_bp) state = 2
else if (worstBp >= th.state1_bp) state = 1

const payload = {
  state,
  value: worstBp,
  evid: `drift:${breached.length}/${rows.length}:${worstBp}bp`,
  rows,
}


// 2026-11-09 用户：「他自己判，他也解决不了啊，得这个传到中枢再上传到大脑去解决问题」。
// 所以 drift 退成纯测量器：只交原始数（每个器官最后一次、距今多久、窗口违规比例），
// 不判严重度、不判档位、不发主题信号。判与上传都在 core/consolidate.mjs（中枢）。
const organOf = (what) => { const m = String(what).match(/^organ_(\d+)_/); return m ? Number(m[1]) : 0 }
const RAW_F = join(ROOT, 'track', 'drift-raw.json')
// 2026-11-09 用户：「这种每时每刻都在改的，只能把他的平常数据整合，然后出现问题就加急，
// 然后带上加急的数据」。所以初级中枢除了交当前快照，还留一小段历史（最近 20 轮），
// 出问题时上面能拿到"那段时间的曲线"，而不是只有一个数。
const HISTORY_KEEP = 20
let prevHistory = []
if (existsSync(RAW_F)) {
  try { prevHistory = (JSON.parse(readFileSync(RAW_F, 'utf8')).history || []).slice(-HISTORY_KEEP) } catch { prevHistory = [] }
}
const snap = { at: new Date().toISOString(), rows: rows.map((r) => ({ organ: organOf(r.what), bp: r.bp || 0, last: r.last || null })) }
const history = [...prevHistory, snap].slice(-HISTORY_KEEP)
const raw = {
  at: snap.at,
  rows: rows.map((r) => ({ what: r.what, organ: organOf(r.what), last: r.last || null, gap_ms: r.gap_ms === undefined ? null : r.gap_ms, bp: r.bp === null ? null : r.bp || 0, window_ms: r.window_ms || 0, samples: r.samples || 0, paused_skipped: r.paused_skipped || 0, alive_during_pause: r.alive_during_pause === undefined ? null : r.alive_during_pause, insufficient_samples: r.insufficient_samples || false })),
  heartbeat: rows.find((r) => r.what === 'heartbeat') || null,
  worst_bp: worstBp,
  history,
}
if (dry) {
  console.log(JSON.stringify(raw, null, 2))
} else {
  writeFileSync(RAW_F + '.tmp', JSON.stringify(raw), 'utf8')
  renameSync(RAW_F + '.tmp', RAW_F)
  // 2026-11-09 断连修复：改成纯测量器以后它一条信号都不发了，于是自己在总线上"消失"，
  // pulse 报 never-reported、上游也没法确认它还活着。测量本身也是一条数据，照发。
  emit('15', 4, 0, worstBp, `measure:${raw.rows.length}rows/${worstBp}bp`, { rush: 0, topic: 'measure' })
  console.log(JSON.stringify({ measured: raw.rows.length, worst_bp: worstBp, history: history.length }))
}
