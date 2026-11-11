// Testes dos indicadores de saúde do uso no painel, sem rede: `node --test api/indicators.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const link = require('./link');
const admin = require('./admin');
const { config } = require('./_lib/config');
const { hashes, memory } = require('./_lib/store');
const { createCmd, resetMem } = require('./_lib/store_cmd');
const { K, dayKey } = require('./_lib/metrics');

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
const ALU = code(22222), OUTRO = code(44444);
const secret = (c) => crypto.createHash('sha256').update('s' + c).digest('hex');
const KEY = 'chave-de-admin-de-teste';
const NOW = 1_800_000_000_000;
const CFG = () => config({ ADMIN_KEY: KEY, VERCEL_GIT_COMMIT_SHA: 'abc1234def', AI_RPD: '200' });
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
  const deps = { config: CFG, allowMemory: true, fetch: async () => ({ status: 200 }), now: () => NOW };
  return { l: link.makeHandler(deps), a: admin.makeHandler(deps), cmd: createCmd(CFG(), async () => ({}), { allowMemory: true }) };
}
async function adm(H, body, key = KEY) {
  const res = fakeRes();
  await H.a({ method: 'POST', headers: { 'x-forwarded-for': '5.5.5.' + ++ipN, authorization: 'Bearer ' + key }, body, socket: {} }, res);
  return res;
}
async function as(H, who, body) {
  const res = fakeRes();
  await H.l({ method: 'POST', headers: { 'x-forwarded-for': '6.6.6.' + ++ipN }, body: { code: who, secret: secret(who), ...body }, socket: {} }, res);
  return res;
}
// combinação: pl|in|os|sc|lg|th|tc|mic|nt|v|geo|tz|mem|cpu|net|dpr
const combo = (nt, v) => `x:android-chrome|pwa|a14|s|pt|dark|sim|sim|${nt}|${v}|br-sp|m3|8|c8|4g|d2`;

test('notificações negadas e versões antigas saem das fichas dos aparelhos (7 dias)', async () => {
  const H = mk();
  const day = dayKey(NOW);
  await H.cmd.cmd(['HINCRBY', K.dim(day), combo('nao', 'abc1234'), '3']);
  await H.cmd.cmd(['HINCRBY', K.dim(day), combo('sim', 'abc1234'), '5']);
  await H.cmd.cmd(['HINCRBY', K.dim(day), combo('nd', '9f8e7d6'), '2']);
  await H.cmd.cmd(['HINCRBY', K.dim(day), combo('na', '-'), '4']);
  const r = (await adm(H, { action: 'indicators' })).json();
  assert.equal(r.devices, 14);
  assert.deepEqual([r.notifications.granted, r.notifications.denied, r.notifications.notAsked, r.notifications.unsupported], [5, 3, 2, 4]);
  assert.equal(r.notifications.deniedPct, 37.5); // 3 de quem já respondeu (5 + 3)
  assert.equal(r.versions.current, 'abc1234');
  assert.equal(r.versions.withVersion, 10); // quem não informou a versão fica de fora
  assert.equal(r.versions.outdated, 2);
  assert.equal(r.versions.outdatedPct, 20);
});

test('sem dados, os percentuais ficam vazios em vez de zero enganoso', async () => {
  const H = mk();
  const r = (await adm(H, { action: 'indicators' })).json();
  assert.equal(r.notifications.deniedPct, null);
  assert.equal(r.versions.outdatedPct, null);
  assert.equal(r.devices, 0);
});

test('cota de IA do dia, perfis online e bloqueados', async () => {
  const H = mk();
  await H.cmd.cmd(['SET', `gd:${new Date(NOW).toISOString().slice(0, 10)}`, '50']);
  await as(H, ALU, { action: 'sync' });
  await as(H, OUTRO, { action: 'sync' });
  let r = (await adm(H, { action: 'indicators' })).json();
  assert.deepEqual(r.ai, { today: 50, limit: 200, pct: 25 });
  assert.equal(r.onlineProfiles, 2);
  assert.equal(r.blockedProfiles, 0);
  await adm(H, { action: 'block', code: ALU });
  await adm(H, { action: 'block', code: OUTRO });
  assert.equal((await adm(H, { action: 'indicators' })).json().blockedProfiles, 2);
  await adm(H, { action: 'unblock', code: ALU });
  await adm(H, { action: 'delete', code: OUTRO, confirm: OUTRO }); // excluir também tira do conjunto
  r = (await adm(H, { action: 'indicators' })).json();
  assert.equal(r.blockedProfiles, 0);
});

test('indicadores só para o admin e sem nada pessoal na resposta', async () => {
  const H = mk();
  assert.equal((await adm(H, { action: 'indicators' }, 'errada')).statusCode, 401);
  await as(H, ALU, { action: 'sync', name: 'Fulana' });
  const body = (await adm(H, { action: 'indicators' })).body;
  assert.equal(body.includes(ALU), false);
  assert.equal(body.includes('Fulana'), false);
});
