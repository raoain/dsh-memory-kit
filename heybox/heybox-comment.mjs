// heybox-comment.mjs — 回复小黑盒评论（默认预览，加 --go 才发）
//
// 用法：
//   node heybox-comment.mjs --link 195172607 --comment 986347705 --text "……"          # 预览
//   node heybox-comment.mjs --link 195172607 --comment 986347705 --text "……" --go      # 真发
//
// 表单字段照 world 的 reply 实现：link_id / text / root_id / reply_id / is_cy。

import { readFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'

const EXT = 'F:/新建文件夹 (2)/Coopanion/data/extensions/node_modules/cortico-world-heybox/src/heybox/client.mjs'
const CRED = 'F:/新建文件夹 (2)/Coopanion/data/home/companion/data/heybox-credentials.json'

const args = process.argv.slice(2)
const arg = (n) => { const i = args.indexOf(`--${n}`); return i >= 0 ? args[i + 1] : undefined }
const go = args.includes('--go')
const linkId = arg('link')
const commentId = arg('comment')
const text = arg('text')

if (!linkId || !commentId || !text) {
  console.error('用法：node heybox-comment.mjs --link <link_id> --comment <comment_id> --text "..." [--go]')
  process.exit(2)
}
if (text.length > 500) { console.error(`超出 500 字（当前 ${text.length}）`); process.exit(2) }

const form = { link_id: linkId, text, root_id: commentId, reply_id: commentId, is_cy: '0' }

if (!go) {
  console.log(JSON.stringify({ mode: '预览（不发送）', chars: text.length, form }, null, 2))
  console.log('\n未发送。确认后加 --go。')
  process.exit(0)
}

const { HeyboxClient } = await import(pathToFileURL(EXT).href)
const client = new HeyboxClient({ cookies: JSON.parse(readFileSync(CRED, 'utf8')).cookies ?? {}, interval: 900 })
if (!client.loggedIn) { console.error('没有登录态'); process.exit(1) }

try {
  const data = await client.request({ path: '/bbs/app/comment/create', method: 'POST', body: form, workshop: true })
  console.log(JSON.stringify({ ok: true, commentid: data?.commentid ?? null, raw: data?.status ?? null }, null, 2))
} catch (err) {
  console.error(JSON.stringify({ ok: false, error: String(err?.message ?? err), code: err?.code ?? 'unknown' }, null, 2))
  process.exit(1)
}
