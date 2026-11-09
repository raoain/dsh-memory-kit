// core/human.mjs -- language converter. Keeps the raw JSON, appends one localized line.
//
// The bus stays ASCII-only; localized text is produced here at display time and never written back.
// Language is data: track/locales/<lang>.json -- add a file to add a language, no code change.
//
// usage: node core/human.mjs [n] [--lang zh|en]   (default n=1 latest, lang=zh)

import { readFileSync, existsSync } from 'node:fs'
import { join } from 'node:path'

// root comes from core/root.mjs -- do not hardcode the path here
import { ROOT } from './root.mjs'
const BUS = join(ROOT, 'track', 'bus.jsonl')

const argv = process.argv.slice(2)
const li = argv.indexOf('--lang')
const lang = li >= 0 ? argv[li + 1] : 'zh'
const nArg = argv.find((a, i) => !a.startsWith('--') && i !== li + 1)
const n = Number(nArg) || 1

const locPath = join(ROOT, 'track', 'locales', lang + '.json')
if (!existsSync(locPath)) {
  console.error('no locale: ' + lang)
  process.exit(2)
}
const L = JSON.parse(readFileSync(locPath, 'utf8'))

function sentence(r) {
  const out = []
  out.push(L.src[String(r.src)] || (L.unknownSrc + r.src))
  if (L.kind[String(r.kind)]) out.push(L.kind[String(r.kind)])
  out.push(L.state[String(r.state)] || L.unknownState)
  // 翻译层的词一律来自 locales（2026-11-08：硬编码在代码里就是内嵌翻译，不是并联）
  if (r.rush !== undefined) out.push((L.rushPrefix || 'rush') + r.rush + (L.rush?.[String(r.rush)] ? '' : ''))
  const ev = String(r.evid || '')
  const m = ev.match(/^verify:(\d+)\/(\d+)\/(\d+)\/(\d+)$/)
  if (m) out.push(L.counts.replace('{N0}', m[1]).replace('{N1}', m[2]).replace('{N2}', m[3]).replace('{N3}', m[4]))
  else if (ev) out.push(ev)
  if (Array.isArray(r.counts)) out.push(L.countsRaw.replace('{V}', r.counts.join('/')))
  return out.filter(Boolean).join(' / ')
}

if (!existsSync(BUS)) { console.error(L.noBus); process.exit(2) }
const lines = readFileSync(BUS, 'utf8').split('\n').filter(Boolean).slice(-n)
if (lines.length === 0) { console.error(L.emptyBus); process.exit(2) }
for (const l of lines) {
  let r
  try { r = JSON.parse(l) } catch { console.log(l + '   <- ' + L.parseFail); continue }
  console.log(JSON.stringify(r) + '   <- ' + sentence(r))
}