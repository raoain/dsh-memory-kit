// dsh-memory-chain — 五个动词的分层记事本
// 醒来 wake / 干活 work / 遇坑 pit / 收工 close
//
// 设计取向：不给参数，给习惯。
// 参数是给不认识的人用的；我们每天就是这个顺序。

import { readFileSync, writeFileSync, appendFileSync, existsSync, mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { homedir } from 'node:os'

export const name = 'dsh-memory-chain'

// Cordis 要求显式声明依赖的服务：不写 inject 就取 ctx.tools 会抛
// 「cannot get property "tools" without inject」，插件整条 entry 失败且不报错到界面之外。
export const inject = ['tools']

const DEFAULT_ROOT = join(homedir(), '.dsh', 'notebook')

function paths(root) {
  return {
    core: join(root, '0-核心.md'),
    work: join(root, '1-工作.md'),
    file: join(root, '2-档案.md'),
    tomb: join(root, '3-墓碑.md'),
  }
}

function readIf(p) {
  try {
    if (!existsSync(p)) return ''
    const s = readFileSync(p, 'utf8')
    // 文件可能带 UTF-8 BOM（Windows/PowerShell 5.1 的习惯），读出来要剥掉，
    // 否则第一个工具结果会以不可见的 U+FEFF 开头
    return s.charCodeAt(0) === 0xfeff ? s.slice(1) : s
  } catch { return '' }
}

function ensureRoot(p) {
  const dir = dirname(p)
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true })
}

function stamp() {
  const d = new Date()
  const p2 = (n) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${p2(d.getMonth() + 1)}-${p2(d.getDate())} ${p2(d.getHours())}:${p2(d.getMinutes())}`
}

// 追加前确保文件以换行结尾，否则新条目会粘在上一行末尾
function appendLine(path, text) {
  ensureRoot(path)
  let body = text
  const old = readIf(path)
  if (old.length > 0 && !old.endsWith('\n')) body = '\n' + body
  appendFileSync(path, body, 'utf8')
}

// 首次运行自动建出最小四页，保证「装上 → wake 一次」就能用
function initTemplates(root) {
  const P = paths(root)
  const defs = [
    [P.core, '# 核心层\n\n## 我是谁\n\n（写：你是谁、使用者是谁、三条纪律。这页每次都会读，压到 2 KB 以内。）\n'],
    [P.work, '# 工作层\n\n> 每次读最近一屏；work 工具会往上追加。\n\n'],
    [P.file, '# 档案层\n\n> 按需查：现象 | 根因 | 修法。\n\n'],
    [P.tomb, '# 墓碑\n\n> 作废的旧规矩：旧说法 | 为什么作废 | 现在按什么来。\n\n'],
  ]
  for (const [p, body] of defs) {
    if (!existsSync(p)) {
      ensureRoot(p)
      writeFileSync(p, body, 'utf8')
    }
  }
}

export function apply(ctx, config = {}) {
  const root = config.root || DEFAULT_ROOT
  const P = paths(root)
  ensureRoot(P.core)
  initTemplates(root)

  const textOut = (text) => ({
    schema: { type: 'object', additionalProperties: false, required: ['ok', 'text'], properties: { ok: { type: 'boolean' }, text: { type: 'string' } } },
    render: (_a, v) => [{ type: 'text', text: v.text }],
  })

  // --- 醒来 ---
  ctx.tools.register({
    name: 'notebook_wake',
    description: '读记事本的核心层（我是谁、使用者是谁、三条纪律）和工作层最近一屏。每次开工先调这个。',
    parameters: { type: 'object', additionalProperties: false, properties: {} },
    output: textOut(),
    execute() {
      const core = readIf(P.core)
      const work = readIf(P.work).split('\n').filter(Boolean).slice(-20).join('\n')
      if (!core && !work) return { ok: false, text: `记事本还没建：${root}` }
      return { ok: true, text: `${core}\n\n--- 工作层（最近 20 行）---\n${work}` }
    },
  })

  // --- 干活 ---
  ctx.tools.register({
    name: 'notebook_work',
    description: '往工作层追加一条「正在做的事」。一句话，写完就完。',
    parameters: {
      type: 'object', additionalProperties: false, required: ['text'],
      properties: { text: { type: 'string', description: '一句话：在做什么 / 做完什么' } },
    },
    output: textOut(),
    execute(args) {
      appendLine(P.work, `- [${stamp()}] ${args.text}\n`)
      return { ok: true, text: `工作层 +1：${args.text}` }
    },
  })

  // --- 遇坑 ---
  ctx.tools.register({
    name: 'notebook_pit',
    description: '往档案层记一个坑。三段式：现象|根因|修法，用半角竖线分隔。这些平时不读，查的时候才看。',
    parameters: {
      type: 'object', additionalProperties: false, required: ['text'],
      properties: { text: { type: 'string', description: '格式：现象|根因|修法' } },
    },
    output: textOut(),
    execute(args) {
      ensureRoot(P.file)
      const [what, why, fix] = String(args.text).split('|')
      const entry = `\n### ${(what || '').trim()}\n- 时间：${stamp()}\n- 根因：${(why || '待补').trim()}\n- 修法：${(fix || '待补').trim()}\n`
      appendLine(P.file, entry)
      return { ok: true, text: `档案层 +1：${(what || '').trim()}` }
    },
  })

  // --- 标死（墓碑）---
  ctx.tools.register({
    name: 'notebook_tomb',
    description: '给一条作废的旧规矩立墓碑。三段式：旧说法|为什么作废|现在按什么来。只收「读到会让人立刻做错事」的，版本变更不要进来。',
    parameters: {
      type: 'object', additionalProperties: false, required: ['text'],
      properties: { text: { type: 'string', description: '格式：旧说法|为什么作废|现在按什么来' } },
    },
    output: textOut(),
    execute(args) {
      ensureRoot(P.tomb)
      const [old, why, now] = String(args.text).split('|')
      const d = new Date()
      const p2 = (n) => String(n).padStart(2, '0')
      const date = `${d.getFullYear()}-${p2(d.getMonth() + 1)}-${p2(d.getDate())}`
      const entry = `\n### 「${(old || '').trim()}」（${date} 作废）\n- 为什么：${(why || '待补').trim()}\n- 现在按：${(now || '待补').trim()}\n`
      if (!existsSync(P.tomb)) {
        ensureRoot(P.tomb)
        writeFileSync(P.tomb, '# 墓碑 · 作废清单\n\n> 翻到旧文件、旧结论时来这里核对：这条是不是已经作废了？\n\n---\n', 'utf8')
      }
      appendLine(P.tomb, entry)
      return { ok: true, text: `墓碑 +1：「${(old || '').trim()}」` }
    },
  })

  // --- 收工 ---
  ctx.tools.register({
    name: 'notebook_close',
    description: '收工：在工作层留一条收工标记，并提醒该跑快照和备份。备份仍需宿主的脚本执行。',
    parameters: {
      type: 'object', additionalProperties: false,
      properties: { note: { type: 'string', description: '可选的收工备注' } },
    },
    output: textOut(),
    execute(args = {}) {
      ensureRoot(P.work)
      const note = args.note ? `（${args.note}）` : ''
      appendLine(P.work, `- [${stamp()}] 收工${note}\n`)
      return {
        ok: true,
        text: `收工标记已写${note}。别忘了让宿主跑：status.ps1（快照）+ backup.ps1（双盘备份）。`,
      }
    },
  })

  ctx.logger?.info?.(`dsh-memory-chain: 记事本已挂载 ${root}`)
}


// 同时提供默认导出：两种宿主加载方式都覆盖
export default { name, inject, apply }
