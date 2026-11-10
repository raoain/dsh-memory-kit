// hippocampus.mjs - organ 13 (memHi), the first predecessor of the total brain.
// Reads past verdicts (track/brain.jsonl) and builds an experience index:
// for each organ: how many times judged, first/last, and - the important half -
// every time it went bad -> good, WITH what was done in between (from dispatch.jsonl).
// Without that last part the index can say "it keeps failing" but not "this is what
// made it stop failing"; the basal-ganglia style choice needs the second sentence.
// ASCII only on this side.
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { ROOT } from './root.mjs';

const BRAIN = join(ROOT, 'track', 'brain.jsonl');
const DISPATCH = join(ROOT, 'track', 'dispatch.jsonl');
const OUT = join(ROOT, 'track', 'hippocampus.json');
const MAX_CLEARS = 20; // keep the file small; newest wins

function loadLines(p) {
  if (!existsSync(p)) return [];
  return readFileSync(p, 'utf8').split(/\r?\n/).filter((l) => l.trim().length > 0);
}

function main() {
  const lines = loadLines(BRAIN);

  // dispatches: what actually got sent to whom, so a clear can name its cause
  const dispatches = loadLines(DISPATCH).map((l) => {
    try { return JSON.parse(l); } catch { return null; }
  }).filter(Boolean);

  const per = new Map();
  const BAD = new Set(['broken', 'silent', 'late']);
  for (const line of lines) {
    let rec;
    try { rec = JSON.parse(line); } catch { continue; }
    if (!rec || !Array.isArray(rec.items)) continue;
    const at = rec.at || '';
    const present = new Set();
    for (const it of rec.items) {
      const key = String(it.organ);
      present.add(key);
      if (!per.has(key)) {
        per.set(key, { organ: it.organ, id: it.id, seen: 0, first: at, last: at, cleared: 0, clears: [], wasBad: false, badSince: null, badKind: null, kinds: {}, buckets: {} });
      }
      const o = per.get(key);
      o.seen += 1;
      o.last = at;
      o.kinds[it.kind] = (o.kinds[it.kind] || 0) + 1;
      o.buckets[it.bucket] = (o.buckets[it.bucket] || 0) + 1;
      o.id = it.id || o.id;
      if (BAD.has(String(it.kind))) {
        if (!o.wasBad) { o.wasBad = true; o.badSince = at; o.badKind = it.kind; }
        else o.badKind = it.kind;
      } else if (o.wasBad) {
        closeClear(o, at, 'judged-good');
      }
    }
    for (const [key, o] of per) {
      if (present.has(key)) continue;
      // absent from the plan also counts as bad -> good
      if (o.wasBad) closeClear(o, at, 'left-the-plan');
    }
  }

  function closeClear(o, at, how) {
    o.wasBad = false;
    o.cleared += 1;
    // what was dispatched to this organ between it going bad and this round
    const act = dispatches
      .filter((d) => String(d.cell) === String(o.id) && String(d.at) >= String(o.badSince || '') && String(d.at) <= String(at))
      .filter((d) => d.ok !== false)
      .pop() || null;
    // 2026-11-10 用户：「没有为什么失败那一句」——Reflexion 的反思文本就是这句。
    // 我们写不出模型的自由反思，只能写可核的原因：派了什么、派了没效、还是根本没派。
    const why = act
      ? 'cleared after a dispatch (' + (act.reason || 'no reason given') + ') at ' + act.at
      : 'cleared without any dispatch recorded between ' + String(o.badSince) + ' and ' + String(at) + ' (nobody did anything we can name)'
    o.clears.push({
      from: o.badSince,
      to: at,
      how,
      why,
      badKind: o.badKind,
      action: act ? { at: act.at, reason: act.reason || null, from: act.from || null } : null,
    });
    if (o.clears.length > MAX_CLEARS) o.clears = o.clears.slice(-MAX_CLEARS);
    o.badSince = null;
    o.badKind = null;
  }

  const organs = {};
  const needsUnderstanding = [];
  for (const [key, o] of per) {
    // what worked last time (null when it never cleared)
    const last = o.clears.length ? o.clears[o.clears.length - 1] : null;
    o.lastClear = last;
    o.lastGoodAction = last ? last.action : null;
    organs[key] = o;
    const mu = o.buckets['needs-understanding'] || 0;
    if (mu > 0) needsUnderstanding.push({ organ: o.organ, id: o.id, seen: o.seen, cleared: o.cleared, needsUnderstanding: mu });
  }
  needsUnderstanding.sort((a, b) => b.needsUnderstanding - a.needsUnderstanding);
  const out = { at: new Date().toISOString(), rounds: lines.length, organs, needsUnderstanding };
  mkdirSync(dirname(OUT), { recursive: true });
  writeFileSync(OUT, JSON.stringify(out, null, 2) + '\n', 'utf8');
  const n = Object.keys(organs).length;
  const nu = needsUnderstanding.length;
  const withClear = Object.values(organs).filter((o) => o.cleared > 0).length;
  console.log(`indexed ${lines.length} verdicts, ${n} organs, ${nu} with needs-understanding, ${withClear} with at least one clear`);
  console.log(`SIG {"state":0,"counts":[${n},${nu}]}`);
  return 0;
}

if (process.argv[1] && import.meta.url === new URL(`file:///${process.argv[1].replace(/\\/g, '/')}`).href) {
  process.exit(main());
}
