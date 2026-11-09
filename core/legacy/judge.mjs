// core/judge.mjs —— 数核最小版：吃结构化事实，吐死物
//
// 输入：
//   text  —— 一句待判的话（由语言模型翻译出来的"候选"，不作数）
//   facts —— 本轮的结构化事实：
//            { calls: [{tool, ok, out}], files: [{path, body}] }
// 输出（死物，不是话）：
//   { v: 'yes' | 'no' | 'unknown', evid: [..], missing: [..] }
//
// 三条判据（判据来自项目，不由本文件发明）：
//   J1 依据：有形标记（[读自]/[命令回显]/[推断]），且 [读自 路径] 必须能打开
//   J2 数字：句中每个数字必须能在 facts 里逐位找到；没有 facts → unknown
//   J3 兜底：J1 不成立 → no；J1 成立但 J2 无法判 → unknown

import { existsSync, readFileSync } from 'node:fs'

const MARK = /\[(读自|命令回显|推断)[^\]]*\]/g
const READ = /\[读自\s*([^\]]+)\]/g

function pickNumbers(text) {
  return [...new Set((text.match(/\d[\d,.]*|\d/g) || []).map((n) => n.replace(/,/g, '')))]
    .filter((n) => n.length >= 2)
}

export function judge({ text = '', facts = { calls: [], files: [] } } = {}) {
  const evid = []
  const missing = []

  // J1 依据
  const marks = [...text.matchAll(MARK)].map((m) => m[0])
  const reads = [...text.matchAll(READ)].map((m) => m[1].trim().replace(/^["'“]|["'”]$/g, ''))
  const unopenable = reads.filter((p) => !existsSync(p))

  if (marks.length === 0) {
    return { v: 'no', evid: ['J1: 全文无依据标记'], missing: ['依据标记'] }
  }
  if (unopenable.length > 0) {
    return { v: 'no', evid: [`J1: 指到的路径打不开 ${unopenable.join(', ')}`], missing: unopenable }
  }
  evid.push(`J1: 标记 ${marks.length} 处，路径可打开 ${reads.length} 处`)

  // J2 数字
  const nums = pickNumbers(text)
  if (nums.length === 0) {
    evid.push('J2: 无需核的数字')
    return { v: 'yes', evid, missing }
  }

  const corpus = []
  for (const c of facts.calls || []) if (c && c.out) corpus.push(String(c.out))
  for (const f of facts.files || []) {
    if (f && f.body) corpus.push(String(f.body))
    else if (f && f.path && existsSync(f.path)) corpus.push(readFileSync(f.path, 'utf8'))
  }

  if (corpus.length === 0) {
    evid.push('J2: 无事实可核')
    return { v: 'unknown', evid, missing: nums }
  }

  const hay = corpus.join('\n')
  const notFound = nums.filter((n) => !hay.includes(n))
  if (notFound.length > 0) {
    return { v: 'no', evid: [...evid, `J2: 无出处数字 ${notFound.join(' ')}`], missing: notFound }
  }
  evid.push(`J2: 数字 ${nums.length} 个全部命中`)
  return { v: 'yes', evid, missing }
}

export default { judge }
