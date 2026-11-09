// heybox-read.mjs — 直连小黑盒接口（只读），复用 Coopanion world 自带的签名与 cookie
//
// 为什么要有这个：world 的工具只挂在桌宠身上，我这边只能读 schema。
// 但它的实现就在本机：client.mjs 负责签名/cookie，我把登录态借过来，就能自己查。
//
// 用法（node 24+）：
//   node heybox-read.mjs tree <link_id>        读帖子 + 评论
//   node heybox-read.mjs feed [limit]          首页信息流
//   node heybox-read.mjs messages [limit]      私信列表
//   node heybox-read.mjs profile <userid>      用户资料
//   node heybox-read.mjs raw <path> [k=v ...]  任意 GET
//
// 只做 GET。写操作（发帖/评论/点赞）不走这个脚本——那要过桌宠的写操作闸门。

const EXT = 'F:/新建文件夹 (2)/Coopanion/data/extensions/node_modules/cortico-world-heybox/src/heybox/client.mjs'
const CRED = 'F:/新建文件夹 (2)/Coopanion/data/home/companion/data/heybox-credentials.json'
import { readFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'

const { HeyboxClient } = await import(pathToFileURL(EXT).href)
const cred = JSON.parse(readFileSync(CRED, 'utf8'))
const client = new HeyboxClient({ cookies: cred.cookies ?? {}, interval: 900 })

const [action, ...rest] = process.argv.slice(2)

function out(obj) { console.log(JSON.stringify(obj, null, 2)) }

try {
  if (!client.loggedIn) { out({ ok: false, error: '没有登录态，先让桌宠完成扫码登录' }); process.exit(1) }

  if (action === 'tree') {
    const linkId = rest[0]
    if (!linkId) { out({ ok: false, error: '需要 link_id' }); process.exit(1) }
    const data = await client.get('/bbs/app/link/tree', {
      link_id: linkId, page: 1, is_first: 1, index: 1, owner_only: 0, offset: 0, limit: 20, sort_filter: 'hot',
    })
    out(data)
  } else if (action === 'feed') {
    const limit = Number(rest[0] ?? 10)
    out(await client.get('/bbs/app/feeds', { offset: 0, limit, pull: '0', dw: '604' }))
  } else if (action === 'messages') {
    const limit = Number(rest[0] ?? 10)
    out(await client.get('/bbs/app/user/message', { list_type: 0, offset: 0, limit }))
  } else if (action === 'profile') {
    const userid = rest[0]
    if (!userid) { out({ ok: false, error: '需要 userid' }); process.exit(1) }
    out(await client.get('/bbs/app/profile/user/profile', { userid }))
  } else if (action === 'raw') {
    const path = rest[0]
    const params = {}
    for (const kv of rest.slice(1)) { const i = kv.indexOf('='); if (i > 0) params[kv.slice(0, i)] = kv.slice(i + 1) }
    out(await client.get(path, params))
  } else {
    out({ ok: false, error: `未知操作：${action ?? '(空)'}`, usage: 'tree <link_id> | feed | messages | profile <userid> | raw <path>' })
    process.exit(1)
  }
} catch (err) {
  out({ ok: false, error: String(err?.message ?? err), code: err?.code ?? 'unknown' })
  process.exit(1)
}
