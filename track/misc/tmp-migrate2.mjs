import fs from 'node:fs';
import path from 'node:path';

const ROOT = 'F:/Tools/coo-day1';
const TRACK = path.join(ROOT, 'track');
const GO = process.argv.includes('--go');

// 第二批：上一轮因"被脚本硬引用"而留原地的 md。用户定：能改就改，改脚本的钱付得起。
// 显式指定落点（不再靠正则猜）
const EXTRA = {
  '数学-链.md': 'theory',
  '数学-链-v2.md': 'theory',
  '理论全文-2026-10-30.md': 'theory',
  '术语对照.md': 'terms',
  '待消化.md': 'misc',
  '大计划.md': 'misc',
  '接缝.md': 'misc',
  '格册.md': 'misc',
  '比喻与说法.md': 'misc',
  '机器对应.md': 'misc',
  '借来的机制.md': 'misc',
  '脚本清单.md': 'misc',
  '回档实验-待答.md': 'misc',
  '豁免证明-完成声明-20261122.md': 'misc',
};

const move = [];
for (const [f, zone] of Object.entries(EXTRA)) {
  if (fs.existsSync(path.join(TRACK, f))) move.push({ f, to: zone });
}
console.log(`第二批将迁: ${move.length}`);
for (const p of move) console.log(`  → ${p.to}\\${p.f}`);

if (!GO) { console.log('(dry-run；加 --go 执行)'); process.exit(0); }

for (const p of move) {
  const from = path.join(TRACK, p.f);
  const to = path.join(TRACK, p.to, p.f);
  if (!fs.existsSync(path.join(TRACK, p.to))) fs.mkdirSync(path.join(TRACK, p.to), { recursive: true });
  fs.renameSync(from, to);
}

// 全库替换（含 ps1/mjs：这次就是要把脚本里的硬编码改掉）
const exts = new Set(['.ps1', '.mjs', '.md', '.json', '.jsonl', '.yml', '.yaml', '.txt', '.cmd', '.vbs']);
const skip = new Set(['.git', 'trash', 'archive', 'tmp', '区册', 'node_modules', '.locks']);
const files = [];
(function walk(d) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    if (e.isDirectory()) { if (!skip.has(e.name)) walk(path.join(d, e.name)); continue; }
    if (exts.has(path.extname(e.name).toLowerCase())) files.push(path.join(d, e.name));
  }
})(ROOT);

let changed = 0;
for (const p of move) {
  const pairs = [
    ['track\\' + p.f, 'track\\' + p.to + '\\' + p.f],
    ['track/' + p.f, 'track/' + p.to + '/' + p.f],
  ];
  for (const f of files) {
    let t;
    try { t = fs.readFileSync(f, 'utf8'); } catch { continue; }
    if (!t.includes(p.f)) continue;
    const before = t;
    for (const [a, b] of pairs) t = t.split(a).join(b);
    if (t !== before) { fs.writeFileSync(f, t, 'utf8'); changed++; }
  }
}
console.log(`\n第二批完成：移动 ${move.length}；改引用文件 ${changed}`);
