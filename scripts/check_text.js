#!/usr/bin/env node
// Trava da "dieta de texto": conta os textos fixos de tela (Text('...')) com mais de MAX_CHARS
// caracteres em lib/ui. Falha se houver MAIS do que o teto (LIMIT), para o app não voltar a encher
// de parágrafo. O teto só pode descer: quando você encurtar textos, baixe o LIMIT aqui.
// Texto longo de verdade vai para o "?" (HelpButton / Help em lib/ui/widgets.dart).
// Uso: node scripts/check_text.js
'use strict';

const fs = require('node:fs');
const path = require('node:path');

const MAX_CHARS = 110;
const LIMIT = 19; // teto atual (eram 37 antes da dieta de 11/2026)
const DIR = path.resolve(__dirname, '..', 'lib', 'ui');

const found = [];
for (const f of fs.readdirSync(DIR).filter((x) => x.endsWith('.dart'))) {
  const src = fs.readFileSync(path.join(DIR, f), 'utf8');
  const re = /Text\(\s*((?:'[^'\n]*'\s*)+|(?:"[^"\n]*"\s*)+)/g;
  let m;
  while ((m = re.exec(src))) {
    const t = [...m[1].matchAll(/'([^'\n]*)'|"([^"\n]*)"/g)].map((x) => x[1] || x[2]).join('');
    if (t.length > MAX_CHARS) found.push({ file: f, line: src.slice(0, m.index).split('\n').length, len: t.length, text: t.slice(0, 70) });
  }
}

if (found.length > LIMIT) {
  console.error(`Textos de tela com mais de ${MAX_CHARS} caracteres: ${found.length} (teto ${LIMIT}). Encurte ou mova para o "?".`);
  for (const x of found) console.error(`  lib/ui/${x.file}:${x.line} [${x.len}] ${x.text}…`);
  process.exit(1);
}
console.log(`Texto ok: ${found.length} textos longos (teto ${LIMIT}).`);
