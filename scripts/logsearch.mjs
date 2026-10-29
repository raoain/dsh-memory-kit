// logsearch.mjs — 在 DSH 会话日志里搜「用户说过的话」
//
// 两个关键点（都是踩过的坑）：
// ① 会话日志是多帧 zstd，"解一次只拿到第一帧"（只有 252 字节的 session 头）→ 必须按魔数切帧逐帧解
// ② 只搜 type=user/message 的记录。否则我自己的命令/回答里引用的句子也会被搜到，
//    于是「我编一句用户说 X，再搜 X」就能自我印证 —— 那正好是我们要防的伪造来源。
//
// 用法：node logsearch.mjs "要搜的原文" [最大命中数]
// 输出 JSON：{ ok, files, scanned, hits:[{session, time, snippet}] }

import { readFileSync, readdirSync } from 'node:fs';
import { zstdDecompressSync } from 'node:zlib';
import { join, basename, dirname } from 'node:path';

const home = process.env.USERPROFILE || process.env.HOME;
const root = join(home, '.dsh', 'sessions');
const needle = process.argv[2];
const maxHits = Number(process.argv[3] || 5);

if (!needle) {
  console.log(JSON.stringify({ ok: false, error: '缺少搜索词' }));
  process.exit(1);
}

function walk(dir, out = []) {
  let entries;
  try { entries = readdirSync(dir, { withFileTypes: true }); } catch { return out; }
  for (const e of entries) {
    const p = join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.zstd')) out.push(p);
  }
  return out;
}

// 把一条记录里所有 text 字段抽出来
function texts(o, acc = []) {
  if (!o || typeof o !== 'object') return acc;
  if (typeof o.text === 'string') acc.push(o.text);
  for (const v of Object.values(o)) {
    if (v && typeof v === 'object') texts(v, acc);
  }
  return acc;
}

const MAGIC = [0x28, 0xb5, 0x2f, 0xfd];
const files = walk(root);
const hits = [];
let scanned = 0;

for (const f of files) {
  let buf;
  try { buf = readFileSync(f); } catch { continue; }
  const starts = [];
  for (let i = 0; i <= buf.length - 4; i++) {
    if (buf[i] === MAGIC[0] && buf[i + 1] === MAGIC[1] && buf[i + 2] === MAGIC[2] && buf[i + 3] === MAGIC[3]) starts.push(i);
  }
  if (!starts.length) continue;
  scanned++;
  for (let k = 0; k < starts.length; k++) {
    const s = starts[k];
    const e = k + 1 < starts.length ? starts[k + 1] : buf.length;
    let text;
    try { text = zstdDecompressSync(buf.subarray(s, e)).toString('utf8'); } catch { continue; }
    for (const line of text.split('\n')) {
      if (!line.includes(needle)) continue;      // 快速过滤
      let o;
      try { o = JSON.parse(line); } catch { continue; }
      if (o.type !== 'user/message') continue;   // 只认用户消息
      // 排除「平台注入」：meow 的长期记忆块也是以 user/message 形式送达的，
      // 它不是用户当场的原话。不排除的话，记忆里的一条旧转述就能给自己作证。
      if (/=====\s*长期记忆|【关于user】|【设计原则】|【记忆导引】|\[meow-memory-reflect\]|本会话已压缩|关键词:|source_session|importance/.test(line)) continue;
      const body = texts(o).join('\n');
      if (!body.includes(needle)) continue;
      const idx = body.indexOf(needle);
      hits.push({
        session: basename(dirname(f)),
        time: o.time ? new Date(o.time).toISOString() : null,
        snippet: body.slice(Math.max(0, idx - 60), idx + needle.length + 60).replace(/\s+/g, ' '),
      });
      if (hits.length >= maxHits) break;
    }
    if (hits.length >= maxHits) break;
  }
  if (hits.length >= maxHits) break;
}

console.log(JSON.stringify({ ok: true, files: files.length, scanned, needle, hitCount: hits.length, hits }, null, 2));
process.exit(0);
