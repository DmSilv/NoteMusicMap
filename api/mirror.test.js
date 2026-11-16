// Espelho da conta entre aparelhos, sem rede: `node --test api/mirror.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const account = require('./account');
const link = require('./link');
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
const P1 = code(11111);
const S = ['a', 'b', 'c'].map((c) => c.repeat(64));
let NOW = Date.UTC(2026, 10, 14, 15, 0, 0);
let ipN = 0;
function mk() {
  hashes.clear();
  memory.clear();
  resetMem();
  NOW = Date.UTC(2026, 10, 14, 15, 0, 0);
  const deps = { config: () => config({}), allowMemory: true, fetch: async () => { throw new Error('sem rede'); }, now: () => NOW };
  return { a: account.makeHandler(deps), l: link.makeHandler(deps) };
}
function fakeRes() {
  const r = { headers: {}, statusCode: 0, body: '' };
  r.setHeader = (k, v) => { r.headers[k] = v; };
  r.end = (b) => { r.body = b; };
  r.json = () => JSON.parse(r.body);
  return r;
}
async function call(h, body) {
  const res = fakeRes();
  await h({ method: 'POST', headers: { 'x-forwarded-for': '9.9.9.' + ++ipN }, body, socket: {} }, res);
  return res;
}
const L = (H, s, body) => call(H.l, { code: P1, secret: s, ...body });
async function twoDevices() {
  const H = mk();
  await L(H, S[0], { action: 'sync' });
  const pair = (await call(H.a, { action: 'pair_new', code: P1, secret: S[0] })).json().pair;
  assert.equal((await call(H.a, { action: 'pair_join', pair, secret: S[1] })).statusCode, 200);
  return H;
}

test('com um aparelho só o espelho está desligado e a consulta barata não ganha campos', async () => {
  const H = mk();
  await L(H, S[0], { action: 'sync' });
  const r = await L(H, S[0], { action: 'mi_list' });
  assert.equal(r.statusCode, 409);
  assert.equal(r.json().error, 'mirror_off');
  assert.equal((await L(H, S[0], { action: 'mi_put', sec: 'AG', u: NOW, d: '[]' })).statusCode, 409);
  const rev = (await L(H, S[0], { action: 'rev' })).json();
  assert.equal(rev.mo, undefined);
  assert.equal(rev.mr, undefined);
});

test('com 2 aparelhos: um grava, o outro vê a revisão mudar, lista e baixa', async () => {
  const H = await twoDevices();
  const rev0 = (await L(H, S[1], { action: 'rev' })).json();
  assert.equal(rev0.mo, 1);
  assert.equal(rev0.mr, 0);
  NOW += 1000;
  const put = await L(H, S[0], { action: 'mi_put', sec: 'S:K7QM-4TXD', u: NOW, d: '{"name":"Ana","tasks":[1,2,3]}' });
  assert.equal(put.statusCode, 200);
  const rev1 = (await L(H, S[1], { action: 'rev' })).json();
  assert.ok(rev1.mr > rev0.mr, 'o outro aparelho vê que mudou, sem chamada extra');
  const list = (await L(H, S[1], { action: 'mi_list' })).json();
  assert.deepEqual(list.secs, { 'S:K7QM-4TXD': { u: NOW } });
  const got = (await L(H, S[1], { action: 'mi_get', secs: ['S:K7QM-4TXD', 'nao-existe'] })).json();
  assert.equal(got.mitems['S:K7QM-4TXD'].d, '{"name":"Ana","tasks":[1,2,3]}');
  assert.equal(got.mitems['nao-existe'], undefined);
});

test('versão mais antiga não sobrescreve a mais nova (pedido atrasado)', async () => {
  const H = await twoDevices();
  NOW += 5000;
  await L(H, S[0], { action: 'mi_put', sec: 'AG', u: NOW, d: '["novo"]' });
  const old = await L(H, S[1], { action: 'mi_put', sec: 'AG', u: NOW - 3000, d: '["velho"]' });
  assert.equal(old.statusCode, 200);
  assert.equal(old.json().stale, true);
  const got = (await L(H, S[0], { action: 'mi_get', secs: ['AG'] })).json();
  assert.equal(got.mitems.AG.d, '["novo"]');
});

test('apagar deixa uma marca; a seção volta a existir se alguém gravar uma versão mais nova', async () => {
  const H = await twoDevices();
  NOW += 1000;
  await L(H, S[0], { action: 'mi_put', sec: 'S:i:abc', u: NOW, d: '{"name":"Local"}' });
  NOW += 1000;
  assert.equal((await L(H, S[0], { action: 'mi_del', sec: 'S:i:abc', u: NOW })).statusCode, 200);
  const list = (await L(H, S[1], { action: 'mi_list' })).json();
  assert.deepEqual(list.secs['S:i:abc'], { u: NOW, x: 1 });
  const got = (await L(H, S[1], { action: 'mi_get', secs: ['S:i:abc'] })).json();
  assert.equal(got.mitems['S:i:abc'].x, 1);
  assert.equal(got.mitems['S:i:abc'].d, undefined);
  NOW += 1000;
  await L(H, S[1], { action: 'mi_put', sec: 'S:i:abc', u: NOW, d: '{"name":"De volta"}' });
  assert.equal((await L(H, S[0], { action: 'mi_list' })).json().secs['S:i:abc'].x, undefined);
});

test('só o dono da conta mexe no espelho', async () => {
  const H = await twoDevices();
  assert.equal((await L(H, S[2], { action: 'mi_list' })).statusCode, 403);
  assert.equal((await L(H, S[2], { action: 'mi_put', sec: 'AG', u: NOW, d: '[]' })).statusCode, 403);
});

test('limites: nome de seção, tamanho, versão do futuro, seções demais e tamanho total', async () => {
  const H = await twoDevices();
  NOW += 1000;
  const put = (sec, d, u) => L(H, S[0], { action: 'mi_put', sec, u: u ?? NOW, d });
  assert.equal((await put('../x', '{}')).statusCode, 400);
  assert.equal((await put('a b', '{}')).statusCode, 400);
  assert.equal((await put('x'.repeat(65), '{}')).statusCode, 400);
  assert.equal((await put('AG', 'y'.repeat(120001))).statusCode, 400, 'seção grande demais (e o pedido nem passa)');
  assert.equal((await put('AG', '{}', NOW + 3 * 86400000)).statusCode, 400, 'versão do futuro');
  assert.equal((await put('AG', '{}', 0)).statusCode, 400);
  assert.equal((await put('AG', 5)).statusCode, 400);
  for (let i = 0; i < 400; i++) await put('S:i:' + i, '{}', NOW + i);
  assert.equal((await put('S:i:novo', '{}')).statusCode, 400, 'passou de 400 seções');
  assert.equal((await put('S:i:3', '{"ok":1}', NOW + 9999)).statusCode, 200, 'trocar uma que já existe continua valendo');
});

test('tamanho total da conta tem teto', async () => {
  const H = await twoDevices();
  NOW += 1000;
  const big = 'z'.repeat(119000);
  let last = 0;
  for (let i = 0; i < 40; i++) last = (await L(H, S[0], { action: 'mi_put', sec: 'B:' + i, u: NOW + i, d: big })).statusCode;
  assert.equal(last, 400, 'passou de 4 MB no total');
});

test('voltando a 1 aparelho o espelho é apagado e deixa de valer', async () => {
  const H = await twoDevices();
  NOW += 1000;
  await L(H, S[0], { action: 'mi_put', sec: 'AG', u: NOW, d: '["x"]' });
  const other = (await call(H.a, { action: 'devices', code: P1, secret: S[0] })).json().devices.find((d) => !d.me).id;
  assert.equal((await call(H.a, { action: 'device_remove', code: P1, secret: S[0], id: other })).statusCode, 200);
  assert.equal((await L(H, S[0], { action: 'mi_list' })).statusCode, 409);
  const pair = (await call(H.a, { action: 'pair_new', code: P1, secret: S[0] })).json().pair;
  await call(H.a, { action: 'pair_join', pair, secret: S[2] });
  const list = (await L(H, S[0], { action: 'mi_list' })).json();
  assert.deepEqual(list.secs, {}, 'o espelho antigo não volta');
  assert.equal(list.mr, 0);
});

test('limite de gravações por hora', async () => {
  const H = await twoDevices();
  NOW += 1000;
  let last = 0;
  for (let i = 0; i < 605; i++) last = (await L(H, S[0], { action: 'mi_put', sec: 'AG', u: NOW + i, d: '[]' })).statusCode;
  assert.equal(last, 429);
});
