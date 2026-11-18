// client/server.mjs -- minimal local client for the individual (v0, no model API).
// Serves: GET /            -> client/index.html
//         GET /state       -> read-only snapshot assembled from track/ and core/
//         POST /say {text} -> spawn core/sense.mjs --text ... --from user (the ear), then reply
// Nothing here judges; it only reads files and forwards text to the organ.
import { createServer } from 'node:http'
import { readFileSync, existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { spawnSync } from 'node:child_process'

const here = dirname(fileURLToPath(import.meta.url))
const ROOT = join(here, '..')
const PORT = Number(process.env.CLIENT_PORT || 7788)

const R = (rel) => join(ROOT, rel)
const readJson = (rel, d = null) => { try { return JSON.parse(readFileSync(R(rel), 'utf8')) } catch { return d } }
const tail = (rel, n = 1) => {
  try {
    const lines = readFileSync(R(rel), 'utf8').trim().split(/\r?\n/).filter(Boolean)
    return lines.slice(-n)
  } catch { return [] }
}

function heartbeatAge() {
  // the single source of truth for "is it beating" is the bus: last src=7 record's ts
  try {
    const lines = readFileSync(R('track/bus.jsonl'), 'utf8').trim().split(/\r?\n/)
    for (let i = lines.length - 1; i >= 0; i--) {
      let s; try { s = JSON.parse(lines[i]) } catch { continue }
      if (String(s.src) === '7') return Math.round((Date.now() - s.ts) / 1000)
    }
  } catch { /* no bus */ }
  return null
}

function state() {
  const reg = readJson('core/registry.json', { cells: {} })
  const cells = reg.cells || {}
  const withPath = Object.values(cells).filter((c) => c && c.path).length
  const last = tail('track/bus.jsonl', 1)[0]
  let lastSig = null
  try { lastSig = JSON.parse(last) } catch { /* ignore */ }
  return {
    at: new Date().toISOString(),
    heartbeat_age_s: heartbeatAge(),
    organs_with_path: withPath,
    organs_total: Object.keys(cells).length,
    bus_last: lastSig,
    in_raw_lines: (() => { try { return readFileSync(R('track/in-raw.jsonl'), 'utf8').trim().split(/\r?\n/).filter(Boolean).length } catch { return 0 } })(),
    sense_enabled: !!(cells['11'] && cells['11'].enabled)
  }
}

function say(text) {
  const p = spawnSync(process.execPath, [R('core/sense.mjs'), '--text', text, '--from', 'user'], { encoding: 'utf8' })
  return { code: p.status, out: (p.stdout || '').trim(), err: (p.stderr || '').trim() }
}

const server = createServer((req, res) => {
  const url = req.url || '/'
  const send = (code, body, type = 'application/json; charset=utf-8') => {
    res.writeHead(code, { 'content-type': type, 'cache-control': 'no-store' })
    res.end(body)
  }
  if (req.method === 'GET' && (url === '/' || url.startsWith('/index'))) {
    try { return send(200, readFileSync(join(here, 'index.html'), 'utf8'), 'text/html; charset=utf-8') } catch (e) { return send(500, String(e)) }
  }
  if (req.method === 'GET' && url.startsWith('/state')) return send(200, JSON.stringify(state(), null, 2))
  if (req.method === 'POST' && url.startsWith('/say')) {
    let body = ''
    req.on('data', (c) => { body += c })
    req.on('end', () => {
      let text = ''
      try { text = String(JSON.parse(body || '{}').text || '') } catch { /* ignore */ }
      if (!text.trim()) return send(400, JSON.stringify({ ok: false, error: 'empty text' }))
      const r = say(text)
      send(200, JSON.stringify({ ok: r.code === 0, sense: r }))
    })
    return
  }
  send(404, JSON.stringify({ ok: false, error: 'not found' }))
})

server.listen(PORT, '127.0.0.1', () => {
  console.log(`client v0 on http://127.0.0.1:${PORT}  (root=${ROOT})`)
})
