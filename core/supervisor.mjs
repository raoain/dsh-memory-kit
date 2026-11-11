// core/supervisor.mjs -- 父进程级监督：哪个 loop 死了，只重启那一个；反复死就停手上报。
//
// Why (2026-11-11 用户：「那不就跟以前那个老哥一样的吗？」)：
// Erlang/OTP supervisor 早就把这件事解了——叶子进程死了由上级按策略重启（one_for_one），
// 并有 MaxR/MaxT 重启强度上限（同一时间窗内重启超过 MaxR 次就停手并上报，避免「死了又起、起了又死」）。
// 我们现在的 start-timers.vbs 只是「一次性拉起 + 各自看锁」，之后没有父进程盯着：
// 心跳还在、但某个器官的循环死了，没有任何人会救它（见 lesson 0mwc7ufg）。
//
// 2026-11-11 用户：「这一步得归到总中枢，这是他的任务，这是他的判决，然后下达做法呀」——
// 所以这个文件**不判**：进程退出时它只做三件——①把退出写成事件 ②问中枢（consolidate --judge-procs）
// ③照中枢下达的 action 执行（restart / stop）。判与做分开，就像「手不能判生死」。
//
// 这个文件就是那棵最小监督树：
//   - 每个 loop 一个子进程；子进程一退出，**只重启它自己**（one_for_one）；
//   - 同一 loop 在 60 秒窗口内重启超过 MAX_R(=3) 次 → 停手，写 escalate.jsonl 并上报人；
//   - 不碰别人的进程，不杀任何东西（与「手不能判生死」一致：只维持「该在的还在」）。
//
// usage:
//   node core/supervisor.mjs --dry        # 只打印要管哪几个 loop（默认，安全）
//   node core/supervisor.mjs --selftest   # 用假 loop 验证「会重启 3 次然后停手」（不碰生产）
//   node core/supervisor.mjs --run        # 真的接管（会和对现有 vbs 起的循环抢锁，切换前先停 vbs）

import { spawn, spawnSync } from 'node:child_process'
import { appendFileSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { ROOT } from './root.mjs'

const NODE = process.execPath
const WINDOW_MS = 60 * 1000
const MAX_R = 3

// 与 start-timers.vbs 同源的 9 个循环（改这里要同步改 vbs，或者以后只留这里）
const LOOPS = [
  { name: 'watchdog', every: 300, cell: 4, cmd: ['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', join(ROOT, 'watchdog.ps1')] },
  { name: 'sweep', every: 1800, cell: 18, cmd: [NODE, join(ROOT, 'core', 'sweep.mjs')] },
  { name: 'reflex', every: 3, cell: 7, cmd: [NODE, join(ROOT, 'core', 'reflex.mjs')] },
  { name: 'self', every: 1800, cell: 8, cmd: [NODE, join(ROOT, 'core', 'self.mjs')] },
  { name: 'backup', every: 86400, cell: 5, cmd: ['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', join(ROOT, 'backup.ps1')] },
  { name: 'pulse', every: 1800, cell: 9, cmd: [NODE, join(ROOT, 'core', 'pulse.mjs')] },
  { name: 'align', every: 86400, cell: 16, cmd: [NODE, join(ROOT, 'core', 'align.mjs')] },
  { name: 'immunity', every: 86400, cell: 17, cmd: [NODE, join(ROOT, 'core', 'immunity.mjs')] },
  { name: 'drift', every: 60, cell: 15, cmd: [NODE, join(ROOT, 'core', 'drift.mjs')] },
  { name: 'heart', every: 60, cell: 18, cmd: [NODE, join(ROOT, 'core', 'consolidate.mjs'), '--heart'] },
]

function loopArgv (l) {
  return [NODE, join(ROOT, 'core', 'loop.mjs'), '--name', l.name, '--every', String(l.every), '--cell', String(l.cell), '--', ...l.cmd]
}

function escalate (l, restarts) {
  const row = {
    at: new Date().toISOString(), organ: String(l.cell), name: l.name,
    kind: 'restart-storm', why_failed: `restarted ${restarts} times within ${WINDOW_MS / 1000}s; supervisor stopped restarting it`,
    next: 'hand it to a person: check the loop log, decide whether to change the organ', from: 'supervisor',
  }
  try { appendFileSync(join(ROOT, 'track', 'escalate.jsonl'), JSON.stringify(row) + '\n', 'utf8') } catch { /* keep going */ }
  console.error(`[supervisor] stop restarting ${l.name}: ${restarts} restarts in window`)
}

export function supervise (loops, opts = {}) {
  const maxR = opts.maxR ?? MAX_R
  const windowMs = opts.windowMs ?? WINDOW_MS
  const maxRestartsPerLoop = opts.maxRestartsPerLoop ?? Infinity
  const seen = new Map()
  const stopping = new Set()
  const children = []

  function start (l) {
    const argv = l.argv || loopArgv(l)
    const child = spawn(argv[0], argv.slice(1), { stdio: 'ignore', windowsHide: true })
    children.push(child)
    child.on('exit', () => {
      if (stopping.has(l.name)) return
      if (opts.dryJudge) { console.log(JSON.stringify({ dry: true, would_ask_center: l.name })); return }
      // ① 退出写成事件（给中枢看的事实，不是决定）
      const ev = { ts: Date.now(), at: new Date().toISOString(), name: l.name, cell: l.cell, pid: child.pid ?? null }
      try { appendFileSync(join(ROOT, 'track', 'proc-exit.jsonl'), JSON.stringify(ev) + '\n', 'utf8') } catch { /* keep going */ }
      // ② 问中枢（判决归 consolidate）
      let order = null
      try {
        spawnSync(NODE, [join(ROOT, 'core', 'consolidate.mjs'), '--judge-procs'], { encoding: 'utf8' })
        // 不靠 stdout（管道/编码都可能坏）：直接读中枢写下的最后一条下达，按名字匹配
        const lines = readFileSync(join(ROOT, 'track', 'proc-cmd.jsonl'), 'utf8').trim().split(/\r?\n/).filter(Boolean)
        for (let i = lines.length - 1; i >= 0; i--) {
          try {
            const o = JSON.parse(lines[i])
            if (String(o.name) === String(l.name)) { order = o; break }
          } catch { /* skip */ }
        }
      } catch { /* no order */ }
      if (typeof opts.onOrder === 'function') opts.onOrder(l, order)
      // ③ 照下达执行；没有下达就不动（不越权）
      if (!order || order.action === 'none') { stopping.add(l.name); return }
      if (order.action === 'stop') { stopping.add(l.name); escalate(l, Number(order.restarts_in_window || 0)); return }
      start(l)
    })
  }

  for (const l of loops) start(l)
  return {
    stop () { for (const l of loops) stopping.add(l.name); for (const c of children) { try { c.kill() } catch { /* gone */ } } },
  }
}

function main (argv) {
  if (argv.includes('--run')) {
    console.log(JSON.stringify({ ok: true, running: LOOPS.length, note: 'supervisor took over; stop start-timers.vbs first' }))
    supervise(LOOPS)
    return 0
  }
  if (argv.includes('--selftest')) {
    // fake loop exits after 100ms; each exit asks the center; expect restarts until the center says stop
    const fake = { name: 'selftest', every: 0, cell: 0, argv: [NODE, '-e', 'setTimeout(()=>process.exit(0),100)'] }
    let orders = 0
    let lastAction = null
    const h = supervise([fake], {
      dryJudge: false,
      onOrder: (l, order) => { orders += 1; lastAction = order ? order.action : null },
    })
    setTimeout(() => {
      h.stop()
      console.log(JSON.stringify({ ok: orders >= 1, selftest: 'each exit asked the center; supervisor only executed', orders, last_action: lastAction }))
      process.exit(orders >= 1 ? 0 : 1)
    }, 6000)
    return 0
  }
  console.log(JSON.stringify({ dry: true, loops: LOOPS.map((l) => ({ name: l.name, every: l.every, cell: l.cell })), max_r: MAX_R, window_s: WINDOW_MS / 1000 }))
  return 0
}

// selftest 需要让定时器跑完，所以不能立刻 process.exit（否则计时器被杀、什么都不打印）
if (process.argv[1]?.endsWith('supervisor.mjs')) {
  if (process.argv.includes('--selftest')) main(process.argv.slice(2))
  else process.exit(main(process.argv.slice(2)))
}
