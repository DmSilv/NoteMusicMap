// Confere o inglês do app: `node scripts/check_i18n.js` (roda também no CI).
//  1. todo texto em tr('...') (e literal marcado /*tr*/'...') do código tem tradução no dicionário (packages/afina_core/lib/i18n_en*.dart);
//  2. a tradução usa os mesmos marcadores {0}, {1}... do original;
//  3. a tradução não ficou com cara de português (acentos de português: ã õ ç);
//  4. entradas do dicionário que nenhum texto do código usa (sobra) são avisadas.
//  `--list` imprime os textos que ainda faltam, um por linha, com arquivo:linha.
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { findGroups, groupKey } = require('./lib/dart_strings');
const { ROOT, dartFiles } = require('./lib/i18n_rules');

const DICT_DIR = path.join(ROOT, 'packages', 'afina_core', 'lib');

/** Textos do código: Map chave -> [{file, line}]. */
function extractKeys() {
  const keys = new Map();
  const add = (key, file, line) => { if (!keys.has(key)) keys.set(key, []); keys.get(key).push({ file, line }); };
  const visit = (code, file, baseLine) => {
    for (const g of findGroups(code)) {
      const before = code.slice(Math.max(0, g.start - 12), g.start);
      const line = baseLine + code.slice(0, g.start).split('\n').length - 1;
      const { key } = groupKey(g);
      if (/\btr\(\s*$/.test(before) || /\/\*tr\*\/$/.test(before)) add(key, file, line);
      for (const l of g.lits) for (const p of l.parts) if (p.t === 'expr' && /['"]/.test(p.code)) visit(p.code, file, line);
    }
  };
  for (const f of dartFiles()) {
    const rel = path.relative(ROOT, f).split(path.sep).join('/');
    visit(fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n'), rel, 1);
  }
  return keys;
}

/** Dicionário: Map pt -> en, lido dos arquivos i18n_en*.dart (pares de textos: chave, valor). */
function readDictionary() {
  const dict = new Map(); const dupes = [];
  const files = fs.readdirSync(DICT_DIR).filter((n) => /^i18n_en_.+\.dart$/.test(n)).sort();
  for (const n of files) {
    const src = fs.readFileSync(path.join(DICT_DIR, n), 'utf8').replace(/\r\n/g, '\n');
    const gs = findGroups(src).map((g) => groupKey(g).key);
    for (let i = 0; i + 1 < gs.length; i += 2) {
      if (dict.has(gs[i])) dupes.push(gs[i]);
      dict.set(gs[i], gs[i + 1]);
    }
    if (gs.length % 2) dupes.push(`(${n}: número ímpar de textos, algum par ficou incompleto)`);
  }
  return { dict, dupes, files };
}

const slotSet = (t) => new Set(t.match(/\{\d+\}/g) || []);
const PT_LOOK = /[ãõçÃÕÇ]|\b(você|não|para o|para a|uma|então|aqui)\b/i;

function main() {
  const keys = extractKeys();
  const { dict, dupes } = readDictionary();
  const missing = [], badSlots = [], looksPt = [], empty = [], dropped = [];
  for (const [k, where] of keys) {
    const v = dict.get(k);
    if (v === undefined) { missing.push([k, where[0]]); continue; }
    const ks = slotSet(k), vs = slotSet(v);
    if ([...vs].some((x) => !ks.has(x))) badSlots.push([k, v]);
    else if ([...ks].some((x) => !vs.has(x))) dropped.push([k, v]);
    if (PT_LOOK.test(v)) looksPt.push([k, v]);
  }
  if (process.argv.includes('--dropped')) { dropped.forEach(([k, v]) => console.log(JSON.stringify(k) + ' -> ' + JSON.stringify(v))); return; }
  const unused = [...dict.keys()].filter((k) => !keys.has(k));
  if (process.argv.includes('--list')) {
    for (const [k, w] of missing) console.log(`${w.file}:${w.line}\t${JSON.stringify(k)}`);
    return;
  }
  console.log(`Inglês: ${keys.size} textos no código, ${dict.size} traduções.`);
  let bad = 0;
  const show = (title, arr, fmt) => { if (arr.length) { bad += arr.length; console.log(`\n${title} (${arr.length}):`); arr.slice(0, 40).forEach((x) => console.log('  - ' + fmt(x))); if (arr.length > 40) console.log(`  ... e mais ${arr.length - 40}`); } };
  show('Sem tradução', missing, ([k, w]) => `${w.file}:${w.line}  ${JSON.stringify(k)}`);
  show('Marcadores {n} que o original não tem', badSlots, ([k, v]) => `${JSON.stringify(k)} -> ${JSON.stringify(v)}`);
  show('Tradução com cara de português', looksPt, ([k, v]) => `${JSON.stringify(k)} -> ${JSON.stringify(v)}`);
  show('Texto repetido no dicionário', dupes, (k) => JSON.stringify(k));
  if (unused.length) console.log(`\nAviso: ${unused.length} entradas do dicionário não são usadas pelo código.` + (unused.length <= 15 ? '\n  ' + unused.map((k) => JSON.stringify(k)).join('\n  ') : ''));
  if (bad) { console.log(`\n${bad} problema(s).`); process.exit(1); }
  console.log('Tudo certo.');
}

if (require.main === module) main();
module.exports = { extractKeys, readDictionary };
