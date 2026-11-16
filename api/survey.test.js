// Pesquisa rápida no painel: quem respondeu (perfil), de qual aparelho; `node --test api/survey.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const link = require('./link');
const admin = require('./admin');
const feedback = require('./feedback');
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
const ANA = code(11111);
const secret = (c) => crypto.createHash('sha256').update('s' + c).digest('hex');
const KEY = 'chave-de-admin-de-teste';
let NOW = 1_800_000_000_000;
let ipN = 0;
function fakeRes() {
  const r = { headers: {}, statusCode: 0, body: '' };
  r.setHeader = (k, v) => { r.headers[k] = v; };
  r.end = (b) => { r.body = b; };
  r.json = () => JSON.parse(r.body);
  return r;
}
function mk() {
  hashes.clear();
  memory.clear();
  resetMem();
  NOW = 1_800_000_000_000;
  const deps = { config: () => config({ ADMIN_KEY: KEY, FEEDBACK_ADMIN_KEY: 'fk' }), allowMemory: true, fetch: async () => ({ status: 200 }), now: () => NOW };
  return { l: link.makeHandler(deps), a: admin.makeHandler(deps), f: feedback.makeHandler(deps) };
}
async function fb(H, dev, body) {
  const res = fakeRes();
  await H.f({ method: 'POST', headers: { 'x-forwarded-for': '4.4.4.' + ++ipN, 'x-device-id': dev }, body, socket: {} }, res);
  return res;
}
async function adm(H, body) {
  const res = fakeRes();
  await H.a({ method: 'POST', headers: { 'x-forwarded-for': '5.5.5.' + ++ipN, authorization: 'Bearer ' + KEY }, body, socket: {} }, res);
  return res;
}
async function profile(H, c, name) {
  const res = fakeRes();
  await H.l({ method: 'POST', headers: { 'x-forwarded-for': '6.6.6.' + ++ipN }, body: { action: 'sync', code: c, secret: secret(c), name }, socket: {} }, res);
}

test('resposta nova leva o perfil e aparece no painel com o nome e o aparelho', async () => {
  const H = mk();
  await profile(H, ANA, 'Ana');
  assert.equal((await fb(H, 'dev-ana', { kind: 'survey', qid: 'mais_usa', answer: 'Afinador', version: '1.0', platform: 'web', profile: ANA })).statusCode, 200);
  const r = (await adm(H, { action: 'survey' })).json();
  assert.equal(r.rows.length, 1);
  assert.equal(r.rows[0].code, ANA);
  assert.equal(r.rows[0].who.name, 'Ana');
  assert.equal(r.rows[0].q, 'mais_usa');
  assert.equal(r.rows[0].a, 'Afinador');
  assert.equal(r.summary.surveys.mais_usa.total, 1);
});

test('resposta antiga (sem perfil) ganha dono quando o aparelho se identifica depois', async () => {
  const H = mk();
  await profile(H, ANA, 'Ana');
  await fb(H, 'dev-ana-2', { kind: 'rating', rating: 4, comment: 'comentario-antigo' });
  const find = async () => (await adm(H, { action: 'survey' })).json().rows.filter((x) => x.c === 'comentario-antigo');
  let rows = await find();
  assert.equal(rows.length, 1);
  assert.equal(rows[0].code, '');
  assert.equal((await fb(H, 'dev-ana-2', { kind: 'identify', profile: ANA })).statusCode, 200);
  rows = await find();
  assert.equal(rows.length, 1, 'identificar não cria resposta nova');
  assert.equal(rows[0].code, ANA);
  assert.equal(rows[0].who.name, 'Ana');
  assert.equal(rows[0].r, 4);
});

test('identificar sem perfil válido é recusado; código inválido na resposta é ignorado', async () => {
  const H = mk();
  assert.equal((await fb(H, 'd-x1', { kind: 'identify', profile: 'lixo' })).statusCode, 400);
  assert.equal((await fb(H, 'd-x1', { kind: 'identify' })).statusCode, 400);
  assert.equal((await fb(H, 'd-x1', { kind: 'survey', qid: 'melhorar', answer: 'texto-invalido', profile: 'A0A0-1111' })).statusCode, 200);
  const row = (await adm(H, { action: 'survey' })).json().rows.find((x) => x.a === 'texto-invalido');
  assert.equal(row.code, '');
});

test('só o administrador vê a pesquisa', async () => {
  const H = mk();
  const res = fakeRes();
  await H.a({ method: 'POST', headers: { 'x-forwarded-for': '5.5.5.1', authorization: 'Bearer errada' }, body: { action: 'survey' }, socket: {} }, res);
  assert.equal(res.statusCode, 401);
});
