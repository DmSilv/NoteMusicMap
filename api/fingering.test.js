// Dedilhado do violino editado no painel: validação, notas de cada escala, ações do admin e a leitura pública.
// `node --test api/fingering.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const admin = require('./admin');
const pub = require('./fingering');
const fing = require('./_lib/fingering');
const seedGen = require('../scripts/gen_fingering_seed');
const fs = require('node:fs');
const { config } = require('./_lib/config');
const { hashes, memory } = require('./_lib/store');
const { resetMem } = require('./_lib/store_cmd');

const KEY = 'chave-de-admin-de-teste';
const NOW = 1_800_000_000_000;
let ipN = 0;
const fakeRes = () => {
  const r = { headers: {}, statusCode: 0, body: '' };
  r.setHeader = (k, v) => { r.headers[k] = v; };
  r.end = (b) => { r.body = b; };
  r.json = () => JSON.parse(r.body);
  return r;
};
function mk() {
  hashes.clear();
  memory.clear();
  resetMem();
  const deps = { config: () => config({ ADMIN_KEY: KEY }), allowMemory: true, fetch: async () => ({ status: 200 }), now: () => NOW };
  return { a: admin.makeHandler(deps), p: pub.makeHandler(deps) };
}
async function adm(H, body, key = KEY) {
  const res = fakeRes();
  await H.a({ method: 'POST', headers: { 'x-forwarded-for': '7.7.7.' + ++ipN, authorization: 'Bearer ' + key }, body, socket: {} }, res);
  return res;
}
async function get(H, method = 'GET') {
  const res = fakeRes();
  await H.p({ method, headers: {}, socket: {} }, res);
  return res;
}

test('o seed do painel é o mesmo da tabela do app (rode node scripts/gen_fingering_seed.js se falhar)', () => {
  const cur = fs.readFileSync(seedGen.OUT, 'utf8');
  assert.equal(cur, seedGen.build());
});

test('toda escala do app passa na validação, sem aviso de corda solta', () => {
  const seed = JSON.parse(fs.readFileSync(seedGen.OUT, 'utf8')).items;
  assert.ok(seed.length >= 3);
  for (const s of seed) {
    const v = fing.validate(s);
    assert.equal(v.error, undefined, JSON.stringify(s));
    assert.deepEqual(v.warnings, [], JSON.stringify(s));
  }
});

test('nomes das notas: Dó menor melódica sobe com Lá e Si e desce com Si♭ e Lá♭; Sol♭ maior escreve Dó♭', () => {
  const nm = (pc, alt, type, oct) => fing.noteRows(pc, alt, type, oct).map((r) => r.name);
  assert.deepEqual(nm(0, false, 'melodicMinor', 1), ['Dó', 'Ré', 'Mi♭', 'Fá', 'Sol', 'Lá', 'Si', 'Dó', 'Si♭', 'Lá♭', 'Sol', 'Fá', 'Mi♭', 'Ré', 'Dó']);
  assert.deepEqual(nm(6, true, 'major', 1).slice(0, 8), ['Sol♭', 'Lá♭', 'Si♭', 'Dó♭', 'Ré♭', 'Mi♭', 'Fá', 'Sol♭']);
  assert.equal(nm(6, false, 'major', 1)[0], 'Fá♯');
  assert.equal(fing.noteRows(10, false, 'major', 3).length, 43);
  assert.equal(fing.noteRows(10, false, 'major', 3)[2].octave, 4); // Ré4
  assert.equal(fing.noteRows(10, false, 'major', 3)[2].open, true);
});

test('validação: tônica, tipo, oitavas, dedos, índices, 8va e outra grafia', () => {
  const ok = { pc: 3, alt: false, type: 'major', oct: 3, marks: { 0: '2', 9: '1' }, ottava: [18, 23] };
  assert.equal(fing.validate(ok).error, undefined);
  const bads = [
    { ...ok, pc: 12 }, { ...ok, pc: -1 }, { ...ok, type: 'xyz' }, { ...ok, oct: 0 }, { ...ok, oct: 5 },
    { ...ok, marks: { 43: '1' } }, { ...ok, marks: { 0: '5' } }, { ...ok, marks: { 0: 'a' } },
    { ...ok, ottava: [30, 20] }, { ...ok, ottava: [0, 99] }, { ...ok, alt: true },
  ];
  for (const bad of bads) assert.ok(fing.validate(bad).error, JSON.stringify(bad));
  assert.equal(fing.validate({ ...ok, marks: { 5: '' } }).entry.marks[5], undefined);
  assert.equal(fing.validate({ ...ok, ottava: null }).entry.ottava, null);
  assert.equal(fing.validate({ pc: 6, alt: true, type: 'major', oct: 3, marks: {} }).error, undefined);
});

test('um zero fora de corda solta vira aviso (e não impede salvar)', () => {
  const v = fing.validate({ pc: 3, alt: false, type: 'major', oct: 3, marks: { 1: '0' } });
  assert.equal(v.error, undefined);
  assert.equal(v.warnings.length, 1);
  assert.match(v.warnings[0], /corda solta/);
});

test('painel: lista o que vem do app, salva uma correção, a leitura pública a devolve e apagar volta ao app', async () => {
  const H = mk();
  assert.equal((await adm(H, { action: 'fing_list' }, 'errada')).statusCode, 401);
  const l0 = (await adm(H, { action: 'fing_list' })).json();
  assert.equal(l0.overrides.length, 0);
  assert.ok(l0.seed.length >= 3);
  assert.ok(l0.types.find((t) => t.id === 'major'));
  const g0 = await get(H);
  assert.equal(g0.statusCode, 200);
  assert.deepEqual(g0.json(), { v: 1, items: [] });
  assert.match(g0.headers['Cache-Control'], /s-maxage=300/);

  const rows = (await adm(H, { action: 'fing_rows', pc: 3, alt: false, type: 'major', oct: 3 })).json();
  assert.equal(rows.rows.length, 43);
  assert.equal(rows.source, 'app');
  assert.equal(rows.marks['0'], '2');
  assert.deepEqual(rows.ottava, [18, 23]);

  const body = { action: 'fing_save', pc: 3, alt: false, type: 'major', oct: 3, marks: { 0: '2', 9: '2' }, ottava: [18, 23] };
  const s = (await adm(H, body)).json();
  assert.equal(s.ok, true);
  assert.deepEqual(s.warnings, []);
  const g1 = (await get(H)).json();
  assert.equal(g1.items.length, 1);
  assert.equal(g1.items[0].marks['9'], '2');
  assert.deepEqual(g1.items[0].ottava, [18, 23]);
  const rows2 = (await adm(H, { action: 'fing_rows', pc: 3, alt: false, type: 'major', oct: 3 })).json();
  assert.equal(rows2.source, 'servidor');

  assert.equal((await adm(H, { action: 'fing_delete', pc: 3, alt: false, type: 'major', oct: 3 })).json().ok, true);
  assert.equal((await get(H)).json().items.length, 0);
  assert.equal((await adm(H, { action: 'fing_rows', pc: 3, alt: false, type: 'major', oct: 3 })).json().source, 'app');
});

test('painel: entrada inválida não grava nada', async () => {
  const H = mk();
  const bads = [
    { pc: 99, alt: false, type: 'major', oct: 3, marks: {} },
    { pc: 3, alt: false, type: 'major', oct: 3, marks: { 0: '9' } },
    { pc: 3, alt: true, type: 'major', oct: 3, marks: {} },
  ];
  for (const bad of bads) assert.equal((await adm(H, { action: 'fing_save', ...bad })).statusCode, 400);
  assert.equal((await get(H)).json().items.length, 0);
});

test('leitura pública: só GET, sem chave, e sem banco responde lista vazia', async () => {
  const H = mk();
  assert.equal((await get(H, 'POST')).statusCode, 405);
  const semBanco = pub.makeHandler({ config: () => config({}), fetch: async () => { throw new Error('rede'); } });
  const res = fakeRes();
  await semBanco({ method: 'GET', headers: {}, socket: {} }, res);
  assert.equal(res.statusCode, 200);
  assert.deepEqual(res.json().items, []);
});

test('uma escala salva ocupa um campo só no Redis', async () => {
  const H = mk();
  await adm(H, { action: 'fing_save', pc: 6, alt: true, type: 'major', oct: 3, marks: { 0: '2' }, ottava: [18, 26] });
  assert.equal(hashes.get(fing.HASH).size, 1);
});

test('a sugestão pelo molde reproduz as três escalas lidas (só o 1º dedo e o 8va ficam para a página)', () => {
  const sb = fing.suggest(10, false, 'major', 3);
  assert.equal(sb.error, undefined);
  const seed = JSON.parse(fs.readFileSync(seedGen.OUT, 'utf8')).items;
  const get = (pc, alt) => seed.find((s) => s.pc === pc && s.alt === alt && s.type === 'major' && s.oct === 3);
  assert.deepEqual(sb.marks, get(10, false).marks); // Si♭ maior: idêntico, inclusive as cordas soltas
  // Ré, Mi♭ e Sol♭ começam a partir da corda Ré: só o molde (sem o dedo da 1ª nota)
  for (const [pc, alt] of [[2, false], [3, false], [6, true]]) {
    const want = { ...get(pc, alt).marks };
    delete want['0'];
    assert.deepEqual(fing.suggest(pc, alt, 'major', 3).marks, want, 'pc ' + pc);
  }
  assert.ok(fing.suggest(0, false, 'major', 3).marks['21']);
});

test('sem molde (menor, 1 oitava...) a sugestão recusa, e o painel avisa', async () => {
  assert.ok(fing.suggest(9, false, 'naturalMinor', 3).error);
  assert.ok(fing.suggest(0, false, 'major', 2).error);
  const H = mk();
  assert.equal((await adm(H, { action: 'fing_suggest', pc: 0, alt: false, type: 'major', oct: 3 })).json().ok, true);
  assert.equal((await adm(H, { action: 'fing_suggest', pc: 0, alt: false, type: 'major', oct: 2 })).statusCode, 400);
  assert.equal((await adm(H, { action: 'fing_suggest', pc: 0, alt: false, type: 'major', oct: 3 }, 'errada')).statusCode, 401);
});

test('lista de tonalidades do painel: maiores com Sol♭ e Fá♯, menores com Ré♯ e Mi♭', async () => {
  const H = mk();
  const l = (await adm(H, { action: 'fing_list' })).json();
  const names = (a) => a.map((x) => x.name + (x.alt ? '*' : ''));
  assert.ok(names(l.tonics.major).includes('Fá♯') && names(l.tonics.major).includes('Sol♭*'));
  assert.ok(names(l.tonics.minor).includes('Mi♭') && names(l.tonics.minor).includes('Ré♯*'));
  assert.equal(l.tonics.major.filter((x) => !x.alt).length, 12);
});
