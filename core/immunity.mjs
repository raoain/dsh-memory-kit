// immunity.mjs -- organ 17: the immunity register check (does the enforcement still exist, and does it hold?).
//
// Why: a rule written only in docs is not immunity -- BOM was written into docs three times and
// still came back. A rule counts here only when a machine check enforces it. This script reads
// core/immunity.json and does two things per entry:
//   1. enforcement still exists: the named file still contains the named literal (someone may
//      have deleted the checker while the rule stayed "covered" in the table)
//   2. the live check still passes right now (a checker that exists but reports green on a
//      broken system is worse than no checker)
// It never repairs anything; it writes track/免疫表.md and reports a signal.
//
// usage:
//   node core/immunity.mjs          check + write the table
//   node core/immunity.mjs --quiet  only print the summary line

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, existsSync, readdirSync, statSync } from 'node:fs'
import { join } from 'node:path'
import { ROOT } from './root.mjs'
import { emit } from './bus.mjs'
import { matches } from './match.mjs'

// 翻译层：中文只放在 core/locales/zh.json，核心代码只认 key（同 spec.source_language 的规矩）
const ZH = JSON.parse(readFileSync(new URL('./locales/zh.json', import.meta.url), 'utf8'))
function zh(key, ...args) {
  const t = ZH[key] || key
  return String(t).replace(/\{(\d+)\}/g, (_m, idx) => (args[Number(idx)] === undefined ? '' : String(args[Number(idx)])))
}

const SELF = '17'
// 取原文、不做 {n} 替换：正则里本身就带 {4} 这种量词，走 zh() 会被当成占位符吃掉
function zhRaw(key) { return String(ZH[key] || '') }
const REG = JSON.parse(readFileSync(join(ROOT, 'core', 'immunity.json'), 'utf8'))
const SPEC = JSON.parse(readFileSync(join(ROOT, 'core', 'spec.json'), 'utf8'))
const quiet = process.argv.includes('--quiet')

const ROOT_LITERAL = 'F:' + '\\' + 'Tools' + '\\' + 'coo-day1' // 拼出来：写全了本文件会被自己判违规
const ps1 = readdirSync(ROOT).filter((f) => f.endsWith('.ps1'))
const mjs = readdirSync(ROOT).filter((f) => f.endsWith('.mjs'))
const coreMjs = existsSync(join(ROOT, 'core')) ? readdirSync(join(ROOT, 'core')).filter((f) => f.endsWith('.mjs')).map((f) => join('core', f)) : []
const allMjs = [...mjs, ...coreMjs]

function readText(rel) {
  const p = join(ROOT, rel)
  return existsSync(p) ? readFileSync(p, 'utf8') : null
}

function bomCount(abs) {
  const buf = readFileSync(abs)
  let n = 0
  while (buf.length >= 3 * (n + 1) && buf[3 * n] === 0xef && buf[3 * n + 1] === 0xbb && buf[3 * n + 2] === 0xbf) n++
  return n
}

// 2026-11-09: 规则表从来没有被任何检查器读过 —— 一条永远匹配不上的规则就是静默失效，
// 而它看起来和zh('lite.37')完全一样。用规矩自己的匹配函数（core/match.mjs，唯一一份）
// 去问：过去这些信号里，每条规则有没有一条能配上。配上过 = 至少它活着。
function recentSignals() {
  const out = []
  const files = ['track/bus.jsonl', 'track/events.jsonl']
  const arch = join(ROOT, 'track', 'archive')
  if (existsSync(arch)) for (const f of readdirSync(arch).filter((x) => /^bus-\d{8}\.jsonl$/.test(x))) files.push(join('track', 'archive', f))
  for (const rel of files) {
    const t = readText(rel) || ''
    for (const line of t.split('\n')) {
      if (!line.trim()) continue
      try { out.push(JSON.parse(line)) } catch { /* torn line */ }
    }
  }
  return out
}

const CHECKS = {
  // 2026-11-09 用户定的免疫定义：直接识别zh('lite.38')。标准里有、免疫表里没有 → 失败。
  // 这样加第 6 条契约的人不必记得来登记，表会自己点名。
  'standards-covered': () => {
    const contract = (SPEC.tools && SPEC.tools.contract) || {}
    const covered = new Set(
      REG.entries.map((e) => (e.enforced_by && e.enforced_by.pattern) || '').filter((p) => p.startsWith('@contract ')).map((p) => p.slice('@contract '.length).trim()),
    )
    const missing = Object.keys(contract).filter((k) => !covered.has(k))
    return { ok: missing.length === 0, detail: missing.length ? zh('imm.1', missing.join(',')) : zh('imm.2', Object.keys(contract).length) }
  },
  // 2026-11-09 用户：「全定好了，全交给免疫这个疯狗去报错就行」——
  // 所以 spec 的**每一节**都必须有免疫条目认领（条目里写 covers: ['signal', ...]）。
  // 以后有人在 spec 里加一节却没加检查，这条当场吠。
  'spec-sections-covered': () => {
    const sections = Object.keys(SPEC).filter((k) => !['version'].includes(k))
    const covered = new Set()
    for (const e of REG.entries) for (const c of (e.covers || [])) covered.add(c)
    const missing = sections.filter((k) => !covered.has(k))
    return {
      ok: missing.length === 0,
      detail: missing.length ? zh('imm.sections.missing', missing.join(','), sections.length) : zh('imm.sections.ok', sections.length),
    }
  },
  // 2026-11-09 用户问：「keywords 有时是字符串不是数组，你没给他上新标准吗？它的读取也不是新标准吗？」
  // 对——所以形状写进了 spec.records，这里查它：读的字段类型必须和协议一致，不一致就点名。
  'record-shape': () => {
    // 2026-11-09 用户：「按新标准和那些脚本的玩意儿写，不然统一干嘛」——所以标准覆盖全部数据文件，不只 memories。
    // 声明写的是zh('lite.39')：类型按首词判（number/string/array/object/boolean），带 |null 的允许 null。
    const ALL = (SPEC.records && Object.entries(SPEC.records)) || []
    const decls = ALL.filter(([k]) => k !== 'note')
    const bad = []
    let checked = 0
    const kindOf = (v) => Array.isArray(v) ? 'array' : (v === null ? 'null' : typeof v)
    const wantOk = (want, v) => {
      const w = String(want).toLowerCase()
      const k = kindOf(v)
      if (k === 'null') return w.includes('null')
      if (w.startsWith('number')) return k === 'number'
      if (w.startsWith('string')) return k === 'string'
      if (w.startsWith('array')) return k === 'array'
      if (w.startsWith('object')) return k === 'object'
      if (w.startsWith('boolean')) return k === 'boolean'
      return true
    }
    for (const [key, d] of decls) {
      const raw = readText(d.file)
      if (!raw) continue
      const objs = d.one_object ? (() => { try { return [JSON.parse(raw)] } catch { return [{ __err: 1 }] } })()
        : String(raw).split('\n').filter((l) => l.trim()).map((l) => { try { return JSON.parse(l) } catch { return { __err: 1 } } })
      for (const o of objs) {
        checked++
        if (o.__err) { bad.push(`${key}: unparsable entry`); continue }
        for (const [f, want] of Object.entries(d.fields || {})) {
          if (!(f in o)) { bad.push(`${key}: missing ${f}`); continue }
          if (!wantOk(want, o[f])) bad.push(`${key}.${f}: ${kindOf(o[f])} but spec says ${want}`)
        }
      }
    }
    return { ok: bad.length === 0, detail: bad.length ? zh('imm.3', bad.length, checked, bad.slice(0, 3).join('; ')) : zh('imm.4', checked, decls.length) }
  },
  // 2026-11-09 用户：「核心代码不许有中文或别的鬼东西」——注释可中文（不参与解析），
  // 但**字符串里出现非 ASCII** 就是血管里进了异物，当场点名（翻译层在 core/locales/zh.json）。
  'core-ascii-strings': () => {
    const files = readdirSync(join(ROOT, 'core')).filter((f) => f.endsWith('.mjs'))
    const bad = []
    for (const f of files) {
      const lines = String(readText('core/' + f) || '').split('\n')
      lines.forEach((line, i) => {
        const code = line.replace(/\r$/, '').replace(/\/\/.*$/, '')
        if (!/['"`][^'"`]*[^\x00-\x7F][^'"`]*['"`]/.test(code)) return
        bad.push(`${f}:${i + 1}`)
      })
    }
    return { ok: bad.length === 0, detail: bad.length ? zh('imm.ascii.bad', bad.length, bad.slice(0, 5).join(', ')) : zh('imm.ascii.ok', files.length) }
  },
  // 2026-11-09 用户：「把这些移交给免疫」——数据侧的 ASCII 也归这里，
  // verify 不再自己扫一遍，改成问免疫要结论（verify 管结构，免疫管标准）。
  'core-data-ascii': () => {
    const files = ['core/spec.json', 'core/registry.json', 'core/rules.json', 'core/immunity.json', 'track/bus.jsonl']
    const bad = []
    for (const f of files) {
      const t = readText(f)
      if (!t) continue
      t.split(/\r?\n/).forEach((line, i) => {
        if (/[^\x00-\x7F]/.test(line)) bad.push(`${f}:${i + 1}`)
      })
    }
    return { ok: bad.length === 0, detail: bad.length ? zh('imm.data.bad', bad.length, bad.slice(0, 3).join(' ')) : zh('imm.data.ok', files.length) }
  },
  // 2026-11-09 用户：把标准搬齐全，每条都走同一套三步（spec 声明 → 免疫条目 → verify 取结论）。
  // 第一批：核心层大小（上限与节数都从 spec.pages.core 读，不在检查器里写死）。
  // 2026-11-09 用户：「垃圾场加一下吧，以后也一样的，他自己删文件先堆那里多了再删吧」
  'trash-size': () => {
    const cfg = (SPEC.reminders && SPEC.reminders.trash) || {}
    const dir = join(ROOT, cfg.dir || 'trash')
    if (!existsSync(dir)) return { ok: true, detail: zh('imm.trash.none') }
    let files = 0
    let bytes = 0
    const walk = (d) => {
      for (const e of readdirSync(d, { withFileTypes: true })) {
        const p = join(d, e.name)
        if (e.isDirectory()) { walk(p); continue }
        if (e.name.endsWith('.from')) continue
        files += 1
        try { bytes += statSync(p).size } catch { /* ignore */ }
      }
    }
    walk(dir)
    const mb = bytes / (1024 * 1024)
    const maxMb = Number(cfg.max_size_mb || 200)
    return { ok: mb <= maxMb, level: mb > maxMb ? 1 : 0, detail: zh('imm.trash.size', files, mb.toFixed(1), maxMb) }
  },
  // 2026-11-09 A 类活体第五批（用户：「每天必须更新且频繁的活的东西要加上」）：根定义 / 定时器 / 自我集
  'roots-unique': () => {
    const cfg = (SPEC.liveness && SPEC.liveness.roots) || {}
    const checker = join(ROOT, cfg.checker || 'check-naming.mjs')
    if (!existsSync(checker)) return { ok: false, detail: zh('imm.roots.nochecker') }
    let out = ''
    try { out = execFileSync('node', [checker], { cwd: ROOT, encoding: 'utf8' }) } catch (err) { out = String((err && err.stdout) || '') }
    let obj = null
    try { obj = JSON.parse(out) } catch { obj = null }
    if (!obj) return { ok: false, detail: zh('imm.roots.unreadable') }
    const defs = Number(
      (obj.definitions && obj.definitions.root && obj.definitions.root.definitions) !== undefined
        ? obj.definitions.root.definitions
        : (obj.rootDefs !== undefined ? obj.rootDefs : 0),
    )
    const max = Number(cfg.max_defs || 1)
    return { ok: defs <= max, detail: zh('imm.roots.n', defs, max) }
  },
  'timers-present': () => {
    const cfg = (SPEC.liveness && SPEC.liveness.timers) || {}
    const need = cfg.files || []
    const lost = need.filter((f) => !existsSync(join(ROOT, f)))
    return { ok: lost.length === 0, detail: lost.length ? zh('imm.timers.lost', lost.join(', ')) : zh('imm.timers.ok', need.length) }
  },
  'self-set': () => {
    const cfg = (SPEC.liveness && SPEC.liveness.self_set) || {}
    const f = join(ROOT, cfg.file || 'track/baseline.json')
    if (!existsSync(f)) return { ok: false, detail: zh('imm.selfset.none') }
    let o = null
    try { o = JSON.parse(readFileSync(f, 'utf8')) } catch { o = null }
    if (!o || !o.snapAt) return { ok: false, detail: zh('imm.selfset.bad') }
    const days = (Date.now() - new Date(o.snapAt).getTime()) / 86400000
    const max = Number(cfg.max_age_days || 8)
    // 偏离多少也一并判。只认 SIG 机器码（2026-11-09 收掉最后一处解析人话）：
    // SIG {"state":N,"counts":[偏离项数, 指标数]}；读不到才退回 null，不去猜正文。
    let drift = null
    try {
      const out = execFileSync('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', join(ROOT, cfg.snapshot_cmd || 'baseline.ps1')], { cwd: ROOT, encoding: 'utf8' })
      const sig = String(out).split(/\r?\n/).filter((l) => l.trim().startsWith('SIG ')).pop()
      if (sig) {
        const parsed = JSON.parse(sig.slice(4))
        if (Array.isArray(parsed.counts)) drift = Number(parsed.counts[0])
      }
    } catch { drift = null }
    const maxDrift = Number(cfg.max_drift || 5)
    const bad = days > max || (drift !== null && drift > maxDrift)
    return { ok: !bad, level: bad ? 1 : 0, detail: zh('imm.selfset.age', days.toFixed(1), max, drift === null ? '?' : drift, maxDrift) }
  },
  // 2026-11-09 用户：「先给『能查不许猜』和『同根因升级』各配一条可跑的检查，有强制检查比写了强」
  // ① 能查不许猜 → 可执行的形态就是「说完成必须带可核证据」：工作层条目里有完成词，就必须带 证: 且证能打开
  'claims-evidence': () => {
    const cfg = (SPEC.rules && SPEC.rules.evidence) || {}
    const dir = (cfg.page && cfg.page.dir) || 'notebook'
    const prefix = (cfg.page && cfg.page.prefix) || '1-'
    const names = existsSync(join(ROOT, dir)) ? readdirSync(join(ROOT, dir)).filter((f) => f.startsWith(prefix) && f.endsWith('.md')) : []
    if (!names.length) return { ok: false, detail: zh('imm.ev.nopage', prefix) }
    const claimWords = zhRaw(cfg.claim_key).split('|').filter(Boolean)
    const evidRe = /证[:：]/
    // 只判今天的；历史欠账只报数（同 verify 旧口径：入口拦截 + 对象分开，否则「修一条多一条债」）
    const today = new Date().toISOString().slice(0, 10)
    const badToday = []
    let debt = 0
    for (const line of readFileSync(join(ROOT, dir, names[0]), 'utf8').split(/\r?\n/)) {
      if (!/^- \[/.test(line)) continue
      if (!claimWords.some((w) => line.includes(w))) continue
      const day = (line.match(/^- \[(\d{4}-\d{2}-\d{2})/) || [])[1] || ''
      let weak = false
      if (!evidRe.test(line)) weak = true
      else {
        const evid = line.split(evidRe)[1] || ''
        const hasPath = (evid.match(/[A-Za-z0-9_\-\\/\.]+\.(md|ps1|jsonl|json|mjs|txt)/g) || []).some((p) => existsSync(join(ROOT, p)))
        const hasCount = /\d+\s*(items|lines|B|ms)/.test(evid) || /OK |项：|\d+\s*项/.test(evid)
        if (!hasPath && !hasCount) weak = true
      }
      if (!weak) continue
      if (day === today) badToday.push(zh('imm.ev.weak'))
      else debt++
    }
    const bad = badToday
    return { ok: bad.length === 0, detail: bad.length ? zh('imm.ev.bad', bad.length) : zh('imm.ev.ok', debt) }
  },
  // ② 同根因第二次 → 升级：可执行的形态就是「同一项连续失败到阈值就必须处理」，读连击表
  'streak-escalation': () => {
    const cfg = (SPEC.rules && SPEC.rules.escalation) || {}
    const file = join(ROOT, cfg.streak_file || 'track/warn-streak.json')
    if (!existsSync(file)) return { ok: true, detail: zh('imm.streak.none') }
    let data = {}
    try { data = JSON.parse(readFileSync(file, 'utf8') || '{}') } catch { data = {} }
    const limit = Number(cfg.streak || 3)
    const hot = Object.entries(data).filter(([, v]) => Number(v && v.count !== undefined ? v.count : v) >= limit)
    return { ok: hot.length === 0, detail: hot.length ? zh('imm.streak.hot', hot.map(([k]) => k).join(','), limit) : zh('imm.streak.ok', limit) }
  },
  // 2026-11-09 第四批：提醒类（规则在 spec.reminders，判定在这里；它们不会「失败」，只是提示旧了）
  'wake-fresh': () => {
    const cfg = (SPEC.reminders && SPEC.reminders.wake_mark) || {}
    const p = join(ROOT, cfg.file || 'track/wake-last.txt')
    if (!existsSync(p)) return { ok: false, detail: zh('imm.wake.missing') }
    const raw = String(readFileSync(p, 'utf8')).trim()
    const m = raw.match(/^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})/)
    if (!m) return { ok: false, detail: zh('imm.wake.bad', raw.slice(0, 30)) }
    const ageH = (Date.now() - new Date(m[1].replace(' ', 'T') + 'Z').getTime()) / 3600000
    const maxH = Number(cfg.max_age_h || 24)
    const wornH = Number(cfg.worn_after_h || 12)
    const level = ageH > maxH ? 2 : ageH > wornH ? 1 : 0
    return { ok: level === 0, level, detail: zh('imm.wake.age', ageH.toFixed(1), maxH) }
  },
  'snapshot-fresh': () => {
    const cfg = (SPEC.reminders && SPEC.reminders.snapshot) || {}
    const dir = join(ROOT, cfg.dir || 'track/own')
    const ext = cfg.ext || '.json'
    const names = existsSync(dir) ? readdirSync(dir).filter((f) => f.endsWith(ext)) : []
    if (!names.length) return { ok: false, detail: zh('imm.snap.none') }
    let newest = 0
    for (const n of names) {
      const st = statSync(join(dir, n))
      if (st.mtimeMs > newest) newest = st.mtimeMs
    }
    const ageH = (Date.now() - newest) / 3600000
    const maxH = Number(cfg.max_age_h || 30)
    return { ok: ageH <= maxH, level: ageH > maxH ? 1 : 0, detail: zh('imm.snap.age', ageH.toFixed(1), maxH) }
  },
  // 2026-11-09 第三批搬迁：流水时间戳（格式与非递减在 spec.pages.timeline，正则里的中文前缀放 locales）
  'timeline-order': () => {
    const cfg = (SPEC.pages && SPEC.pages.timeline) || {}
    const files = cfg.files || []
    if (!files.length) return { ok: false, detail: zh('imm.time.nofiles') }
    const bad = []
    for (const f of files) {
      const dir = f.dir || 'notebook'
      const prefix = f.prefix || ''
      const dirAbs = join(ROOT, dir)
      const names = existsSync(dirAbs) ? readdirSync(dirAbs).filter((n) => n.startsWith(prefix) && n.endsWith('.md')) : []
      if (!names.length) { bad.push(zh('imm.time.missing', f.name || prefix)); continue }
      const t = readFileSync(join(dirAbs, names[0]), 'utf8')
      const pat = new RegExp(zhRaw(f.pattern_key), 'gm')
      const stamps = [...t.matchAll(pat)].map((m) => m[1])
      if (!stamps.length) { bad.push(zh('imm.time.nomatch', f.name || prefix)); continue }
      let prev = null
      let backward = null
      for (const s of stamps) {
        const d = new Date(s.replace(' ', 'T') + ':00Z')
        if (Number.isNaN(d.getTime())) { bad.push(zh('imm.time.invalid', f.name, s)); break }
        if (prev && d < prev) { backward = `${prev.toISOString().slice(0, 16)} -> ${s}`; break }
        prev = d
      }
      if (backward) bad.push(zh('imm.time.backward', f.name, backward))
    }
    return { ok: bad.length === 0, detail: bad.length ? bad.join('; ') : zh('imm.time.ok', files.length) }
  },
  // 2026-11-09 第二批搬迁：墓碑（规则在 spec.pages.tombstone，判定在这里，verify 只取结论）
  'tombstone': () => {
    const cfg = (SPEC.pages && SPEC.pages.tombstone) || {}
    const dir = cfg.dir || 'notebook'
    const prefix = cfg.prefix || '3-'
    const files = existsSync(join(ROOT, dir)) ? readdirSync(join(ROOT, dir)).filter((f) => f.startsWith(prefix) && f.endsWith('.md')) : []
    if (!files.length) return { ok: false, detail: zh('imm.tomb.missing', prefix) }
    const t = readFileSync(join(ROOT, dir, files[0]), 'utf8')
    const head = t.split('## ')[0] || t
    const entries = (t.match(/^### /gm) || []).length
    const empty = (t.match(/^### .+\r?\n\s*\r?\n(?=###|$)/gm) || []).length
    const hasWhy = /why|because/i.test(t) || t.includes(zh('imm.tomb.marker.why'))
    const hasNow = /now follows|now rule/i.test(t) || t.includes(zh('imm.tomb.marker.now'))
    const bad = []
    if (cfg.require_reason && empty > 0) bad.push(zh('imm.tomb.empty', empty))
    if (cfg.require_now_rule && !(hasWhy && hasNow)) bad.push(zh('imm.tomb.format'))
    return { ok: bad.length === 0, detail: bad.length ? bad.join('; ') : zh('imm.tomb.ok', files[0], entries) }
  },
  'core-page': () => {
    const cfg = (SPEC.pages && SPEC.pages.core) || {}
    const dir = cfg.dir || 'notebook'
    const prefix = cfg.prefix || '0-'
    const maxBytes = Number(cfg.max_bytes || 2048)
    const minSections = Number(cfg.min_sections || 4)
    const files = readdirSync(join(ROOT, dir)).filter((f) => f.startsWith(prefix) && f.endsWith('.md'))
    if (!files.length) return { ok: false, detail: zh('imm.page.missing', prefix) }
    const f = join(ROOT, dir, files[0])
    const t = readFileSync(f, 'utf8')
    const bytes = Buffer.byteLength(t, 'utf8')
    const sections = (t.match(/^## /gm) || []).length
    const bad = []
    if (bytes > maxBytes) bad.push(zh('imm.page.size', bytes, maxBytes))
    if (sections < minSections) bad.push(zh('imm.page.sections', sections, minSections))
    return { ok: bad.length === 0, detail: bad.length ? bad.join('; ') : zh('imm.page.ok', files[0], bytes, sections) }
  },
  // 2026-11-09 用户：「这种玩意还是接入会好一点，是真正的免疫系统在提醒，而且钉的话很频繁本来就」
  // 所以「每个 .ps1 都要有引脚」这条也归免疫判，verify 不再自己扫目录。
  'pins-cover-scripts': () => {
    let pins = null
    try { pins = JSON.parse(readText('state.json') || 'null') } catch { pins = null }
    if (!pins || !pins.pins) return { ok: false, detail: zh('imm.pins.nostate') }
    const names = new Set(Object.keys(pins.pins).map((k) => String(k).replace(/^script\./, '')))
    const scripts = readdirSync(ROOT).filter((f) => f.endsWith('.ps1'))
    const unpinned = scripts.filter((f) => !names.has(f))
    return { ok: unpinned.length === 0, detail: unpinned.length ? zh('imm.pins.bad', unpinned.length, unpinned.slice(0, 5).join(', ')) : zh('imm.pins.ok', scripts.length) }
  },
  // 2026-11-09 用户：「就把这部分加到脚本，那部分不就行了吗？免疫的，只是合并加新的而已」
  // lint 的规则写进 spec.tools.lint，免疫只负责给结论：跑 lint.ps1 -Quiet，读「N 处问题」。
  'ps1-lint': () => {
    const rules = (SPEC.tools && SPEC.tools.lint && SPEC.tools.lint.rules) || {}
    const script = (SPEC.tools && SPEC.tools.lint && SPEC.tools.lint.implemented_by) || 'lint.ps1'
    const p = join(ROOT, script)
    if (!existsSync(p)) return { ok: false, detail: zh('imm.lint.noscript', script) }
    let out = ''
    try {
      out = execFileSync('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', p, '-Quiet'], { cwd: ROOT, encoding: 'utf8' })
    } catch (err) { out = String((err && err.stdout) || '') }
    // 只认那一行机器码 SIG {"state":N,"counts":[files,problems]}——人话输出（Write-Host）不进 stdout
    const sig = String(out).split(/\r?\n/).filter((l) => l.trim().startsWith('SIG ')).pop()
    let n = null
    let pieces = 0
    if (sig) {
      try {
        const o = JSON.parse(sig.slice(4))
        if (Array.isArray(o.counts)) { pieces = Number(o.counts[0]) || 0; n = Number(o.counts[1]) || 0 }
      } catch { n = null }
    }
    return { ok: n === 0, detail: n === null ? zh('imm.lint.unreadable') : zh('imm.lint.n', n, pieces || Object.keys(rules).length) }
  },
  // 2026-11-10 用户：「自己他妈自己转，怎么延误都不知道，根本就没适配我们的系统」——
  // 有节律的器官必须各自带一个 loop 且带 --cell（异常时才知道是谁发的 pace 信号）；
  // 或者在 sweep 的步骤表里被链式驱动。两者都没有 = 没人管它的节律 = 没适配。
  'organ-pace-wired': () => {
    const vbs = readText('start-timers.vbs') || ''
    const sweepSrc = readText('core/sweep.mjs') || ''
    const looped = new Set([...vbs.matchAll(/--name (\w+) --every \d+ --cell \d+/g)].map((m) => m[1]))
    const cells = Object.entries(REG.cells || {}).filter(([, c]) => c.path && Number(c.every || 0) > 0)
    const missing = cells.filter(([, c]) => !looped.has(String(c.id)) && !sweepSrc.includes(String(c.id) + '.mjs')).map(([k, c]) => k + ':' + c.id)
    return { ok: missing.length === 0, detail: missing.length ? zh('imm.pace.missing', missing.join(', '), cells.length) : zh('imm.pace.ok', cells.length) }
  },
  'rules-coverable': () => {    const R = JSON.parse(readText('core/rules.json') || '{"rules":[]}')
    const sigs = recentSignals()
    const dead = []
    for (const r of R.rules || []) {
      const hit = sigs.some((s) => { try { return matches(SPEC, r.when, s) } catch { return false } })
      if (!hit) dead.push(r.id)
    }
    return { ok: dead.length === 0, detail: dead.length ? zh('imm.5', dead.join(',')) : zh('imm.6', (R.rules || []).length) }
  },
  'ps1-bom': () => {
    const bad = ps1.filter((f) => bomCount(join(ROOT, f)) !== 1)
    return { ok: bad.length === 0, detail: bad.length ? zh('imm.7', bad.slice(0, 3).join(',')) : zh('imm.8', ps1.length) }
  },
  'ps1-param': () => {
    const bad = ps1.filter((f) => f !== '_root.ps1' && !/param\s*\(/.test(readText(f) || ''))
    return { ok: bad.length === 0, detail: bad.length ? zh('imm.9', bad.slice(0, 3).join(',')) : zh('lit.1') }
  },
  'ps1-exit': () => {
    const bad = []
    for (const f of ps1) {
      const badC = [...(readText(f) || '').matchAll(/exit\s+(-?\d+)/g)].map((m) => Number(m[1])).filter((v) => ![0, 1, 2, 3].includes(v))
      if (badC.length) bad.push(`${f}:${[...new Set(badC)].join('/')}`)
    }
    return { ok: bad.length === 0, detail: bad.length ? bad.slice(0, 3).join(' ') : zh('lit.2') }
  },
  'root-hardcode': () => {
    // 只算代码行：注释里的用法示例（F:\Tools\coo-day1\start.ps1）不是写死
    const codeHard = (rel) => {
      const t = readText(rel) || ''
      return t.split(/\r?\n/).some((l) => {
        const s = l.trim()
        if (!s || s.startsWith('#') || s.startsWith('//') || s.startsWith('*')) return false
        return s.includes(ROOT_LITERAL)
      })
    }
    const bad = [...ps1, ...allMjs].filter(codeHard)
    return { ok: bad.length === 0, detail: bad.length ? zh('imm.10', bad.slice(0, 4).join(','), bad.length > 4 ? zh('lit.3') + bad.length + zh('lit.4') : '') : zh('lit.5') }
  },
  'mjs-header': () => {
    const bad = allMjs.filter((f) => {
      const t = readText(f) || ''
      const first = t.split(/\r?\n/).find((l) => l.trim())
      return first && !/^\s*\/\//.test(first)
    })
    return { ok: bad.length === 0, detail: bad.length ? zh('imm.11', bad.slice(0, 3).join(',')) : zh('imm.12', allMjs.length) }
  },
  'contract-spec': () => {
    const need = ['call', 'exit', 'report', 'root', 'bom']
    const have = Object.keys(SPEC.tools && SPEC.tools.contract ? SPEC.tools.contract : {})
    const miss = need.filter((k) => !have.includes(k))
    return { ok: miss.length === 0, detail: miss.length ? zh('imm.13', miss.join(',')) : zh('imm.14', have.join('/')) }
  },
  'organ-path': () => {
    const reg = JSON.parse(readText('core/registry.json'))
    const cells = Object.values(reg.cells).filter((c) => c.path && c.enabled !== false)
    const miss = cells.filter((c) => !existsSync(join(ROOT, c.path)))
    return { ok: miss.length === 0, detail: miss.length ? zh('imm.15', miss.map((c) => c.id).join(',')) : zh('imm.16', cells.length) }
  },
  'organ-key-helper': () => {
    // 2026-11-11 用户：同根因第二次就做成检查。器官「名字 ↔ 编号」的换算只有 core/organs.mjs 一个入口；
    // 别处再手写这段查找就点名单（今天真踩：一处漏换号，cleared 静默读成 0）。
    const bad = []
    for (const rel of coreMjs) {
      if (rel.endsWith('organs.mjs') || rel.endsWith('immunity.mjs')) continue
      const txt = readText(rel) || ''
      txt.split('\n').forEach((line, i) => {
        const s = line.replace(/\r$/, '')
        if (s.trim().startsWith('//')) return
        if (/String\(c\.id\)\s*===\s*String/.test(s)) bad.push(`${rel}:${i + 1}`)
      })
    }
    return { ok: bad.length === 0, detail: bad.length ? zh('imm.orgkey', bad.join(',')) : zh('imm.orgkey-ok') }
  },
  'probe-fresh': () => {
    const p = join(ROOT, 'track', '.probe-last.json')
    if (!existsSync(p)) return { ok: false, detail: zh('lit.6') }
    const j = JSON.parse(readFileSync(p, 'utf8'))
    const ageH = (Date.now() - new Date(j.at).getTime()) / 3600000
    const ok = j.ok === true && ageH < 24
    return { ok, detail: zh('imm.17', ageH.toFixed(1), j.passed, j.total) }
  },
  'bus-alive': () => {
    const lines = (readText('track/bus.jsonl') || '').split('\n').filter((l) => l.trim())
    if (!lines.length) return { ok: false, detail: zh('lit.7') }
    const last = JSON.parse(lines[lines.length - 1])
    const age = (Date.now() - Number(last.ts)) / 1000
    return { ok: age < 120, detail: zh('imm.18', age.toFixed(0), last.src) }
  },
  'pin-readable': () => {
    const t = readText('state.json')
    if (!t) return { ok: false, detail: zh('lit.8') }
    try {
      const j = JSON.parse(t)
      const n = j.pins ? Object.keys(j.pins).length : 0
      return { ok: n > 0, detail: zh('imm.19', n) }
    } catch {
      return { ok: false, detail: zh('lit.9') }
    }
  },
  'align-guard': () => {
    const t = readText('core/align.mjs') || ''
    const ok = /REFUSED/.test(t) && /state\.before/.test(t)
    return { ok, detail: ok ? zh('lit.10') : zh('lit.11') }
  },
  // 2026-11-09 用户定的接入方式：同一个东西，别人是别人家的个体，各自带自己的 ID 名。
  // 所以 id 只要在同一个 owner 内唯一即可；跨 owner 可以有同名 id（那本来就是两家的同一条）。
  // 真正不许的是：同一个 owner 里两个同 id —— 那时zh('lite.40')就说不清了。
  'ids-unique-per-owner': () => {
    const seen = new Set()
    const dup = []
    for (const e of REG.entries) {
      const k = `${e.owner || 'unknown'}/${e.id}`
      if (seen.has(k)) dup.push(k)
      seen.add(k)
    }
    const owners = [...new Set(REG.entries.map((e) => e.owner || 'unknown'))]
    return { ok: dup.length === 0, detail: dup.length ? zh('imm.20', dup.join(',')) : zh('imm.21', owners.length, owners.join(',')) }
  },
}

const rows = []
let missing = 0
let escalated = 0
let failing = 0
for (const e of REG.entries) {
  // 2026-11-09 修：enforced_by.file 是相对 ROOT 的（verify.ps1 / core/immunity.mjs），
  // 而 readText 按进程 CWD 解析——从别的目录调用时全被判成「没管着」。先拼成绝对路径再读。
  const enforcedFile = String(e.enforced_by.file || '')
  const isAbs = /^([A-Za-z]:|[\\/])/.test(enforcedFile)
  const t = isAbs ? (existsSync(enforcedFile) ? readFileSync(enforcedFile, 'utf8') : null) : readText(enforcedFile)
  const exists = t !== null && t.includes(e.enforced_by.pattern)
  if (!exists) missing++
  const fn = CHECKS[e.live_check]
  let res = { ok: false, detail: zh('lit.12') }
  if (fn) {
    try { res = fn() } catch (err) { res = { ok: false, detail: zh('lit.13') + String(err.message || err).slice(0, 80) } }
  }
  if (!res.ok && e.tier !== 'escalate') failing++
  if (e.tier === 'escalate') escalated++
  rows.push({ ...e, enforced: exists, liveOk: res.ok, detail: res.detail })
}

const lines = []
lines.push(zh('lit.14'))
lines.push('')
lines.push(zh('imm.22', REG.entries.length))
lines.push(zh('lit.15'))
lines.push('')
lines.push(zh('lit.16'))
lines.push('|---|---|---|---|---|---|---|')
rows.forEach((r, i) => {
  const enforced = r.enforced ? zh('lit.17') : zh('lit.18')
  const tier = r.tier === 'escalate' ? zh('lit.19') : zh('lit.20')
  const live = r.liveOk ? zh('lit.21') : r.tier === 'escalate' ? zh('lit.22') : zh('lit.23')
  lines.push(`| ${i + 1} | ${r.owner || 'unknown'} | ${tier} | ${r.failure} | ${r.enforced_by.file} / ${enforced} | ${r.live_check} / ${live} | ${r.detail} |`)
})
lines.push('')
lines.push(zh('lit.24'))
lines.push('')
const docOnly = rows.filter((r) => !r.enforced)
if (!docOnly.length) lines.push(zh('lit.25'))
else for (const r of docOnly) lines.push(`- ${r.id}: ${r.docs}`)
lines.push('')
lines.push(zh('lit.26'))
lines.push('')
const esc = rows.filter((r) => r.tier === 'escalate')
if (!esc.length) lines.push(zh('lit.27'))
else for (const r of esc) lines.push(zh('imm.23', r.id, r.failure))
lines.push('')
lines.push(zh('lit.28'))
lines.push('')
lines.push(zh('lit.29'))
lines.push('|---|---|---|---|---|')
const reg2 = JSON.parse(readText('core/registry.json'))
const idOf = {}
for (const [num, cell] of Object.entries(reg2.cells)) idOf[num] = cell.id
const lastSig = {}
// 2026-11-09: live bus is discharged after 45 minutes, so reading only the live file reported
// every slow organ as zh('lite.41'). History lives in track/archive; the table must read both.
const sigSources = ['track/bus.jsonl', 'track/events.jsonl']
const archDir = join(ROOT, 'track', 'archive')
if (existsSync(archDir)) {
  for (const f of readdirSync(archDir).filter((x) => /^bus-\d{8}\.jsonl$/.test(x))) sigSources.push(join('track', 'archive', f))
}
for (const rel of sigSources) {
  const t = readText(rel) || ''
  for (const line of t.split('\n')) {
    if (!line.trim()) continue
    let r
    try { r = JSON.parse(line) } catch { continue }
    const ts = Number(r.ts) || Date.parse(r.at) || 0
    const s = String(r.src)
    if (!lastSig[s] || ts > lastSig[s].ts) lastSig[s] = { ...r, ts }
  }
}
for (const num of Object.keys(reg2.cells).sort((a, b) => Number(a) - Number(b))) {
  const cell = reg2.cells[num]
  if (cell.enabled === false) continue
  const sig = lastSig[num]
  const name = cell.id
  if (!sig) { lines.push(zh('imm.24', name)); continue }
  const ageMin = (Date.now() - sig.ts) / 60000
  const verdict = [zh('lit.30'), zh('lit.31'), zh('lit.32'), zh('lit.33')][Number(sig.state)] || '?'
  lines.push(zh('imm.25', name, verdict, ageMin < 60 ? ageMin.toFixed(0) + zh('lit.34') : (ageMin / 60).toFixed(1) + zh('lit.35'), sig.value, sig.evid || ''))
}
lines.push('')
writeFileSync(join(ROOT, 'track', zh('lit.36')), lines.join('\n'), 'utf8')

const total = REG.entries.length
const state = missing > 0 ? 2 : failing > 0 ? 1 : 0
// 2026-11-09 用户：「把这些移交给免疫」——verify 不再自己扫一遍标准，改成问免疫要结论。
// --json 给机器读：每条的 id / tier / ok / detail，verify 按 id 取它要的那一条。
if (process.argv.includes('--json')) {
  const out = rows.map((r) => ({ id: r.id, tier: r.tier, ok: !(!r.enforced || (!r.liveOk && r.tier !== 'escalate')), detail: r.detail }))
  console.log(JSON.stringify({ total, missing, failing, escalated, state, rows: out }))
  process.exit(state === 2 ? 2 : 0)
}
console.log(zh('imm.26', total, total - missing, total - failing - escalated, escalated, missing, failing))
if (!quiet) for (const r of rows.filter((x) => !x.enforced || (!x.liveOk && x.tier !== 'escalate'))) console.log(`  ! ${r.id}: ${r.detail}`)
emit(SELF, 4, state, total - failing - escalated, `immunity:${total - missing}/${total - failing - escalated}`, { rush: 0 })
process.exit(state === 2 ? 2 : 0)
