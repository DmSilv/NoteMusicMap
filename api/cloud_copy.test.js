// Cópia das fichas na nuvem com 1 aparelho (chave copia_nuvem + aceite): `node --test api/cloud_copy.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const account = require('./account');
const admin = require('./admin');
const link = require('./link');
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
const P1 = code(11111);
const S = ['a', 'b'].map((c) => c.repeat(64));
const KEY = 'chave-admin-teste';
let NOW = Date.UTC(2026, 10, 21, 15, 0, 0);
let ipN = 0;
function mk() {
  hashes.clear(); memory.clear(); resetMem(); features.resetCache();
  NOW = Date.UTC(2026, 10, 21, 15, 0, 0);
  const deps = { config: () => config({ ADMIN_KEY: KEY }), allowMemory: true, fetch: async () => { throw new Error('sem rede'); }, now: () => NOW };
  return { a: account.makeHandler(deps), l: link.makeHandler(deps), m: admin.makeHandler(deps) };
}
function fakeRes() {
  const r = { headers: {}, statusCode: 0, body: '' };
  r.setHeader = (k, v) => { r.headers[k] = v; };
  r.end = (b) => { r.body = b; };
  r.json = () => JSON.parse(r.body);
  return r;
}
async function call(h, body, headers = {}) {
  const res = fakeRes();
  await h({ method: 'POST', headers: { 'x-forwarded-for': '9.9.9.' + ++ipN, ...headers }, body, socket: {} }, res);
  return res;
}
const L = (H, s, body) => call(H.l, { code: P1, secret: s, ...body });
const adm = (H, body) => call(H.m, body, { authorization: 'Bearer ' + KEY });
async function setup(grant = true) {
  const H = mk();
  await L(H, S[0], { action: 'sync', name: 'Prof' });
  if (grant) assert.equal((await adm(H, { action: 'feature_grant', id: 'copia_nuvem', code: P1 })).statusCode, 200);
  return H;
}

test('sem a chave liberada: aceitar é recusado e o espelho continua desligado', async () => {
  const H = await setup(false);
  const r = await L(H, S[0], { action: 'cloud_set', on: true });
  assert.equal(r.statusCode, 403);
  assert.equal((await L(H, S[0], { action: 'mi_list' })).statusCode, 409);
  assert.equal((await L(H, S[0], { action: 'sync' })).json().ff.includes('copia_nuvem'), false);
});

test('chave liberada mas sem aceite: nada é guardado e nada custa; o app fica sabendo que pode oferecer', async () => {
  const H = await setup();
  const s = (await L(H, S[0], { action: 'sync' })).json();
  assert.ok(s.ff.includes('copia_nuvem'));
  assert.equal(s.cn, undefined);
  assert.equal(s.mo, undefined);
  assert.equal((await L(H, S[0], { action: 'mi_put', sec: 'AG', u: NOW, d: '[]' })).statusCode, 409);
  assert.equal((await L(H, S[0], { action: 'rev' })).json().mo, undefined);
});

test('liberada + aceite: o espelho funciona com um aparelho só (grava, lista, baixa)', async () => {
  const H = await setup();
  const on = await L(H, S[0], { action: 'cloud_set', on: true });
  assert.equal(on.statusCode, 200);
  assert.equal(on.json().cn, 1);
  const s = (await L(H, S[0], { action: 'sync' })).json();
  assert.equal(s.cn, 1);
  assert.equal(s.mo, 1);
  assert.equal((await L(H, S[0], { action: 'rev' })).json().mo, 1);
  NOW += 1000;
  assert.equal((await L(H, S[0], { action: 'mi_put', sec: 'S:K7QM-4TXD', u: NOW, d: '{"name":"Ana"}' })).statusCode, 200);
  assert.deepEqual((await L(H, S[0], { action: 'mi_list' })).json().secs, { 'S:K7QM-4TXD': { u: NOW } });
  assert.equal((await L(H, S[0], { action: 'mi_get', secs: ['S:K7QM-4TXD'] })).json().mitems['S:K7QM-4TXD'].d, '{"name":"Ana"}');
});

test('desligar apaga a cópia do servidor (um aparelho só) e religar começa vazio', async () => {
  const H = await setup();
  await L(H, S[0], { action: 'cloud_set', on: true });
  NOW += 1000;
  await L(H, S[0], { action: 'mi_put', sec: 'AG', u: NOW, d: '[1]' });
  const off = await L(H, S[0], { action: 'cloud_set', on: false });
  assert.equal(off.json().cn, 0);
  assert.equal((await L(H, S[0], { action: 'mi_list' })).statusCode, 409);
  assert.equal((await L(H, S[0], { action: 'sync' })).json().cn, undefined);
  await L(H, S[0], { action: 'cloud_set', on: true });
  assert.deepEqual((await L(H, S[0], { action: 'mi_list' })).json().secs, {});
});

test('o administrador desliga a chave: o espelho para na hora (a cópia não é lida nem gravada)', async () => {
  const H = await setup();
  await L(H, S[0], { action: 'cloud_set', on: true });
  assert.equal((await L(H, S[0], { action: 'mi_list' })).statusCode, 200);
  await adm(H, { action: 'feature_set', id: 'copia_nuvem', mode: 'off' });
  assert.equal((await L(H, S[0], { action: 'mi_list' })).statusCode, 409);
  assert.equal((await L(H, S[0], { action: 'rev' })).json().mo, undefined);
});

test('com 2 aparelhos o espelho segue valendo mesmo sem a chave e desligar a cópia não o apaga', async () => {
  const H = await setup(false);
  const pair = (await call(H.a, { action: 'pair_new', code: P1, secret: S[0] })).json().pair;
  assert.equal((await call(H.a, { action: 'pair_join', pair, secret: S[1] })).statusCode, 200);
  NOW += 1000;
  assert.equal((await L(H, S[0], { action: 'mi_put', sec: 'AG', u: NOW, d: '[2]' })).statusCode, 200);
  await L(H, S[0], { action: 'cloud_set', on: false });
  assert.deepEqual((await L(H, S[1], { action: 'mi_list' })).json().secs, { AG: { u: NOW } });
});
