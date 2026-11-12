// Testes das chaves de recursos (liberação aos poucos): `node --test api/features.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const link = require('./link');
const admin = require('./admin');
const features = require('./_lib/features');
const { config } = require('./_lib/config');
const { hashes, memory } = require('./_lib/store');
const { resetMem } = require('./_lib/store_cmd');

const A = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
function code(seed) {
  let p = '';
  let x = seed;
  for (let i = 0; i < 7; i++) { p += A[x % 32]; x = Math.floor(x / 32) + 7 + i; }
  let s = 0;
  for (let i = 0; i < 7; i++) s += A.indexOf(p[i]) * (2 * i + 1);
  const c = p + A[s % 32];
  return `${c.slice(0, 4)}-${c.slice(4)}`;
}
const PROF = code(11), PROF2 = code(22), ALU = code(33), ALU2 = code(44);
const secret = (c) => crypto.createHash('sha256').update('s' + c).digest('hex');
const KEY = 'chave-de-admin-de-teste';
let ipN = 0;
function fakeRes() {
  const r = { headers: {}, statusCode: 0, body: '' };
  r.setHeader = (k, v) => { r.headers[k] = v; };
  r.end = (b) => { r.body = b; };
  r.json = () => JSON.parse(r.body);
  return r;
}
function mk(env = {}) {
  hashes.clear(); memory.clear(); resetMem(); features.resetCache();
  const cfg = config({ ADMIN_KEY: KEY, ...env });
  const deps = { config: () => cfg, allowMemory: true, fetch: async () => ({ status: 200 }), now: () => 1_800_000_000_000 };
  return { l: link.makeHandler(deps), a: admin.makeHandler(deps) };
}
async function as(H, who, body) {
  const res = fakeRes();
  await H.l({ method: 'POST', headers: { 'x-forwarded-for': '4.4.4.' + ++ipN }, body: { code: who, secret: secret(who), ...body }, socket: {} }, res);
  return res;
}
async function adm(H, body, key = KEY) {
  const res = fakeRes();
  await H.a({ method: 'POST', headers: { 'x-forwarded-for': '5.5.5.' + ++ipN, authorization: 'Bearer ' + key }, body, socket: {} }, res);
  return res;
}
async function setup(env) {
  const H = mk(env);
  for (const [who, nm] of [[PROF, 'Vinícius'], [PROF2, 'Outro'], [ALU, 'Ana'], [ALU2, 'Bia']]) await as(H, who, { action: 'sync', name: nm });
  await as(H, PROF, { action: 'link', role: 'teacher', other: ALU });
  await as(H, PROF, { action: 'link', role: 'teacher', other: ALU2 });
  return H;
}
const sync = async (H, who) => (await as(H, who, { action: 'sync' })).json();
const cardOf = async (H, id) => (await adm(H, { action: 'features' })).json().items.find((x) => x.id === id);

test('sem ninguém liberado: tudo desligado e os cartões aparecem no painel', async () => {
  const H = await setup();
  const r = (await adm(H, { action: 'features' })).json();
  assert.deepEqual(r.items.map((x) => x.id), ['acervo', 'aula_online', 'lembrete_escolha']);
  for (const c of r.items) { assert.equal(c.mode, 'list'); assert.equal(c.count, 0); }
  const s = await sync(H, PROF);
  assert.deepEqual(s.ff, []);
  assert.equal(s.lb, 0);
});

test('o painel exige a chave de admin', async () => {
  const H = await setup();
  assert.equal((await adm(H, { action: 'features' }, 'errada')).statusCode, 401);
  assert.equal((await adm(H, { action: 'feature_set', id: 'acervo', mode: 'all' }, 'errada')).statusCode, 401);
});

test('LIBRARY_TESTERS continua liberando o acervo (ponto de partida)', async () => {
  const H = await setup({ LIBRARY_TESTERS: PROF });
  const s = await sync(H, PROF);
  assert.equal(s.lb, 1);
  assert.ok(s.ff.includes('acervo'));
  assert.equal((await sync(H, PROF2)).lb, 0);
  const card = await cardOf(H, 'acervo');
  assert.deepEqual(card.legacy, [PROF]);
});

test('liberar um código: só ele ganha o recurso; o app recebe a lista (ff)', async () => {
  const H = await setup();
  assert.equal((await adm(H, { action: 'feature_grant', id: 'aula_online', code: PROF })).statusCode, 200);
  const s = await sync(H, PROF);
  assert.deepEqual(s.ff, ['aula_online']);
  assert.deepEqual((await sync(H, PROF2)).ff, []);
  assert.deepEqual((await sync(H, ALU)).ff, []);
  const card = await cardOf(H, 'aula_online');
  assert.equal(card.count, 1);
  assert.deepEqual(card.members, [PROF]);
});

test('liberar o professor junto com os alunos vinculados', async () => {
  const H = await setup();
  const r = await adm(H, { action: 'feature_grant', id: 'aula_online', code: PROF, students: true });
  assert.equal(r.json().changed, 3);
  assert.ok((await sync(H, ALU)).ff.includes('aula_online'));
  assert.ok((await sync(H, ALU2)).ff.includes('aula_online'));
  assert.deepEqual((await sync(H, PROF2)).ff, []);
});

test('tirar da lista desliga só aquele código', async () => {
  const H = await setup();
  await adm(H, { action: 'feature_grant', id: 'aula_online', code: PROF, students: true });
  await adm(H, { action: 'feature_revoke', id: 'aula_online', code: ALU });
  assert.deepEqual((await sync(H, ALU)).ff, []);
  assert.ok((await sync(H, ALU2)).ff.includes('aula_online'));
  assert.equal((await cardOf(H, 'aula_online')).count, 2);
});

test('"off" desliga para todos, inclusive quem está na lista, na hora', async () => {
  const H = await setup();
  await adm(H, { action: 'feature_grant', id: 'aula_online', code: PROF });
  assert.ok((await sync(H, PROF)).ff.includes('aula_online'));
  await adm(H, { action: 'feature_set', id: 'aula_online', mode: 'off' });
  assert.deepEqual((await sync(H, PROF)).ff, []);
  await adm(H, { action: 'feature_set', id: 'aula_online', mode: 'list' });
  assert.ok((await sync(H, PROF)).ff.includes('aula_online'));
});

test('"all" liga para todos', async () => {
  const H = await setup();
  await adm(H, { action: 'feature_set', id: 'aula_online', mode: 'all' });
  for (const who of [PROF, PROF2, ALU, ALU2]) assert.ok((await sync(H, who)).ff.includes('aula_online'));
});

test('porcentagem: sempre os mesmos usuários e a lista continua valendo', async () => {
  const H = await setup();
  await adm(H, { action: 'feature_set', id: 'aula_online', mode: 'pct', pct: 50 });
  const todos = [PROF, PROF2, ALU, ALU2];
  const ligados = [];
  for (const who of todos) if ((await sync(H, who)).ff.includes('aula_online')) ligados.push(who);
  assert.deepEqual(ligados, todos.filter((c) => features.bucket(c) < 50));
  // de novo: o mesmo resultado
  const de_novo = [];
  for (const who of todos) if ((await sync(H, who)).ff.includes('aula_online')) de_novo.push(who);
  assert.deepEqual(de_novo, ligados);
  // quem está fora do sorteio entra se for liberado pela lista
  const fora = todos.find((c) => features.bucket(c) >= 50);
  if (fora) {
    await adm(H, { action: 'feature_grant', id: 'aula_online', code: fora });
    assert.ok((await sync(H, fora)).ff.includes('aula_online'));
  }
  assert.ok(features.bucket(PROF) >= 0 && features.bucket(PROF) < 100);
});

test('o acervo passa a ser decidido pelas chaves: lista, aluno vê o professor e o servidor recusa o resto', async () => {
  const H = await setup();
  const item = { id: 'a1', k: 'a', f: 'Geral', t: 'Estudo', u: 'https://drive.google.com/file/d/x/view', ok: true };
  assert.equal((await as(H, PROF, { action: 'lib_put', item })).statusCode, 403);
  await adm(H, { action: 'feature_grant', id: 'acervo', code: PROF });
  assert.equal((await as(H, PROF, { action: 'lib_put', item })).statusCode, 200);
  assert.deepEqual((await sync(H, ALU)).lbT, [PROF]);
  assert.equal((await as(H, ALU, { action: 'lib_list', other: PROF })).statusCode, 200);
  await adm(H, { action: 'feature_set', id: 'acervo', mode: 'off' });
  assert.equal((await as(H, PROF, { action: 'lib_put', item })).statusCode, 403);
  assert.deepEqual((await sync(H, ALU)).lbT, []);
  assert.equal((await as(H, ALU, { action: 'lib_list', other: PROF })).statusCode, 403);
});

test('entradas inválidas são recusadas', async () => {
  const H = await setup();
  assert.equal((await adm(H, { action: 'feature_set', id: 'nao_existe', mode: 'all' })).statusCode, 400);
  assert.equal((await adm(H, { action: 'feature_set', id: 'acervo', mode: 'quase' })).statusCode, 400);
  assert.equal((await adm(H, { action: 'feature_set', id: 'acervo', mode: 'pct', pct: 0 })).statusCode, 400);
  assert.equal((await adm(H, { action: 'feature_set', id: 'acervo', mode: 'pct', pct: 100 })).statusCode, 400);
  assert.equal((await adm(H, { action: 'feature_grant', id: 'nao_existe', code: PROF })).statusCode, 400);
  assert.equal((await adm(H, { action: 'feature_grant', id: 'acervo', code: 'XXXX' })).statusCode, 400);
  assert.equal((await adm(H, { action: 'feature_grant', id: 'acervo', code: code(999) })).statusCode, 404);
});

test('toda mudança entra no registro do painel', async () => {
  const H = await setup();
  await adm(H, { action: 'feature_set', id: 'aula_online', mode: 'pct', pct: 10 });
  await adm(H, { action: 'feature_grant', id: 'aula_online', code: PROF, students: true });
  const log = (await adm(H, { action: 'log' })).json();
  const acoes = (log.items || log.log || []).map((x) => x.a);
  assert.ok(acoes.includes('feature_set'));
  assert.ok(acoes.includes('feature_grant'));
});

test('um app antigo ignora o campo novo: lb e lbT continuam existindo', async () => {
  const H = await setup({ LIBRARY_TESTERS: PROF });
  const s = await sync(H, PROF);
  assert.equal(s.lb, 1);
  assert.ok(Array.isArray(s.lbT));
});
