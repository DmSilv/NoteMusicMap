// Testes da presença (quem está online agora) no painel, sem rede: `node --test api/presence.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const link = require('./link');
const admin = require('./admin');
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
const PROF = code(11111), ALU = code(22222);
const secret = (c) => crypto.createHash('sha256').update('s' + c).digest('hex');
const KEY = 'chave-de-admin-de-teste';
const MIN = 60000;

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
  const deps = { config: () => config({ ADMIN_KEY: KEY }), allowMemory: true, fetch: async () => ({ status: 200 }), now: () => NOW };
  return { l: link.makeHandler(deps), a: admin.makeHandler(deps) };
}
async function as(H, who, body) {
  const res = fakeRes();
  await H.l({ method: 'POST', headers: { 'x-forwarded-for': '6.6.6.' + ++ipN }, body: { code: who, secret: secret(who), ...body }, socket: {} }, res);
  return res;
}
async function adm(H, body, key = KEY) {
  const res = fakeRes();
  await H.a({ method: 'POST', headers: { 'x-forwarded-for': '5.5.5.' + ++ipN, authorization: 'Bearer ' + key }, body, socket: {} }, res);
  return res;
}
const presence = async (H) => (await adm(H, { action: 'presence' })).json();

test('quem consulta com o vínculo ligado aparece online, com nome e papel', async () => {
  const H = mk();
  await as(H, ALU, { action: 'sync', name: 'Aluna Maria' });
  await as(H, PROF, { action: 'sync', name: 'Profa. Ana' });
  await as(H, PROF, { action: 'link', role: 'teacher', other: ALU });
  const p = await presence(H);
  assert.equal(p.onlineCount, 2);
  assert.equal(p.windowMin, 12);
  const prof = p.items.find((x) => x.code === PROF);
  assert.equal(prof.online, true);
  assert.equal(prof.name, 'Profa. Ana');
  assert.equal(prof.teacher, true);
  assert.equal(p.items.find((x) => x.code === ALU).student, true);
});

test('a presença grava no máximo a cada 10 min (custo baixo) e a consulta barata (rev) já conta', async () => {
  const H = mk();
  await as(H, ALU, { action: 'sync' });
  const t0 = (await presence(H)).items[0].last;
  NOW += 3 * MIN;
  for (let i = 0; i < 6; i++) await as(H, ALU, { action: 'rev' });
  assert.equal((await presence(H)).items[0].last, t0); // nada regravado
  NOW += 8 * MIN; // 11 min desde a gravação: passou de 10
  await as(H, ALU, { action: 'rev' });
  assert.equal((await presence(H)).items[0].last, NOW);
});

test('some do online depois de 12 min, vira "esteve há pouco" e sai do índice em 2 dias', async () => {
  const H = mk();
  await as(H, ALU, { action: 'sync' });
  NOW += 13 * MIN;
  let p = await presence(H);
  assert.equal(p.onlineCount, 0);
  assert.equal(p.items.length, 1);
  assert.equal(p.items[0].online, false);
  NOW += 3 * 24 * 60 * MIN;
  p = await presence(H);
  assert.equal(p.items.length, 0);
});

test('perfil excluído não aparece mais como online', async () => {
  const H = mk();
  await as(H, ALU, { action: 'sync' });
  assert.equal((await presence(H)).onlineCount, 1);
  await adm(H, { action: 'delete', code: ALU, confirm: ALU });
  const p = await presence(H);
  assert.equal(p.onlineCount, 0);
  assert.equal(p.items.length, 0);
});

test('presença só para o admin, e o app não recebe nada novo (compatibilidade)', async () => {
  const H = mk();
  assert.equal((await adm(H, { action: 'presence' }, 'errada')).statusCode, 401);
  const r = (await as(H, ALU, { action: 'sync' })).json();
  assert.equal('pa' in r, false);
  assert.equal(JSON.stringify(r).includes('online'), false);
});
