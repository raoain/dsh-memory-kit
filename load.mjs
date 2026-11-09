// load.mjs — 从会话日志统计「今天干了多少活」（载荷的原始数据）
//
// 为什么：地基够不够，只能拿载荷说话。载荷 = 今天产生了多少条消息、多少次工具调用。
// 日志是多帧 zstd（解一次只拿第一帧），所以按魔数切帧逐帧解。
//
// 用法：node load.mjs [yyyy-MM-dd]
// 输出：{ ok, date, userMsgs, assistantMsgs, toolCalls, toolResults, turns }

import { readFileSync, readdirSync } from 'node:fs';
import { zstdDecompressSync } from 'node:zlib';
import { join, basename, dirname } from 'node:path';

const home = process.env.USERPROFILE || process.env.HOME;
const root = join(home, '.dsh', 'sessions');
const date = process.argv[2] || new Date().toISOString().slice(0, 10);

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

const MAGIC = [0x28, 0xb5, 0x2f, 0xfd];
const stat = { userMsgs: 0, assistantMsgs: 0, toolCalls: 0, toolResults: 0, turns: 0 };
let sessions = 0;
const seen = new Set();

for (const f of walk(root)) {
  let buf;
  try { buf = readFileSync(f); } catch { continue; }
  const starts = [];
  for (let i = 0; i <= buf.length - 4; i++) {
    if (buf[i] === MAGIC[0] && buf[i + 1] === MAGIC[1] && buf[i + 2] === MAGIC[2] && buf[i + 3] === MAGIC[3]) starts.push(i);
  }
  for (let k = 0; k < starts.length; k++) {
    const s = starts[k];
    const e = k + 1 < starts.length ? starts[k + 1] : buf.length;
    let text;
    try { text = zstdDecompressSync(buf.subarray(s, e)).toString('utf8'); } catch { continue; }
    for (const line of text.split('\n')) {
      if (!line.includes('"time"')) continue;
      let o;
      try { o = JSON.parse(line); } catch { continue; }
      if (!o.time) continue;
      const d = new Date(o.time).toISOString().slice(0, 10);
      if (d !== date) continue;
      const key = (o.type || '') + ':' + o.seq + ':' + o.time;
      if (seen.has(key)) continue;      // 同一帧可能被扫两次，按 seq+time 去重
      seen.add(key);
      if (o.type === 'user/message') stat.userMsgs++;
      else if (o.type === 'assistant/message') stat.assistantMsgs++;
      else if (o.type === 'tool/call') stat.toolCalls++;
      else if (o.type === 'tool/result') stat.toolResults++;
      else if (o.type === 'turn/start') stat.turns++;
    }
  }
  sessions++;
}

console.log(JSON.stringify({ ok: true, date, sessions, ...stat }));
