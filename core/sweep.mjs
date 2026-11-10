// sweep.mjs -- the 30-minute housekeeping round, as ONE command (so the launcher needs no nesting).
//
// 2026-11-08: this used to be three separate `& node ...` calls glued together inside
// start-timers.vbs, four levels of quotes deep. It silently failed to start (the other three
// loops came up, sweep did not). A launcher should never depend on quote nesting.
//
// order matters: rotate first (so pulse reads today's live bus, not yesterday's), then pulse
// (reports what is missing), then self (compares the profile against its baseline).
//
// usage: node core/sweep.mjs [--dry]

import { spawnSync } from 'node:child_process'
import { join } from 'node:path'
import { ROOT } from './root.mjs'

const dry = process.argv.includes('--dry')

// 2026-11-10 用户：「让他们自己先管一个纯中枢，自己先管，以他们为标准，然后就上传」——
// 有自己 every 的器官（self/pulse/align/immunity）各自起一条 loop，以自己的节律为准；
// 这里只留链式的那几步（判 → 压 → 轮转 → 大脑 → 思考）。
const steps = [
  ['damage.mjs', 'cheap integrity check first: is the body hurt before we sweep it'],
  ['consolidate.mjs', 'turn new bus lines into events before rotation moves them'],
  ['bus-rotate.mjs', 'rotate yesterday out of the live bus'],
  ['brain.mjs', 'read the newest verdict and rank what deserves attention'],
  ['mind.mjs', 'turn the plan into a conclusion, a move, and a recheck of both'],
]

let failed = 0
for (const [file, why] of steps) {
  const args = [join(ROOT, 'core', file)]
  if (dry) args.push('--dry')
  const r = spawnSync(process.execPath, args, { stdio: 'ignore' })
  if (r.status !== 0) {
    failed++
    console.error(`sweep: ${file} exited ${r.status} (${why})`)
  }
}

if (failed) {
  console.error(`sweep: ${failed}/${steps.length} steps failed`)
  process.exit(1)
}
console.log(`sweep: ${steps.length} steps ok`)
