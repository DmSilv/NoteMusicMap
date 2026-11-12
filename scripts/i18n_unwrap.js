// Tira o tr() de textos que não são para a pessoa ler (nomes técnicos, ids): `node scripts/i18n_unwrap.js lista.json`
// A lista é um JSON com os textos (como aparecem na chave, com {0}, {1}... no lugar das interpolações).
// tr('chave') vira 'chave'; tr('v{0}', [x]) vira 'v${x}'; /*tr*/'chave' vira 'chave'.
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { findGroups, groupKey, emit, readString, stringStartAt } = require('./lib/dart_strings');
const { ROOT, dartFiles } = require('./lib/i18n_rules');

const list = new Set(JSON.parse(fs.readFileSync(process.argv[2], 'utf8')));

function closeParen(s, i) {
  let d = 0;
  for (; i < s.length;) {
    if (stringStartAt(s, i)) { i = readString(s, i).end; continue; }
    const c = s[i];
    if ('([{'.includes(c)) d++; else if (')]}'.includes(c)) { d--; if (d === 0) return i; }
    i++;
  }
  return -1;
}
function splitTop(s) {
  const parts = []; let d = 0, cur = '';
  for (let i = 0; i < s.length;) {
    if (stringStartAt(s, i)) { const r = readString(s, i); cur += s.slice(i, r.end); i = r.end; continue; }
    const c = s[i];
    if ('([{'.includes(c)) d++; else if (')]}'.includes(c)) d--;
    if (c === ',' && d === 0) { parts.push(cur); cur = ''; } else cur += c;
    i++;
  }
  if (cur.trim()) parts.push(cur);
  return parts.map((p) => p.trim());
}
/** Texto Dart com ${arg} no lugar de cada {n}; usa $x quando o argumento é um nome simples. */
function interpolated(key, args) {
  const lit = emit(key.replace(/\{\d+\}/g, '\u0001'));
  let n = 0;
  return lit.replace(/\u0001(.?)/g, (m, next) => { const a = args[n++]; return (/^[A-Za-z_]\w*$/.test(a) && !/\w/.test(next) ? '$' + a : '${' + a + '}') + next; });
}

let total = 0;
for (const f of dartFiles()) {
  let src = fs.readFileSync(f, 'utf8'); const crlf = src.includes('\r\n'); if (crlf) src = src.replace(/\r\n/g, '\n');
  let changed = 0;
  const edits = [];
  const visit = (code, base) => {
    for (const g of findGroups(code)) {
      const { key } = groupKey(g);
      const pre = code.slice(0, g.start);
      const mTr = /\btr\(\s*$/.exec(pre);
      const mMark = /\/\*tr\*\/$/.exec(pre);
      if (list.has(key) && (mTr || mMark)) {
        if (mMark) { edits.push([base + g.start - 6, base + g.start, '']); changed++; }
        else {
          const open = base + mTr.index + 2; // posição do "("
          const full = code; // base só vale no nível raiz
          const close = closeParen(full, mTr.index + 2);
          let rest = full.slice(g.end, close).trim();
          let args = [];
          if (rest.startsWith(',')) { rest = rest.slice(1).trim(); if (rest.startsWith('[')) args = splitTop(rest.slice(1, rest.lastIndexOf(']'))); }
          const lit = args.length ? interpolated(key, args) : emit(key);
          edits.push([base + mTr.index, base + close + 1, lit]); changed++;
        }
      }
    }
  };
  visit(src, 0);
  edits.sort((a, b) => b[0] - a[0]);
  for (const [a, b, t] of edits) src = src.slice(0, a) + t + src.slice(b);
  if (changed) { if (crlf) src = src.replace(/\n/g, '\r\n'); fs.writeFileSync(f, src); total += changed; console.log(path.relative(ROOT, f), changed); }
}
console.log('Textos sem tr():', total);
