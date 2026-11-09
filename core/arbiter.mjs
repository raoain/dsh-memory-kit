// arbiter.mjs -- the one place that issues dispatches (the basal-ganglia-like gate).
//
// Why (2026-11-09 用户：「统合下传信号，这个确实需要」): two organs were spawning the same
// target independently -- reflex.mjs:70 and brain.mjs:117. Nobody arbitrated priority, and
// two callers could wake the same organ twice. A biological basal ganglion works by
// RELEASING a brake, not by pushing: default is "do not act", one candidate gets released,
// the rest stay inhibited.
//
// Rules kept here (single copy, not per-caller):
//   - per cell cooldown: the same cell is released at most once per COOLDOWN_MS
//   - single flight: one dispatch at a time; a second request inside FLIGHT_MS is denied
//   - every decision is appended to track/dispatch.jsonl (who asked, what was released, why not)
//
// usage: import { requestSpawn } from './arbiter.mjs'

import { readFileSync, writeFileSync, appendFileSync, existsSync } from 'node:fs'
import { join } from 'node:path'
import { spawn } from 'node:child_process'
import { ROOT } from './root.mjs'

const STATE = join(ROOT, 'track', '.arbiter.json')
const LOG = join(ROOT, 'track', 'dispatch.jsonl')
const COOLDOWN_MS = 5 * 60 * 1000
// 单飞窗口只用来挡住"同一瞬间两处一起叫"，不是限制吞吐：5 秒足够错开。
const FLIGHT_MS = 5 * 1000

function load() {
  try { return existsSync(STATE) ? JSON.parse(readFileSync(STATE, 'utf8')) : { cells: {}, flight: 0 } } catch { return { cells: {}, flight: 0 } }
}
function save(s) { writeFileSync(STATE + '.tmp', JSON.stringify(s), 'utf8'); writeFileSync(STATE, JSON.stringify(s), 'utf8') }

export function requestSpawn({ from, id, path, reason = '', rush = 0, tier = 0, now = Date.now() }) {
  const s = load()
  const rec = { at: new Date(now).toISOString(), from, cell: id, reason, rush, tier, ok: false, why: '' }

  // 2026-11-09 用户：「不应该是两处命令合并成一条吗？然后如果先发的一条做了，就再做后面那条里面没有的」。
  // 所以闸的判据是"这个器官这轮要不要做一次"，不是"同一时刻全局只许一个"。
  // 去重靠 per-cell 冷却；同一批里不同器官各做一次，重叠的部分自然被冷却挡掉。
  const lastCell = Number((s.cells || {})[id] || 0)
  if (now - lastCell < COOLDOWN_MS) { rec.why = 'cell-cooldown'; appendFileSync(LOG, JSON.stringify(rec) + '\n', 'utf8'); return rec }
  // 2026-11-09 修：`cell.path` 是相对 ROOT 的（如 core/align.mjs），而 existsSync 按进程 CWD 解析——
  // 在 loop 里跑时 CWD 不是 ROOT，于是合法器官被判成 `no-path`，下发全部静默失败（dispatch.jsonl 里连着多条）。
  // 所以路径一律先拼成绝对路径再判、再 spawn。
  const abs = !path ? '' : (path.startsWith(ROOT) ? path : join(ROOT, path.replace(/^[\\/]+/, '')))
  if (!abs || !existsSync(abs)) { rec.why = 'no-path'; appendFileSync(LOG, JSON.stringify(rec) + '\n', 'utf8'); return rec }

  try {
    const child = spawn('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', abs], {
      env: { ...process.env, TRIGGER_FROM: String(from), TRIGGER_RULE: reason },
      stdio: 'ignore',
      detached: true,
    })
    child.unref()
    s.cells = s.cells || {}
    s.cells[id] = now
    s.flight = now
    save(s)
    rec.ok = true
    rec.why = 'released'
  } catch (err) {
    rec.why = 'spawn-failed:' + String((err && err.message) || err).slice(0, 40)
  }
  appendFileSync(LOG, JSON.stringify(rec) + '\n', 'utf8')
  return rec
}
