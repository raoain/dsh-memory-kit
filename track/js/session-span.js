// 报一个 session 的存活时长、对话轮数、压缩（燃尽）次数（只读）
const z = require('node:zlib');
const fs = require('fs');
const f = process.argv[2];
const lines = z.zstdDecompressSync(fs.readFileSync(f)).toString().split('\n').filter(Boolean);
const recs = [];
for (const l of lines) { try { recs.push(JSON.parse(l)); } catch (e) {} }
const fmt = (ms) => new Date(ms).toLocaleString('sv-SE', { timeZone: 'Asia/Shanghai' });
const meta = recs.find((r) => r.type === 'session');
const first = meta ? meta.createdAt : recs[0].time;
let last = 0;
for (const r of recs) if (typeof r.time === 'number' && r.time > last) last = r.time;
const hours = (last - first) / 3600000;
console.log('created  ', fmt(first));
console.log('lastEvent', fmt(last));
console.log('存活      ', (hours / 24).toFixed(2), '天 =', hours.toFixed(1), '小时');
const users = recs.filter((r) => r.type === 'user/message');
console.log('用户消息  ', users.length);
if (users.length) {
  console.log('首条用户  ', fmt(users[0].time), '| 末条用户', fmt(users[users.length - 1].time));
}
const turns = recs.filter((r) => r.type === 'turn/start').length;
console.log('轮次      ', turns);
const comps = recs.filter((r) => r.type === 'compaction/start');
console.log('压缩次数  ', comps.length, comps.map((c) => fmt(c.time)).join(' | '));
const sum = recs.filter((r) => r.type === 'compaction/summary');
for (const s of sum) console.log('  summary@' + fmt(s.time), JSON.stringify(s.data).slice(0, 160));
