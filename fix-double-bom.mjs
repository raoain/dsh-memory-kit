// fix-double-bom.mjs -- strip a duplicated UTF-8 BOM from a file.
//
// 2026-11-08: healing watchdog.ps1, the patch script read the file (which already had a BOM)
// and wrote '\ufeff' + text, producing EF BB BF EF BB BF. PowerShell then failed to parse
// `param()` with "line 10: ( expecting an expression" -- a double BOM breaks the parser in a
// way that points at innocent code.
//
// Rule: when writing a .ps1 whose existing BOM state you do not know, strip first, then add
// exactly one.

import { readFileSync, writeFileSync } from 'node:fs'

const P = process.argv[2]
if (!P) { console.error('usage: node fix-double-bom.mjs <file>'); process.exit(2) }

let buf = readFileSync(P)
let stripped = 0
while (buf.length >= 3 && buf[0] === 0xef && buf[1] === 0xbb && buf[2] === 0xbf) {
  buf = buf.subarray(3)
  stripped++
}
if (stripped === 0) {
  console.log(`${P}: no BOM found, adding one`)
  writeFileSync(P, Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), buf]))
  process.exit(0)
}
if (stripped > 1) {
  console.log(`${P}: stripped ${stripped} BOMs, writing back one`)
  writeFileSync(P, Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), buf]))
} else {
  console.log(`${P}: exactly one BOM, nothing to do`)
}
