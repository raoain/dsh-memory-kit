// core/run.mjs —— 一条路：把"候选话 + 本轮事实"喂给数核，输出死物 JSON
//
// 用法：
//   node core/run.mjs --text <话文件> [--fact <事实json>]
// 事实 JSON 形如：
//   { "calls": [{"tool":"pwsh","ok":true,"out":"verify 46 项 OK 46"}],
//     "files": [{"path":"notebook\\0-核心.md"}] }
// 输出：一行 JSON（死物）。v=no 时退出码 1。

import { readFileSync, existsSync } from 'node:fs'
import { judge } from './judge.mjs'

const argv = process.argv.slice(2)
const get = (flag) => {
  const i = argv.indexOf(flag)
  return i >= 0 ? argv[i + 1] : ''
}

const textPath = get('--text')
const factPath = get('--fact')

if (!textPath) {
  console.error('用法: node core/run.mjs --text <话文件> [--fact <事实json>]')
  process.exit(2)
}

const text = existsSync(textPath) ? readFileSync(textPath, 'utf8') : ''
const facts = factPath && existsSync(factPath)
  ? JSON.parse(readFileSync(factPath, 'utf8'))
  : { calls: [], files: [] }

const out = judge({ text, facts })
console.log(JSON.stringify(out))
process.exit(out.v === 'no' ? 1 : 0)
