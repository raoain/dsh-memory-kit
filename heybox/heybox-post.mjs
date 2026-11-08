// heybox-post.mjs — 直接发小黑盒文章（复用 world 的签名与登录态）
//
// 与 heybox-read.mjs 的区别：这个会写。所以默认只预览，加 --go 才真发。
//
// 用法：
//   node heybox-post.mjs --file post2.md --title "标题"                     # 预览表单
//   node heybox-post.mjs --file post2.md --title "标题" --go                 # 真发
//   node heybox-post.mjs --file post2.md --title "标题" --go --community 806933
//
// 默认：文章类，分区 AI（806933），话题标签 AI，原创，公开。

import { readFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'

const EXT = 'F:/新建文件夹 (2)/Coopanion/data/extensions/node_modules/cortico-world-heybox/src/heybox/client.mjs'
const CRED = 'F:/新建文件夹 (2)/Coopanion/data/home/companion/data/heybox-credentials.json'

const args = process.argv.slice(2)
function arg(name, def) {
  const i = args.indexOf(`--${name}`)
  return i >= 0 && args[i + 1] && !args[i + 1].startsWith('--') ? args[i + 1] : def
}
const go = args.includes('--go')
const file = arg('file')
const title = arg('title')
const community = arg('community', '806933')
const hashtags = (arg('tag', 'AI') || 'AI').split(',').map((s) => s.trim()).filter(Boolean)

if (!file || !title) {
  console.error('用法：node heybox-post.mjs --file <md> --title <标题> [--go] [--community 806933] [--tag AI]')
  process.exit(2)
}

const md = readFileSync(file, 'utf8')
// 简单 HTML 化：空行分段，行内转义；【…】当小标题
const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
const blocks = md.split(/\r?\n\s*\r?\n/).map((p) => p.trim()).filter(Boolean)
const html = blocks.map((p) => {
  if (/^【.+】$/.test(p)) return `<p><strong>${esc(p.slice(1, -1))}</strong></p>`
  return `<p>${esc(p).replace(/\r?\n/g, '<br>').replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')}</p>`
}).join('')

const form = {
  title,
  text: JSON.stringify([{ type: 'html', text: html }]),
  post_type: '1',
  link_tag: '11',
  draft: '0',
  view_limit: '1',
  original: '1',
  words_count: String(md.length),
  topic_ids: community,
  hashtags: JSON.stringify(hashtags),
}

const preview = {
  mode: go ? 'GO（会真发）' : '预览（不发送）',
  title,
  community,
  hashtags,
  words_count: md.length,
  html_bytes: html.length,
  paragraphs: blocks.length,
  form_keys: Object.keys(form),
  text_head: html.slice(0, 160) + '…',
}

if (!go) {
  console.log(JSON.stringify(preview, null, 2))
  console.log('\n未发送。确认无误后加 --go 再跑一次。')
  process.exit(0)
}

const { HeyboxClient } = await import(pathToFileURL(EXT).href)
const cred = JSON.parse(readFileSync(CRED, 'utf8'))
const client = new HeyboxClient({ cookies: cred.cookies ?? {}, interval: 900 })
if (!client.loggedIn) { console.error('没有登录态'); process.exit(1) }

try {
  const data = await client.request({ path: '/bbs/app/api/link/post', method: 'POST', body: form, workshop: true })
  const id = data?.link_id ?? data?.result?.link_id ?? data?.result?.linkid ?? ''
  console.log(JSON.stringify({ ok: true, link_id: String(id), url: id ? `https://www.xiaoheihe.cn/app/bbs/link/${id}` : null }, null, 2))
  if (id) {
    const tree = await client.get('/bbs/app/link/tree', { link_id: String(id), page: 1, is_first: 1, index: 1, owner_only: 0, offset: 0, limit: 1, sort_filter: 'hot' })
    const link = tree.result?.link ?? {}
    console.log(JSON.stringify({ readback_title: link.title ?? null, matched: link.title === title }, null, 2))
  }
} catch (err) {
  console.error(JSON.stringify({ ok: false, error: String(err?.message ?? err), code: err?.code ?? 'unknown' }, null, 2))
  process.exit(1)
}
