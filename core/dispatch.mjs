// core/dispatch.mjs -- point-to-point trigger. No mailbox, no medium.
//
// We are not biological: a signal does not need to diffuse. The sender knows the
// receiver, so dispatch starts the receiver directly and passes the signal via env.
//
// usage: node core/dispatch.mjs [--all] [--dry]
//   default: only signals after the cursor
//   --dry: print who would be triggered, start nothing
//
// NOTE (2026-11-08): the work is wrapped in main() and only runs when this file is
// invoked directly. Before this guard, a plain `import('./dispatch.mjs')` -- which
// was meant to be a harmless load check -- actually fired 222 spawns. Loading and
// running must be two different things.

import { readFileSync, writeFileSync, existsSync } from 'node:fs'
import { join } from 'node:path'
import { spawn } from 'node:child_process'
import { fileURLToPath } from 'node:url'

// root comes from core/root.mjs -- do not hardcode the path here
import { ROOT } from './root.mjs'

function main() {
  const BUS = join(ROOT, 'track', 'bus.jsonl')
  const CUR = join(ROOT, 'track', '.dispatch-cursor')

  const reg = JSON.parse(readFileSync(join(ROOT, 'core', 'registry.json'), 'utf8'))
  const cells = reg.cells || {}
  const subs = reg.subs || {}

  if (!existsSync(BUS)) { console.error('bus not found'); return 2 }

  const all = process.argv.includes('--all')
  const dry = process.argv.includes('--dry')
  const lines = readFileSync(BUS, 'utf8').split('\n').filter(Boolean)
  let start = all ? 0 : Number(existsSync(CUR) ? readFileSync(CUR, 'utf8').trim() : 0) || 0
  if (start > lines.length) start = 0

  const fired = []
  for (let i = start; i < lines.length; i++) {
    let r
    try { r = JSON.parse(lines[i]) } catch { continue }
    const targets = subs[String(r.src)] || []
    for (const t of targets) {
      const cell = cells[String(t)]
      if (!cell) continue
      fired.push(`${r.src}->${t}(${cell.id}) state=${r.state}`)
      if (dry) continue
      try {
        const child = spawn('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', join(ROOT, cell.path)], {
          env: { ...process.env, TRIGGER_FROM: String(r.src), TRIGGER_STATE: String(r.state), TRIGGER_VALUE: String(r.value) },
          stdio: 'ignore',
          detached: true,
        })
        child.unref()
      } catch (e) { fired.push('spawn-failed:' + cell.id) }
    }
  }
  if (!dry) writeFileSync(CUR, String(lines.length), 'utf8')
  console.log(JSON.stringify({ scanned: lines.length - start, fired: fired.length, dry, detail: fired.slice(0, 10) }))
  return 0
}

// only run when invoked directly; importing this file must do nothing
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  process.exit(main())
}
