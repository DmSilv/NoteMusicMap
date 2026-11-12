// Enums que guardam o texto em português (valor constante): o campo vira privado e um getter traduz ao ler.
//   node scripts/i18n_fix_enums.js packages/afina_core lib
// Só mexe em enums que têm /*tr*/'...' nos valores (marcados por i18n_fix_const.js). O que sobrar de /*tr*/ fora de enum é listado.
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { readString, stringStartAt } = require('./lib/dart_strings');

function walk(d, out) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) walk(p, out); else if (e.name.endsWith('.dart')) out.push(p);
  }
  return out;
}

function matchClose(s, i) {
  const pairs = { '(': ')', '[': ']', '{': '}' };
  let d = 0;
  for (; i < s.length;) {
    if (stringStartAt(s, i)) { i = readString(s, i).end; continue; }
    if (s[i] === '/' && s[i + 1] === '/') { i = s.indexOf('\n', i); if (i < 0) return -1; continue; }
    const c = s[i];
    if (pairs[c]) d++; else if (c === ')' || c === ']' || c === '}') { d--; if (d === 0) return i; }
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
  return parts;
}

const leftovers = [];
for (const root of process.argv.slice(2)) {
  for (const file of walk(path.resolve(root), [])) {
    let src = fs.readFileSync(file, 'utf8');
    if (!src.includes('/*tr*/')) continue;
    const crlf = src.includes('\r\n'); if (crlf) src = src.replace(/\r\n/g, '\n');
    const enumRe = /\benum\s+(\w+)[^{]*\{/g;
    let m; const edits = []; const patched = new Set();
    while ((m = enumRe.exec(src))) {
      const open = m.index + m[0].length - 1;
      const close = matchClose(src, open);
      if (close < 0) continue;
      const body = src.slice(open + 1, close);
      if (!body.includes('/*tr*/')) continue;
      // valores: tudo antes do primeiro ';' de nível 0
      let semi = -1, d = 0;
      for (let i = 0; i < body.length;) {
        if (stringStartAt(body, i)) { i = readString(body, i).end; continue; }
        if (body[i] === '/' && body[i + 1] === '/') { i = body.indexOf('\n', i); continue; }
        if ('([{'.includes(body[i])) d++; else if (')]}'.includes(body[i])) d--;
        if (body[i] === ';' && d === 0) { semi = i; break; }
        i++;
      }
      if (semi < 0) continue;
      const values = body.slice(0, semi);
      const rest = body.slice(semi);
      const ctor = new RegExp('const\\s+' + m[1] + '\\s*\\(').exec(rest);
      if (!ctor) { leftovers.push(`${file}: enum ${m[1]} sem construtor const`); continue; }
      const cOpen = semi + ctor.index + ctor[0].length - 1;
      const cClose = matchClose(body, cOpen);
      const params = splitTop(body.slice(cOpen + 1, cClose));
      // índices de parâmetro que recebem /*tr*/ em algum valor
      const idx = new Set();
      const valRe = /(\w+)\s*\(/g; let vm;
      let vd = 0;
      for (let i = 0; i < values.length;) {
        if (stringStartAt(values, i)) { i = readString(values, i).end; continue; }
        if (values[i] === '/' && values[i + 1] === '/') { i = values.indexOf('\n', i); if (i < 0) break; continue; }
        if (values[i] === '/' && values[i + 1] === '*') { i = values.indexOf('*/', i + 2) + 2; continue; }
        const mm = /^[A-Za-z_]\w*\s*\(/.exec(values.slice(i));
        if (mm && vd === 0) {
          const op = i + mm[0].length - 1;
          const cl = matchClose(values, op);
          const args = splitTop(values.slice(op + 1, cl));
          args.forEach((a, k) => { if (a.includes('/*tr*/')) idx.add(k); });
          i = cl + 1; continue;
        }
        i++;
      }
      const fields = [];
      for (const k of idx) {
        const pm = /^\s*this\.(\w+)\s*$/.exec(params[k] || '');
        if (pm) fields.push(pm[1]); else leftovers.push(`${file}: enum ${m[1]} parâmetro ${k} (${(params[k] || '').trim()}) não é this.campo posicional`);
      }
      let nb = body;
      for (const f of fields) {
        nb = nb.replace(new RegExp('this\\.' + f + '\\b'), 'this._' + f);
        const decl = new RegExp('final\\s+String\\s+' + f + ';');
        if (!decl.test(nb)) { leftovers.push(`${file}: enum ${m[1]} sem "final String ${f};"`); continue; }
        nb = nb.replace(decl, `final String _${f};\n  String get ${f} => tr(_${f});`);
      }
      edits.push([open + 1, close, nb]); patched.add(m[1]);
    }
    edits.sort((a, b) => b[0] - a[0]);
    for (const [a, b, t] of edits) src = src.slice(0, a) + t + src.slice(b);
    // o que restou de /*tr*/ fora de enum
    for (const lm of src.matchAll(/\/\*tr\*\/('(?:[^'\\]|\\.)*')/g)) {
      const line = src.slice(0, lm.index).split('\n').length;
      leftovers.push(`${path.relative(process.cwd(), file)}:${line} ${lm[1]}`);
    }
    if (crlf) src = src.replace(/\n/g, '\r\n');
    fs.writeFileSync(file, src);
  }
}
console.log(leftovers.length ? 'Ainda a tratar à mão:\n' + leftovers.join('\n') : 'Nada sobrou.');
