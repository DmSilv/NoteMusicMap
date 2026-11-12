// Tira os `const` que deixaram de valer depois que textos viraram tr('...') (chamada de função não é constante).
//   node scripts/i18n_fix_const.js packages/afina_core
//   node scripts/i18n_fix_const.js .
// Roda `dart analyze` na pasta, e para cada erro de "constante" troca o `const` mais externo que o contém: em expressão, tira a
// palavra; em declaração (`static const x = ...`), vira `final`. Repete até acabar (um `final` novo pode quebrar outro `const`).
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { readString, stringStartAt, skipTrivia } = require('./lib/dart_strings');

const dir = path.resolve(process.argv[2] || '.');
const CONST_CODES = new Set(['const_eval_method_invocation', 'const_with_non_constant_argument', 'invalid_constant', 'non_constant_list_element', 'non_constant_map_element',
  'non_constant_map_key', 'non_constant_map_value', 'non_constant_set_element', 'const_initialized_with_non_constant_value', 'const_eval_type_bool',
  'const_eval_throws_exception', 'const_spread_expected_list_or_set', 'non_constant_case_expression', 'missing_const_in_list_literal',
  'const_constructor_param_type_mismatch', 'const_not_initialized', 'invalid_constant', 'const_eval_extension_method', 'const_eval_property_access',
  'non_constant_default_value', 'const_map_key_not_primitive_equality', 'const_set_element_not_primitive_equality', 'const_eval_type_num']);

function skipAngles(s, i) {
  if (s[i] !== '<') return i;
  let d = 0;
  for (; i < s.length; i++) { if (s[i] === '<') d++; else if (s[i] === '>') { d--; if (d === 0) return i + 1; } }
  return -1;
}
function closeBracket(s, i) {
  const open = s[i]; const pairs = { '(': ')', '[': ']', '{': '}' };
  if (!pairs[open]) return -1;
  let d = 0;
  for (; i < s.length;) {
    if (stringStartAt(s, i)) { i = readString(s, i).end; continue; }
    if (s[i] === '/' && (s[i + 1] === '/' || s[i + 1] === '*')) { i = skipTrivia(s, i); continue; }
    const c = s[i];
    if (c === '(' || c === '[' || c === '{') d++;
    else if (c === ')' || c === ']' || c === '}') { d--; if (d === 0) return i + 1; }
    i++;
  }
  return -1;
}
function endOfDeclaration(s, i) {
  for (; i < s.length;) {
    if (stringStartAt(s, i)) { i = readString(s, i).end; continue; }
    if (s[i] === '/' && (s[i + 1] === '/' || s[i + 1] === '*')) { i = skipTrivia(s, i); continue; }
    const c = s[i];
    if (c === '(' || c === '[' || c === '{') { const e = closeBracket(s, i); if (e < 0) return -1; i = e; continue; }
    if (c === ';') return i;
    i++;
  }
  return -1;
}

/** Todos os `const`: {start, kwEnd, end, decl}. */
function constExtents(s) {
  const out = [];
  const re = /\bconst\b/g;
  let m;
  // evita achar "const" dentro de texto/comentário: confere pelo leitor
  const dead = []; // trechos de texto e comentário
  for (let i = 0; i < s.length;) {
    if (s[i] === '/' && s[i + 1] === '/') { const e = s.indexOf('\n', i); dead.push([i, e < 0 ? s.length : e]); i = e < 0 ? s.length : e; continue; }
    if (s[i] === '/' && s[i + 1] === '*') { const e = skipTrivia(s, i); dead.push([i, e]); i = e; continue; }
    if (stringStartAt(s, i)) { const r = readString(s, i); dead.push([i, r.end]); i = r.end; continue; }
    i++;
  }
  const isDead = (p) => dead.some(([a, b]) => p >= a && p < b);
  while ((m = re.exec(s))) {
    if (isDead(m.index)) continue;
    const kwEnd = m.index + 5;
    let i = skipTrivia(s, kwEnd);
    const rest = s.slice(i, i + 200);
    const isDecl = /^(?:[\w<>,\s?.\[\]]+?\s+)?\w+\s*=(?!=)/.test(rest) && !/^[\w.]+\s*(<[^>]*>)?\s*\(/.test(rest);
    if (isDecl) { const e = endOfDeclaration(s, i); if (e > 0) out.push({ start: m.index, kwEnd, end: e, decl: true }); continue; }
    if (s[i] === '<') { i = skipAngles(s, i); if (i < 0) continue; i = skipTrivia(s, i); }
    else { const id = /^[A-Za-z_]\w*(\.\w+)*/.exec(s.slice(i)); if (id) { i += id[0].length; if (s[i] === '<') { i = skipAngles(s, i); if (i < 0) continue; } const dot = /^\.\w+/.exec(s.slice(i)); if (dot) i += dot[0].length; } }
    if (!'([{'.includes(s[i])) continue;
    const e = closeBracket(s, i);
    if (e > 0) out.push({ start: m.index, kwEnd, end: e, decl: false });
  }
  return out;
}

function analyze() {
  const win = process.platform === 'win32';
  const cmd = 'dart';
  const args = ['analyze', '--format=machine'];
  const r = spawnSync(cmd, args, { cwd: dir, encoding: 'utf8', shell: win, maxBuffer: 64 * 1024 * 1024 });
  const lines = (r.stdout || '').split(/\r?\n/).filter((l) => l.startsWith('ERROR|') || l.startsWith('WARNING|') || l.startsWith('INFO|'));
  return lines.map((l) => {
    const p = l.split('|');
    return { sev: p[0], code: p[2].toLowerCase(), file: p[3].split('\\\\').join('\\'), line: +p[4], col: +p[5], len: +p[6], msg: p.slice(7).join('|') };
  });
}

const reverted = [];
for (let round = 1; round <= 12; round++) {
  const errs = analyze().filter((e) => e.sev === 'ERROR');
  const constErrs = errs.filter((e) => CONST_CODES.has(e.code));
  const other = errs.filter((e) => !CONST_CODES.has(e.code));
  console.log(`rodada ${round}: ${errs.length} erros (${constErrs.length} de const, ${other.length} outros)`);
  if (!constErrs.length) {
    const byCode = {}; other.forEach((e) => { byCode[e.code] = (byCode[e.code] || 0) + 1; });
    console.log('restam:', byCode);
    if (other.length) fs.writeFileSync(path.join(dir, '.i18n_other_errors.txt'), other.map((e) => `${e.file}:${e.line}:${e.col} ${e.code} ${e.msg}`).join('\n'));
    break;
  }
  const byFile = new Map();
  for (const e of constErrs) { if (!byFile.has(e.file)) byFile.set(e.file, []); byFile.get(e.file).push(e); }
  for (const [file, list] of byFile) {
    let src = fs.readFileSync(file, 'utf8'); const crlf = src.includes('\r\n'); if (crlf) src = src.replace(/\r\n/g, '\n');
    const lineStarts = [0]; for (let i = 0; i < src.length; i++) if (src[i] === '\n') lineStarts.push(i + 1);
    const ext = constExtents(src);
    const fixes = new Map(); // start -> extent
    const revert = [];
    for (const e of list) {
      const off = lineStarts[e.line - 1] + e.col - 1;
      const inside = ext.filter((x) => off >= x.start && off < x.end);
      if (!inside.length) { revert.push({ file, off }); continue; }
      inside.sort((a, b) => a.start - b.start);
      const x = inside[0]; // o mais externo
      fixes.set(x.start, x);
    }
    // Lista de edições [início, fim, texto novo]; aplicadas de trás para frente para não mexer nas posições.
    const edits = [];
    for (const x of fixes.values()) {
      if (x.decl) edits.push([x.start, x.kwEnd, 'final']);
      else { let e = x.kwEnd; while (src[e] === ' ' || src[e] === '\n') e++; edits.push([x.start, e, '']); }
    }
    // Constante implícita (valor de enum, parâmetro com padrão): volta ao texto puro marcado com /*tr*/; a tela traduz ao mostrar.
    for (const r of revert) {
      const m = /^tr\(/.exec(src.slice(r.off, r.off + 3));
      if (!m) { console.log('sem como reverter:', file, r.off, JSON.stringify(src.slice(r.off, r.off + 40))); continue; }
      const open = r.off + 2;
      const end = closeBracket(src, open);
      const inner = src.slice(open + 1, end - 1).trim();
      const lit = stringStartAt(inner, 0) ? readString(inner, 0) : null;
      if (!lit || lit.end !== inner.length) { console.log('tr com argumentos em const implícito:', file, r.off, inner.slice(0, 60)); reverted.push({ file, off: r.off, manual: true }); continue; }
      edits.push([r.off, end, '/*tr*/' + inner]);
      reverted.push({ file, off: r.off, text: inner });
    }
    edits.sort((a, b) => b[0] - a[0]);
    for (const [a, b, t] of edits) src = src.slice(0, a) + t + src.slice(b);
    if (crlf) src = src.replace(/\n/g, '\r\n');
    fs.writeFileSync(file, src);
  }
}
if (reverted.length) {
  const rel = reverted.map((r) => `${path.relative(dir, r.file)} ${r.manual ? 'MANUAL' : r.text}`).join('\n');
  fs.writeFileSync(path.join(dir, '.i18n_reverted.txt'), rel);
  console.log(`${reverted.length} textos voltaram a literal marcado /*tr*/ (lista em .i18n_reverted.txt)`);
}
