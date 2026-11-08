// core/reflex.mjs -- the simple reflex center.
//
// Reads new bus signals, matches core/rules.json, and spawns the target organ.
// It does NOT judge: `state` and `rush` come from the organs. It only decides
// who acts, and in what order.
//
// Design notes:
//   - No memory, no world model: only the current signal matters (Russell & Norvig, simple reflex agent).
//   - Multiple rules may fire at once; actions are sorted by rush desc, then by rule id (conflict resolution).
//   - A rule with spawn:0 means inhibition -- matching it produces no action.
//   - Its own signal (src 7) is recorded so its runs are on the bus too.
//
// usage: node core/reflex.mjs [--dry] [--all]

import { readFileSync, writeFileSync, existsSync } from 'node:fs'
import { join } from 'node:path'
import { spawn } from 'node:child_process'
import { emit } from './bus.mjs'

// root comes from core/root.mjs -- do not hardcode the path here
import { ROOT } from './root.mjs'
const BUS = join(ROOT, 'track', 'bus.jsonl')
const CUR = join(ROOT, 'track', '.reflex-cursor')
const SELF = '7'
// 语义编号从 spec 取，不在本地写死（2026-11-08：规则抄多遍必歪）
const SPEC = JSON.parse(readFileSync(join(ROOT, 'core', 'spec.json'), 'utf8'))
const KIND_JUDGE = Number(Object.keys(SPEC.kind).find((k) => SPEC.kind[k] === 'judge') ?? 1)
const COOLDOWN = 300000 // 5 min per rule, prevents self-trigger loops (pin -> pin)
const CD = join(ROOT, 'track', '.reflex-cooldown.json')

const reg = JSON.parse(readFileSync(join(ROOT, 'core', 'registry.json'), 'utf8'))
const rulesFile = JSON.parse(readFileSync(join(ROOT, 'core', 'rules.json'), 'utf8'))
const cells = reg.cells || {}
const rules = rulesFile.rules || []

function matches(when, sig) {
  for (const [k, v] of Object.entries(when)) {
    // 2026-11-08: rules use STATE NAMES (pass/warn/fail/unknown), not numbers. The numbers
    // live in spec.state only -- if rules.json carried its own copy, renumbering in spec
    // would silently disable a rule (same class as the thrice-copied state->rush).
    let want = v
    if (k === 'state' && typeof v === 'string') {
      const found = Object.keys(SPEC.state).find((n) => SPEC.state[n] === v)
      if (found === undefined) return false // unknown name: never match, never guess
      want = found
    }
    if (Number(sig[k]) !== Number(want)) return false
  }
  return true
}

const dry = process.argv.includes('--dry')
const all = process.argv.includes('--all')

// 常驻中枢（2026-11-08）：中枢必须常驻，器官可以按需。
//   --loop N  每 N 秒醒一次（默认 5）—— 这是中枢的正常形态
//   不带 --loop 只跑一次（便于测试/被外部定时器调）
function runOnce() {
  const lines = readFileSync(BUS, 'utf8').split('\n').filter(Boolean)
  let start = all ? 0 : Number(existsSync(CUR) ? readFileSync(CUR, 'utf8').trim() : 0) || 0
  if (start > lines.length) start = 0

  const fired = []
  const cd = existsSync(CD) ? JSON.parse(readFileSync(CD, 'utf8')) : {}
  const nowMs = Date.now()
  for (let i = start; i < lines.length; i++) {
    let sig
    try { sig = JSON.parse(lines[i]) } catch { continue }
    if (String(sig.src) === SELF) continue

    const hits = rules
      .filter((r) => matches(r.when, sig))
      .map((r) => ({ rule: r.id, spawn: Number(r.then.spawn || 0), rush: Number(r.rush ?? sig.rush ?? 0) }))
      .sort((a, b) => b.rush - a.rush || a.rule - b.rule)

    for (const h of hits) {
      if (h.spawn === 0) { fired.push(`${sig.src}->inhibit(rule${h.rule})`); continue }
      const cell = cells[String(h.spawn)]
      if (!cell) { fired.push(`${sig.src}->unknown-cell(${h.spawn})`); continue }
      if (nowMs - (cd[String(h.rule)] || 0) < COOLDOWN) { fired.push(`skip-cooldown(rule${h.rule})`); continue }
      cd[String(h.rule)] = nowMs
      fired.push(`${sig.src}->${h.spawn}(${cell.id}) rush=${h.rush}`)
      if (dry) continue
      try {
        const child = spawn('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', join(ROOT, cell.path)], {
          env: { ...process.env, TRIGGER_FROM: String(sig.src), TRIGGER_STATE: String(sig.state), TRIGGER_RULE: String(h.rule) },
          stdio: 'ignore',
          detached: true,
        })
        child.unref()
      } catch { fired.push('spawn-failed:' + cell.id) }
    }
  }

  if (!dry) { writeFileSync(CUR, String(lines.length), 'utf8'); writeFileSync(CD, JSON.stringify(cd), 'utf8') }

  // 每次醒都上报，但有东西可做才 state 0；空转记 3（不知道干了什么）
  const state = fired.length === 0 ? 3 : 0
  if (!dry) {
    const rush = Number((SPEC.map?.state_to_rush || { 0: 0, 1: 1, 2: 2, 3: 1 })[String(state)] ?? 1)
    emit(SELF, KIND_JUDGE, state, fired.length, `reflex:${start}->${lines.length}`, { rush })
  }
  return { scanned: lines.length - start, fired: fired.length, dry, detail: fired.slice(0, 10) }
}

const loopIdx = process.argv.indexOf('--loop')
if (loopIdx >= 0) {
  const sec = Number(process.argv[loopIdx + 1]) || 5
  process.stdout.write(`center: loop every ${sec}s (pid ${process.pid})\n`)
  const tick = () => { try { runOnce() } catch (e) { process.stderr.write(`center tick failed: ${e.message}\n`) } }
  tick()
  setInterval(tick, sec * 1000)
} else {
  console.log(JSON.stringify(runOnce()))
}
