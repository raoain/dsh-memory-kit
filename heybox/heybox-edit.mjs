// heybox-edit.mjs — 改一篇已发布的小黑盒帖（默认只预览，--go 才真改）
//
// 为什么：帖发出去后正文有错（本次：把「评论补充」塞进了正文），只能改不能重发。
// 接口：/bbs/app/api/link/post（POST），与发帖同一路径，带 link_id。
//   ⚠ 该字段组合尚未在线上验证过：可能被拒绝，也可能被当成新帖。
//   所以默认只预览；--go 之前请先看一眼"现正文长度 / 新正文长度"。
//
// 用法：
//   node heybox-edit.mjs --id 195490172 --file paper.md                  # 预览
//   node heybox-edit.mjs --id 195490172 --file paper.md --go             # 真改
//   node heybox-edit.mjs --id 195490172 --file paper.md --go --title "新标题"

import { readFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'

const EXT = 'F:/新建文件夹 (2)/Coopanion/data/extensions/node_modules/cortico-world-heybox/src/heybox/client.mjs'
const CRED = 'F:/新建文件夹 (2)/Coopanion/data/home/companion/data/heybox-credentials.json'

const args = process.argv.slice(2)
const arg = (n, d) => { const i = args.indexOf(`--${n}`); return i >= 0 && args[i + 1] ? args[i + 1] : d }
const go = args.includes('--go')
const id = arg('id')
const file = arg('file')
const newTitle = arg('title')

if (!id || !file) {
  console.error('用法：node heybox-edit.mjs --id <link_id> --file <md> [--title 新标题] [--go]')
  process.exit(2)
}

const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
const md = readFileSync(file, 'utf8').replace(/^\uFEFF/, '').replace(/<!--[\s\S]*?-->/g, '').replace(/^#\s+.*\r?\n/, '')
const blocks = md.split(/\r?\n\s*\r?\n/).map((p) => p.trim()).filter(Boolean)
const html = blocks.map((p) => {
  if (/^【.+】$/.test(p)) return `<p><strong>${esc(p.slice(1, -1))}</strong></p>`
  if (p.startsWith('## ')) return `<p><strong>${esc(p.slice(3).trim())}</strong></p>`
  if (p.startsWith('# ')) return `<p><strong>${esc(p.slice(2).trim())}</strong></p>`
  return `<p>${esc(p).replace(/\r?\n/g, '<br>').replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')}</p>`
}).join('')
const textField = JSON.stringify([{ type: 'html', text: html }])

const { HeyboxClient } = await import(pathToFileURL(EXT).href)
const cred = JSON.parse(readFileSync(CRED, 'utf8'))
const client = new HeyboxClient({ cookies: cred.cookies ?? {}, interval: 900 })
if (!client.loggedIn) { console.error('没有登录态'); process.exit(1) }

// 读回现帖
const tree = await client.get('/bbs/app/link/tree', {
  link_id: String(id), page: 1, is_first: 1, index: 1, owner_only: 0, offset: 0, limit: 1, sort_filter: 'hot',
})
const link = tree.result?.link ?? {}
const curTitle = link.title ?? ''
const curText = typeof link.text === 'string' ? link.text : JSON.stringify(link.text ?? '')

console.log(JSON.stringify({
  mode: go ? 'GO（会真改）' : '预览（不修改）',
  link_id: id,
  现标题: curTitle,
  新标题: newTitle || '(不改)',
  现正文长度: curText.length,
  新正文长度: textField.length,
  新正文首80: html.slice(0, 80),
  新正文末80: html.slice(-80),
}, null, 2))

if (!go) { console.log('\n未修改。确认无误后加 --go 再跑一次。'); process.exit(0) }

const form = {
  link_id: String(id),
  text: textField,
  words_count: String(md.length),
  post_type: '1',
  link_tag: '11',
  draft: '0',
  view_limit: '1',
  original: '1',
  topic_ids: '806933',
  hashtags: JSON.stringify(['AI']),
}
form.title = newTitle || curTitle

try {
  const data = await client.request({ path: '/bbs/app/api/link/post', method: 'POST', body: form, workshop: true })
  console.log('\n=== 返回 ===')
  console.log(JSON.stringify(data).slice(0, 400))

  const after = await client.get('/bbs/app/link/tree', {
    link_id: String(id), page: 1, is_first: 1, index: 1, owner_only: 0, offset: 0, limit: 1, sort_filter: 'hot',
  })
  const a = after.result?.link ?? {}
  const aText = typeof a.text === 'string' ? a.text : JSON.stringify(a.text ?? '')
  console.log('\n=== 读回 ===')
  console.log(JSON.stringify({
    标题: a.title,
    正文长度: aText.length,
    与期望一致: aText.length === textField.length,
  }, null, 2))
} catch (err) {
  console.error(JSON.stringify({ ok: false, error: String(err?.message ?? err), code: err?.code ?? 'unknown' }, null, 2))
  process.exit(1)
}
