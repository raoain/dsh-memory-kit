// loop.mjs -- the ONLY way to start a repeating organ loop, and it guarantees one instance.
//
// Why this exists (2026-11-08): the duplicate-driver guard used to live in coo-watchdog.cmd,
// so calling start-timers.vbs directly bypassed it; moving the guard into the vbs helped,
// but /force and a hand-rolled `powershell -Command while(...)` could still add a set.
// The user's point: this thing should be stable and singular BY ITSELF, not because someone
// remembers which entry point to use.
//
// So each loop now asks "am I already running?" before it starts, using a lock file that
// holds its own PID. If the PID in the lock is alive and is not me, I exit. That check runs
// inside the loop, so it holds no matter who starts it or how many times.
//
// usage:
//   node core/loop.mjs --name reflex --every 3 -- node core/reflex.mjs
//   node core/loop.mjs --name sweep  --every 1800 -- node core/bus-rotate.mjs --then node core/pulse.mjs
//
// exit: 0 = did the work (or exited because another instance holds the lock), 2 = bad args

import { readFileSync, writeFileSync, existsSync, mkdirSync, unlinkSync } from 'node:fs'
import { join } from 'node:path'
import { spawnSync } from 'node:child_process'
import { ROOT } from './root.mjs'

function arg(name, dflt) {
  const i = process.argv.indexOf(name)
  return i >= 0 && process.argv[i + 1] !== undefined ? process.argv[i + 1] : dflt
}

const name = arg('--name', '')
const every = Number(arg('--every', '60'))
const cell = String(arg('--cell', '0'))
const sep = process.argv.indexOf('--')
if (!name || !(every > 0) || sep < 0) {
  console.error('usage: node core/loop.mjs --name <n> --every <sec> -- <cmd...>')
  process.exit(2)
}
const cmd = process.argv.slice(sep + 1)
if (!cmd.length) { console.error('no command after --'); process.exit(2) }

const lockDir = join(ROOT, 'track', '.locks')
const lockP = join(lockDir, `${name}.lock`)
if (!existsSync(lockDir)) mkdirSync(lockDir, { recursive: true })

function alive(pid) {
  if (!pid) return false
  try { process.kill(pid, 0); return true } catch { return false }
}

// --- single instance check -----------------------------------------------------------
// 2026-11-08: existsSync-then-writeFileSync is NOT atomic -- two loops started at the same
// moment both see "no lock" and both write their own pid, which is exactly how seven node
// loops ended up running while four locks existed. Claim the lock by CREATING it exclusively
// ('wx' fails if it exists); only after losing that race do you read what is inside.
import { openSync, writeSync, closeSync, unlinkSync as rmSync } from 'node:fs'

function claimLock() {
  try {
    const fd = openSync(lockP, 'wx')
    writeSync(fd, String(process.pid))
    closeSync(fd)
    return { ok: true, holder: process.pid }
  } catch {
    let holder = 0
    try { holder = Number(readFileSync(lockP, 'utf8').trim()) } catch { /* unreadable */ }
    if (holder && holder !== process.pid && alive(holder)) return { ok: false, holder }
    // stale lock (holder gone): remove and try once more
    try { rmSync(lockP) } catch { /* ignore */ }
    try {
      const fd = openSync(lockP, 'wx')
      writeSync(fd, String(process.pid))
      closeSync(fd)
      return { ok: true, holder: process.pid }
    } catch {
      let h2 = 0
      try { h2 = Number(readFileSync(lockP, 'utf8').trim()) } catch { /* ignore */ }
      return { ok: false, holder: h2 || holder }
    }
  }
}

const claim = claimLock()
if (!claim.ok) {
  if (process.argv.includes('--verbose')) {
    console.log(`[loop ${name}] already running as pid ${claim.holder}, exiting`)
  }
  process.exit(0)
}

let stopped = false
function cleanup() {
  try {
    if (existsSync(lockP) && Number(readFileSync(lockP, 'utf8').trim()) === process.pid) unlinkSync(lockP)
  } catch { /* ignore */ }
}
process.on('SIGINT', () => { stopped = true; cleanup(); process.exit(0) })
process.on('SIGTERM', () => { stopped = true; cleanup(); process.exit(0) })

// --- the loop -------------------------------------------------------------------------
if (process.argv.includes('--once')) {
  const r = spawnSync(cmd[0], cmd.slice(1), { stdio: 'inherit' })
  cleanup()
  process.exit(r.status ?? 0)
}

while (!stopped) {
  const started = Date.now()
  let childStatus = null
  let timedOut = false
  try {
    // 2026-11-08: spawnSync BLOCKS. If the child hangs, this loop hangs with it, the lock
    // stays held, and nothing can take over -- the chain freezes and the heartbeat stops
    // because the heartbeat writer itself is stuck. That is a system that strangles itself.
    // So every round gets a deadline: longer than any honest round, shorter than patience.
    const timeoutMs = Math.min(120000, Math.max(30000, every * 1000 * 4))
    const r = spawnSync(cmd[0], cmd.slice(1), { stdio: 'ignore', timeout: timeoutMs })
    childStatus = r.status
    if (r.error && r.error.code === 'ETIMEDOUT') {
      timedOut = true
      console.error(`[loop ${name}] round exceeded ${timeoutMs}ms, killed the child and continuing`)
    }
  } catch { /* a single failed round must not kill the loop */ }
  const spent = Date.now() - started
  // 2026-11-10 用户：「让他们自己先管，以他们为标准」——节拍由它自己报，不靠外面从总线倒推。
  // 每轮写一份自述：我该多久一次、这次实际多久、有没有超时/失败。中枢只聚合，不再替它判。
  // 2026-11-10 用户：「这不就是转接器吗？它自己转出来之后再转我的信号就行」。
  // 所以不另立数据文件：正常不报（恒定流由脑干吸收），只有迟到/超时/失败才发一条 pace 信号。
  const lateMs = Math.max(0, spent - every * 1000)
  if (cell !== '0' && (lateMs > 0 || timedOut || (childStatus !== null && childStatus !== 0))) {
    try {
      spawnSync(process.execPath, [join(ROOT, 'core', 'bus.mjs'), 'emit', cell, '4', timedOut ? '2' : '1', String(lateMs), `pace:${every}/${spent}/${childStatus}`], { stdio: 'ignore' })
    } catch { /* 上报失败不影响循环 */ }
  }
  const wait = Math.max(1000, every * 1000 - spent)
  // sleep without a busy loop
  const until = Date.now() + wait
  while (Date.now() < until && !stopped) {
    spawnSync(process.execPath, ['-e', `setTimeout(()=>{}, ${Math.min(1000, until - Date.now())})`], { stdio: 'ignore' })
  }
}
cleanup()
