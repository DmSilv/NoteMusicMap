// Gera api/_lib/fingering_seed.json a partir da tabela do app (packages/afina_core/lib/violin_fingering.dart), para o painel do
// administrador mostrar o que já vem no app e poder corrigir. `node scripts/gen_fingering_seed.js` grava o arquivo;
// `node scripts/gen_fingering_seed.js --check` só confere (o teste api/fingering.test.js usa isto).
'use strict';
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..');
const DART = path.join(ROOT, 'packages', 'afina_core', 'lib', 'violin_fingering.dart');
const OUT = path.join(ROOT, 'api', '_lib', 'fingering_seed.json');

function build() {
  const src = fs.readFileSync(DART, 'utf8');
  const re = /_Entry\((\d+),\s*(true|false),\s*ScaleType\.(\w+),\s*(\d+),\s*\{([^}]*)\}(?:,\s*ottava:\s*\((\d+),\s*(\d+)\))?\)/g;
  const items = [];
  let m;
  while ((m = re.exec(src))) {
    const marks = {};
    for (const kv of m[5].matchAll(/(\d+):\s*'(\d)'/g)) marks[kv[1]] = kv[2];
    items.push({ pc: Number(m[1]), alt: m[2] === 'true', type: m[3], oct: Number(m[4]), marks, ottava: m[6] === undefined ? null : [Number(m[6]), Number(m[7])] });
  }
  return JSON.stringify({ v: 1, items }, null, 2) + '\n';
}

if (require.main === module) {
  const out = build();
  if (process.argv.includes('--check')) {
    const cur = fs.existsSync(OUT) ? fs.readFileSync(OUT, 'utf8') : '';
    if (cur !== out) { console.error('fingering_seed.json desatualizado: rode node scripts/gen_fingering_seed.js'); process.exit(1); }
    console.log('fingering_seed.json em dia');
  } else {
    fs.writeFileSync(OUT, out);
    console.log('fingering_seed.json atualizado (' + JSON.parse(out).items.length + ' escalas).');
  }
}
module.exports = { build, OUT };
