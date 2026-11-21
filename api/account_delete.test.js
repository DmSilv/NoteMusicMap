// O usuário exclui a própria conta: `node --test api/account_delete.test.js`
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
const PROF = code(11), ALU = code(33);
const secret = (c, extra = '') => crypto.createHash('sha256').update('s' + c + extra).digest('hex');
const KEY = 'chave-admin-teste';
let ipN = 0;
function fakeRes() {
  const r = { headers: {}, statusCode: 0, body: '' };
  r.setHeader = (k, v) => { r.headers[k] = v; };
  r.end = (b) => { r.body = b; };
  r.json = () => JSON.parse(r.body);
  return r;
}
function mk() {
  hashes.clear(); memory.clear(); resetMem(); features.resetCache();
  const deps = { config: () => config({ ADMIN_KEY: KEY }), allowMemory: true, fetch: async () => ({ status: 200 }), now: () => 1_800_000_000_000 };
  return { l: link.makeHandler(deps), a: admin.makeHandler(deps) };
}
async function as(H, who, body, sec = secret(who)) {
  const res = fakeRes();
  await H.l({ method: 'POST', headers: { 'x-forwarded-for': '4.4.4.' + ++ipN }, body: { code: who, secret: sec, ...body }, socket: {} }, res);
  return res;
}
async function adm(H, body) {
  const res = fakeRes();
  await H.a({ method: 'POST', headers: { 'x-forwarded-for': '5.5.5.' + ++ipN, authorization: 'Bearer ' + KEY }, body, socket: {} }, res);
  return res;
}
async function setup() {
  const H = mk();
  for (const [who, nm] of [[PROF, 'Vinícius'], [ALU, 'Ana']]) await as(H, who, { action: 'sync', name: nm });
  await as(H, PROF, { action: 'link', role: 'teacher', other: ALU });
  return H;
}
const exists = async (H, c) => (await adm(H, { action: 'detail', code: c })).statusCode === 200;

test('sem confirmar ou com segredo errado nada é apagado', async () => {
  const H = await setup();
  assert.equal((await as(H, ALU, { action: 'account_delete' })).statusCode, 400);
  assert.notEqual((await as(H, ALU, { action: 'account_delete', confirm: true }, secret(ALU, 'errado'))).statusCode, 200);
  assert.equal(await exists(H, ALU), true);
});

test('o aluno exclui a conta: perfil some, o professor fica sem o vínculo', async () => {
  const H = await setup();
  const r = await as(H, ALU, { action: 'account_delete', confirm: true });
  assert.equal(r.statusCode, 200);
  assert.equal(await exists(H, ALU), false);
  const prof = (await as(H, PROF, { action: 'sync' })).json();
  assert.deepEqual(prof.asTeacher, []);
});

test('o professor exclui a conta: o aluno perde o vínculo e o perfil dele continua', async () => {
  const H = await setup();
  assert.equal((await as(H, PROF, { action: 'account_delete', confirm: true })).statusCode, 200);
  assert.equal(await exists(H, PROF), false);
  assert.equal(await exists(H, ALU), true);
  const alu = (await as(H, ALU, { action: 'sync' })).json();
  assert.deepEqual(alu.asStudent, []);
});

test('apaga também e-mail, chave de recuperação, listas de recursos, grupos e a cópia na nuvem', async () => {
  const H = await setup();
  await adm(H, { action: 'feature_grant', id: 'acervo', code: ALU });
  const g = (await adm(H, { action: 'group_save', name: 'Testadores' })).json().id;
  await adm(H, { action: 'group_member', id: g, code: ALU, on: true });
  // índices de e-mail e chave de recuperação, como a conta os grava
  const eh = 'hash-do-email', rk = 'hash-da-chave';
  const put = (key, f, v) => (hashes.get(key) || hashes.set(key, new Map()).get(key)).set(f, v);
  put(`u:${ALU}`, 'eh', eh); put(`u:${ALU}`, 'rk', rk);
  put('acct:em', eh, ALU); put('acct:rk', rk, ALU);
  put(`mi:${ALU}`, 'AG', '[1]'); put(`mm:${ALU}`, 'AG', '{"u":1}');
  assert.equal((await as(H, ALU, { action: 'account_delete', confirm: true })).statusCode, 200);
  assert.equal(hashes.get('acct:em')?.has(eh) || false, false);
  assert.equal(hashes.get('acct:rk')?.has(rk) || false, false);
  assert.equal(hashes.get(`mi:${ALU}`)?.size || 0, 0);
  assert.equal(hashes.get(`mm:${ALU}`)?.size || 0, 0);
  assert.equal(await exists(H, ALU), false);
});

test('o e-mail de outra pessoa que apontava para outro perfil não é apagado', async () => {
  const H = await setup();
  const put = (key, f, v) => (hashes.get(key) || hashes.set(key, new Map()).get(key)).set(f, v);
  put(`u:${ALU}`, 'eh', 'mesmo-hash');
  put('acct:em', 'mesmo-hash', PROF); // hoje o e-mail pertence a outro perfil
  await as(H, ALU, { action: 'account_delete', confirm: true });
  assert.equal(hashes.get('acct:em').get('mesmo-hash'), PROF);
});

test('o painel continua excluindo pela mesma rotina', async () => {
  const H = await setup();
  assert.equal((await adm(H, { action: 'delete', code: ALU, confirm: ALU })).statusCode, 200);
  assert.equal(await exists(H, ALU), false);
});
