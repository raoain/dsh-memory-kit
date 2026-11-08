// core/self.mjs -- self view (8). "Am I still shaped like me?"
//
// Reads the last window of bus signals, reduces them to one numeric profile, and
// compares it with track/self-baseline.json. This is the immune-style check:
// not "is each item right" but "does the whole look like me".
//
// Profile (small on purpose):
//   { n, by_src:{src:count}, state:{0:..,1:..,2:..,3:..}, rush_max }
//
// Verdict:
//   0 = looks like me
//   1 = drifting (one of the two profiles moved a lot)
//   2 = not me (silence, or state distribution far off)
//
// usage:
//   node core/self.mjs              compare against baseline, emit a signal
//   node core/self.mjs --calibrate  (re)write the baseline from the current window
//   node core/self.mjs --dry        print the profile and the diff, emit nothing

import { readFileSync, writeFileSync, existsSync } from 'node:fs'
import { join } from 'node:path'
import { emit } from './bus.mjs'

// root comes from core/root.mjs -- do not hardcode the path here
import { ROOT } from './root.mjs'
const BUS = join(ROOT, 'track', 'bus.jsonl')
const BASE = join(ROOT, 'track', 'self-baseline.json')   // 动态自体（信号轮廓）；静态自体在 baseline.json，由 baseline.ps1 写
                                                          // 2026-11-08 拆开：两个写者共用一个文件，谁写谁覆盖另一拨
const SELF = '8'
const SPEC = JSON.parse(readFileSync(join(ROOT, 'core', 'spec.json'), 'utf8'))
const cells = JSON.parse(readFileSync(join(ROOT, 'core', 'registry.json'), 'utf8')).cells
const WINDOW = 40          // how many recent signals make "a day"
const SILENCE_RATIO = 0.4  // fewer than 40% of the usual count = silence
const DRIFT_WARN = 0.25
const DRIFT_FAIL = 0.50

function profile(signals) {
  const bySrc = {}
  const byState = { 0: 0, 1: 0, 2: 0, 3: 0 }
  let rushMax = 0
  for (const s of signals) {
    if (String(s.src) === SELF) continue
    bySrc[s.src] = (bySrc[s.src] || 0) + 1
    if (s.state !== undefined) byState[Number(s.state)] = (byState[Number(s.state)] || 0) + 1
    if (Number(s.rush || 0) > rushMax) rushMax = Number(s.rush)
  }
  const n = Object.values(bySrc).reduce((a, b) => a + b, 0)
  return { n, bySrc, byState, rushMax }
}

// relative difference of two count maps, averaged over keys; 0 = identical
function relDiff(a, b) {
  const keys = new Set([...Object.keys(a), ...Object.keys(b)])
  let sum = 0
  for (const k of keys) {
    const x = Number(a[k] || 0)
    const y = Number(b[k] || 0)
    const m = Math.max(x, y, 1)
    sum += Math.abs(x - y) / m
  }
  return keys.size ? sum / keys.size : 0
}

const all = readFileSync(BUS, 'utf8').split('\n').filter(Boolean).map((l) => {
  try { return JSON.parse(l) } catch { return null }
}).filter(Boolean)

// 照镜子按区域分开查（2026-11-08 用户纠正：「不应该是每个区域自己查吗？心跳跟肠胃蠕动是两个极端」）。
// 两条一起用，缺一不可：
//   ① 剔掉纯心跳（registry 里 heartbeat: true 的器官）——它每几秒一跳、内容恒定，跳只证明还活着，
//      不携带信息。它的节律由 pulse 查，不归 self 管。
//   ② 剩下的按器官分桶，每个各取最近 PER_SRC 条——一个总数取窗口等于「谁跑得勤谁代表我」。
const PER_SRC = 10
const HEARTBEAT = new Set(
  Object.entries(cells).filter(([, c]) => c.heartbeat === true).map(([num]) => String(num))
)
const buckets = {}
for (const s of all) {
  const k = String(s.src)
  if (HEARTBEAT.has(k)) continue
  if (!buckets[k]) buckets[k] = []
  buckets[k].push(s)
}
const win = Object.values(buckets).flatMap((arr) => arr.slice(-PER_SRC))
const now = profile(win)

const calibrate = process.argv.includes('--calibrate')
const dry = process.argv.includes('--dry')

if (calibrate) {
  // 自己的文件自己写全（2026-11-08 拆成 self-baseline.json 后，这里只碰自己的文件，再不会碰静态自体）
  const out = { at: new Date().toISOString(), window: WINDOW, perSrc: PER_SRC, profile: now }
  writeFileSync(BASE, JSON.stringify(out, null, 2), 'utf8')
  console.log(JSON.stringify({ calibrated: true, file: 'track/self-baseline.json', profile: now }))
  process.exit(0)
}

if (!existsSync(BASE)) {
  writeFileSync(BASE, JSON.stringify({ at: new Date().toISOString(), window: WINDOW, perSrc: PER_SRC, profile: now }, null, 2), 'utf8')
  if (!dry) emit(SELF, 1, 0, 0, 'self:baseline-created', { rush: 0 })
  console.log(JSON.stringify({ note: 'baseline created', profile: now }))
  process.exit(0)
}

const baseFile = JSON.parse(readFileSync(BASE, 'utf8'))
const base = baseFile.profile
if (!base) {
  if (!dry) emit(SELF, 1, 3, 0, 'self:no-profile', { rush: 1 })
  console.log(JSON.stringify({ note: 'self-baseline.json has no profile: run node core/self.mjs --calibrate' }))
  process.exit(0)
}
const srcDiff = relDiff(now.bySrc, base.bySrc)
const stateDiff = relDiff(now.byState, base.byState)
const diff = Math.max(srcDiff, stateDiff)

let state = 0
let why = 'looks-like-me'
if (now.n < base.n * SILENCE_RATIO) { state = 2; why = 'silence' }
else if (diff >= DRIFT_FAIL) { state = 2; why = 'not-me' }
else if (diff >= DRIFT_WARN) { state = 1; why = 'drifting' }

const rush = Number((SPEC.map?.state_to_rush || { 0: 0, 1: 1, 2: 2, 3: 1 })[String(state)] ?? 1)
const evid = `self:${why}:${diff.toFixed(2)}`
if (dry) {
  console.log(JSON.stringify({ dry: true, now, base, srcDiff, stateDiff, state, why }))
} else {
  console.log(JSON.stringify(emit(SELF, 1, state, Number(diff.toFixed(2)), evid, { rush, counts: [now.n, base.n] })))
}
