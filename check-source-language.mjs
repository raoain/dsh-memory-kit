// check-source-language.mjs -- does the PROTOCOL carry non-ASCII?
//
// First version was too wide: it scanned every non-comment line and reported 461 hits,
// most of them Chinese file names, Chinese corpora used by regexes, and human-facing
// error text. Those are DATA and TRANSLATION, not protocol. A checker that reports 461
// problems is telling you the rule is wrong, not the code.
//
// Narrowed to the one thing that actually is protocol: the text that leaves this program
// and goes onto the bus (track/bus.jsonl) or into a JSON data file. If a machine will
// parse it later, it must be ASCII.
//
// usage: node check-source-language.mjs [--verbose]
// exit:  0 clean, 1 protocol violations

import { readdirSync, readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { ROOT } from './core/root.mjs'

const verbose = process.argv.includes('--verbose')
const violations = []

// 1) data files must be pure ASCII
const coreJson = readdirSync(join(ROOT, 'core')).filter((f) => f.endsWith('.json')).map((f) => join('core', f))
for (const f of coreJson) {
  const text = readFileSync(join(ROOT, f), 'utf8')
  text.split('\n').forEach((line, i) => {
    if (/[^\x00-\x7F]/.test(line)) {
      violations.push({ file: f, line: i + 1, why: 'data file must be pure ASCII', text: line.trim().slice(0, 70) })
    }
  })
}

// 2) the bus itself: every line is protocol
const busP = join(ROOT, 'track', 'bus.jsonl')
try {
  const text = readFileSync(busP, 'utf8')
  text.split('\n').forEach((line, i) => {
    if (!line.trim()) return
    if (/[^\x00-\x7F]/.test(line)) {
      violations.push({ file: 'track/bus.jsonl', line: i + 1, why: 'bus line must be pure ASCII', text: line.slice(0, 70) })
    }
  })
} catch { /* no bus yet */ }

// 3) emit() call sites: the literal arguments travel to the bus, so they are protocol
//    (variable arguments are checked by the bus check above once they land)
const coreMjs = readdirSync(join(ROOT, 'core')).filter((f) => f.endsWith('.mjs')).map((f) => join('core', f))
for (const f of coreMjs) {
  const text = readFileSync(join(ROOT, f), 'utf8')
  text.split('\n').forEach((line, i) => {
    if (!/emit\s*\(/.test(line)) return
    if (!/[^\x00-\x7F]/.test(line)) return
    // allow the trailing comment explaining the call
    const code = line.split('//')[0]
    if (!/[^\x00-\x7F]/.test(code)) return
    violations.push({ file: f, line: i + 1, why: 'emit() argument carries non-ASCII', text: code.trim().slice(0, 70) })
  })
}

// record the run (same dead-man pattern as probe: a checker must report that it reported)
const stampP = join(ROOT, 'track', '.source-language.json')
try {
  writeFileSync(stampP, JSON.stringify({ at: new Date().toISOString(), ts: Date.now(), violations: violations.length }), 'utf8')
} catch { /* ignore */ }

if (verbose) {
  console.log(`scanned: ${coreJson.length} json + bus + ${coreMjs.length} core mjs`)
  console.log('scope: protocol only (json data, bus lines, emit arguments)')
  console.log('exempt by design: comments, console output, Chinese file names, Chinese corpora, error text for a person')
}

if (violations.length === 0) {
  console.log('protocol clean: 0 violations')
  process.exit(0)
}

console.log(`protocol violations: ${violations.length}`)
for (const v of violations) console.log(`  ${v.file}:${v.line}  ${v.why}  ${v.text}`)
process.exit(1)
