// Testes da limpeza de perfis abandonados e do aviso de origens com muitos perfis: `node --test api/sweep.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const link = require('./link');
const admin = require('./admin');
const { config } = require('./_lib/config');
const { hashes, memory } = require('./_lib/store');
const { resetMem, createCmd } = require('./_lib/store_cmd');
const { sweepEmpty } = require('./_lib/sweep');

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
const secret = (c) => crypto.createHash('sha256').update('s' + c).digest('hex');
const KEY = 'chave-de-admin-de-teste';
const DAY = 86400000;
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
  const cfg = config({ ADMIN_KEY: KEY });
  const deps = { config: () => cfg, allowMemory: true, fetch: async () => ({ status: 200 }), now: () => NOW };
  return { l: link.makeHandler(deps), a: admin.makeHandler(deps), cmd: createCmd(cfg, async () => ({ status: 200 }), { allowMemory: true }) };
}
async function as(H, who, body, ip) {
  const res = fakeRes();
  await H.l({ method: 'POST', headers: { 'x-forwarded-for': ip || '6.6.6.' + ++ipN }, body: { code: who, secret: secret(who), ...body }, socket: {} }, res);
  return res;
}
async function adm(H, body) {
  const res = fakeRes();
  await H.a({ method: 'POST', headers: { 'x-forwarded-for': '5.5.5.' + ++ipN, authorization: 'Bearer ' + KEY }, body, socket: {} }, res);
  return res;
}
const exists = async (H, c) => (await H.cmd.cmd(['HLEN', `u:${c}`])) > 0;

test('perfil vazio parado há 60 dias é apagado; quem tem vínculo, papel ou bloqueio fica', async () => {
  const H = mk();
  const VAZIO = code(1001), PROF = code(2002), ALU = code(3003), BLOQ = code(4004);
  for (const c of [VAZIO, PROF, ALU, BLOQ]) await as(H, c, { action: 'sync', name: 'Pessoa ' + c.slice(0, 2) });
  await as(H, PROF, { action: 'link', role: 'teacher', other: ALU });
  await adm(H, { action: 'block', code: BLOQ });

  NOW += 30 * DAY;
  assert.equal(await sweepEmpty(H.cmd, NOW, 10), 0, 'com 30 dias ainda ninguém é apagado');
  NOW += 40 * DAY; // 70 dias parados
  const n = await sweepEmpty(H.cmd, NOW, 10);
  assert.equal(n, 1);
  assert.equal(await exists(H, VAZIO), false);
  for (const c of [PROF, ALU, BLOQ]) assert.equal(await exists(H, c), true, c + ' deveria ficar');
});

test('perfil com atividade recente não é apagado, e o painel pode limpar sob pedido', async () => {
  const H = mk();
  const VELHO = code(5005), ATIVO = code(6006);
  await as(H, VELHO, { action: 'sync', name: 'Velho' });
  await as(H, ATIVO, { action: 'sync', name: 'Ativo' });
  NOW += 65 * DAY;
  await as(H, ATIVO, { action: 'sync' }); // o ativo volta a usar
  const ind = (await adm(H, { action: 'indicators' })).json();
  assert.equal(ind.staleProfiles, 1);
  const r = (await adm(H, { action: 'sweep' })).json();
  assert.equal(r.removed, 1);
  assert.equal(await exists(H, VELHO), false);
  assert.equal(await exists(H, ATIVO), true);
});

test('uma origem que passa de 30 perfis novos no dia aparece no aviso do painel, sem ser barrada', async () => {
  const H = mk();
  for (let i = 0; i < 35; i++) {
    const r = await as(H, code(70000 + i * 977), { action: 'sync' }, '9.9.9.9');
    assert.equal(r.statusCode, 200, 'o limite agora é 100 por dia');
  }
  const ind = (await adm(H, { action: 'indicators' })).json();
  assert.equal(ind.hotOrigins, 1);
});
