#!/usr/bin/env node
// Verifica se a documentação continua em dia com o código. Falha (código 1) se:
//   1. a referência gerada (docs/referencia) estiver desatualizada;
//   2. algum link relativo entre os documentos estiver quebrado;
//   3. um módulo do núcleo, um endpoint da API ou uma variável de ambiente existir no código
//      mas não for citado na documentação escrita à mão;
//   4. houver mais de 12 funções em api/ (limite da Vercel Hobby).
// Uso: node scripts/check_docs.js
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const ROOT = path.resolve(__dirname, '..');
const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');
const problems = [];

// 1) referência gerada em dia
const gen = spawnSync(process.execPath, [path.join(__dirname, 'gen_docs.js'), '--check'], { encoding: 'utf8' });
if (gen.status !== 0) problems.push(`Referência gerada desatualizada. Rode: node scripts/gen_docs.js\n${gen.stderr.trim()}`);

// documentos escritos à mão
const docsDir = path.join(ROOT, 'docs');
const manual = fs.readdirSync(docsDir).filter((f) => /^\d\d_.*\.md$/.test(f));
const expected = ['00_LEIA_PRIMEIRO', '01_ARQUITETURA', '02_APP_E_NUCLEO', '03_REGRAS_DE_NEGOCIO', '04_API_E_DADOS', '05_SEGURANCA_E_PRIVACIDADE', '06_TESTES', '07_PAINEL_ADMIN', '08_OPERACAO', '09_DECISOES', '10_GUIA_DE_MANUTENCAO', '11_HISTORICO'];
for (const e of expected) if (!manual.includes(`${e}.md`)) problems.push(`Falta o documento docs/${e}.md`);
const manualText = manual.map((f) => read(`docs/${f}`)).join('\n');

// 2) links relativos
const allDocs = [...manual.map((f) => `docs/${f}`), 'README.md'];
for (const rel of allDocs) {
  const dir = path.dirname(path.join(ROOT, rel));
  for (const m of read(rel).matchAll(/\]\(([^)#\s]+)(?:#[^)]*)?\)/g)) {
    const target = m[1];
    if (/^(https?:|mailto:)/.test(target)) continue;
    if (!fs.existsSync(path.resolve(dir, target))) problems.push(`${rel}: link quebrado → ${target}`);
  }
}

// 3) cobertura
const coreDir = path.join(ROOT, 'packages/afina_core/lib');
for (const f of fs.readdirSync(coreDir).filter((x) => x.endsWith('.dart') && x !== 'afina_core.dart')) {
  const name = f.replace(/\.dart$/, '');
  if (!read('docs/02_APP_E_NUCLEO.md').includes(name)) problems.push(`Módulo do núcleo sem menção em docs/02_APP_E_NUCLEO.md: ${name}`);
}
const apiDir = path.join(ROOT, 'api');
const handlers = fs.readdirSync(apiDir).filter((x) => x.endsWith('.js') && !x.endsWith('.test.js'));
for (const f of handlers) {
  const name = f.replace(/\.js$/, '');
  if (!read('docs/04_API_E_DADOS.md').includes(`/api/${name}`)) problems.push(`Endpoint sem menção em docs/04_API_E_DADOS.md: /api/${name}`);
}
const envNames = new Set();
for (const f of [...handlers.map((x) => `api/${x}`), ...fs.readdirSync(path.join(apiDir, '_lib')).filter((x) => x.endsWith('.js') && !x.endsWith('.test.js')).map((x) => `api/_lib/${x}`)]) {
  for (const m of read(f).matchAll(/env\.([A-Za-z][A-Za-z0-9_]+)/g)) envNames.add(m[1]);
}
const ops = read('docs/08_OPERACAO.md');
for (const v of envNames) {
  const base = v.replace(/_[A-Z]+$/, '_<ID>');
  if (!ops.includes(v) && !ops.includes(base) && !(v.startsWith('AI_RPM_') && ops.includes('AI_RPM_<ID>'))) problems.push(`Variável de ambiente sem menção em docs/08_OPERACAO.md: ${v}`);
}

// 4) limite de funções
if (handlers.length > 12) problems.push(`api/ tem ${handlers.length} funções; o plano Hobby da Vercel aceita no máximo 12.`);

if (problems.length) {
  console.error('Documentação com problemas:\n- ' + problems.join('\n- '));
  process.exit(1);
}
console.log(`Documentação ok: ${manual.length} documentos, referência em dia, links válidos, ${handlers.length}/12 funções.`);
