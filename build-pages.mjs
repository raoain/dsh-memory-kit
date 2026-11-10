// 一次性：给 track/*.md 编数字页号（只增不改），
// 编号写进 core/pages.json（纯 ASCII），文件名写进 core/locales/zh.json 的 page.<id>（翻译层）。
import { readFileSync, writeFileSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const root = new URL('.', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const trackDir = join(root, 'track');
const zhPath = join(root, 'core', 'locales', 'zh.json');
const pagesPath = join(root, 'core', 'pages.json');

const files = readdirSync(trackDir).filter((f) => f.endsWith('.md')).sort();
const zh = JSON.parse(readFileSync(zhPath, 'utf8'));
const pages = existsSync(pagesPath) ? JSON.parse(readFileSync(pagesPath, 'utf8')) : { version: 1, note: 'numeric page ids, append-only; filenames live in core/locales/zh.json as page.<id>', ids: [] };

const used = new Map(); // filename -> id
for (const id of pages.ids) {
  const key = `page.${id}`;
  if (zh[key]) used.set(zh[key].replace(/\\/g, '/'), id);
}
let next = pages.ids.length ? Math.max(...pages.ids) + 1 : 101;
for (const f of files) {
  if ([...used.keys()].some((k) => k.endsWith('/' + f) || k === 'track/' + f)) continue;
  const id = next++;
  pages.ids.push(id);
  zh[`page.${id}`] = `track\\${f}`;
  used.set('track/' + f, id);
}
pages.ids.sort((a, b) => a - b);
writeFileSync(zhPath, JSON.stringify(zh, null, 2) + '\n', 'utf8');
writeFileSync(pagesPath, JSON.stringify(pages, null, 2) + '\n', 'utf8');
console.log(JSON.stringify({ files: files.length, ids: pages.ids.length, first: pages.ids[0], last: pages.ids[pages.ids.length - 1] }));
