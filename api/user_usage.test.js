// Tempo de uso e ficha do aparelho por perfil no painel, sem rede: `node --test api/user_usage.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const link = require('./link');
const admin = require('./admin');
const profiles = require('./_lib/profiles');
const { config } = require('./_lib/config');
const { hashes, memory } = require('./_lib/store');
const { resetMem } = require('./_lib/store_cmd');

const A = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
function code(seed) {
  let p = ''; let x = seed;
  for (let i = 0; i < 7; i++) { p += A[x % 32]; x = Math.floor(x / 32) + 7 + i; }
  let s = 0;
  for (let i = 0; i < 7; i++) s += A.indexOf(p[i]) * (2 * i + 1);
  const c = p + A[s % 32];
  return `${c.slice(0, 4)}-${c.slice(4)}`;
}
const ALU = code(22222);
const secret = (c) => crypto.createHash('sha256').update('s' + c).digest('hex');
const KEY = 'chave-de-admin-de-teste';
const MIN = 60000;
const UA = 'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36';

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
  hashes.clear(); memory.clear(); resetMem();
  NOW = 1_800_000_000_000;
  const deps = { config: () => config({ ADMIN_KEY: KEY }), allowMemory: true, fetch: async () => ({ status: 200 }), now: () => NOW };
  return { l: link.makeHandler(deps), a: admin.makeHandler(deps) };
}
async function as(H, who, body, headers = {}) {
  const res = fakeRes();
  await H.l({ method: 'POST', headers: { 'x-forwarded-for': '6.6.6.' + ++ipN, ...headers }, body: { code: who, secret: secret(who), action: 'sync', ...body }, socket: {} }, res);
  return res;
}
async function adm(H, body) {
  const res = fakeRes();
  await H.a({ method: 'POST', headers: { 'x-forwarded-for': '5.5.5.' + ++ipN, authorization: 'Bearer ' + KEY }, body, socket: {} }, res);
  return res;
}
const detail = async (H) => (await adm(H, { action: 'detail', code: ALU })).json();
const DV = { pl: 'android-chrome', in: 'pwa', v: 'abc1234', os: 'a14', sc: 'celular', lg: 'pt', th: 'escuro', tc: 'sim', mic: 'sim', nt: 'sim', tz: 'm3', mem: '4', cpu: 'c8', net: '4g', dpr: 'd3' };
const HDR = { 'user-agent': UA, 'x-vercel-ip-country': 'BR', 'x-vercel-ip-country-region': 'SP' };

test('ficha do aparelho: o que o app manda + navegador, sistema e região deduzidos pelo servidor', async () => {
  const H = mk();
  await as(H, ALU, { dv: DV }, HDR);
  const d = (await detail(H)).device;
  assert.equal(d.now.pl, 'android-chrome');
  assert.equal(d.now.os, 'a14');
  assert.equal(d.now.br, 'chrome130');
  assert.equal(d.now.ou, 'android');
  assert.equal(d.now.mob, '1');
  assert.equal(d.now.g, 'br-sp');
  assert.equal(d.first, NOW);
  assert.equal(d.changes, 0);
  assert.equal(d.previous, null);
});

test('ficha: valores estranhos são descartados (só categorias curtas)', async () => {
  const H = mk();
  await as(H, ALU, { dv: { ...DV, os: '<script>alert(1)</script>', lg: 'x'.repeat(40), extra: 'nao existe', sc: 'celular' } }, HDR);
  const d = (await detail(H)).device.now;
  assert.equal('os' in d, false);
  assert.equal('lg' in d, false);
  assert.equal('extra' in d, false);
  assert.equal(d.sc, 'celular');
  assert.equal((await as(H, ALU, { dv: 'texto' }, HDR)).statusCode, 200);
  assert.equal((await as(H, ALU, { dv: [1, 2] }, HDR)).statusCode, 200);
});

test('ficha: troca de aparelho guarda o anterior e conta a mudança; repetir a mesma não grava', async () => {
  const H = mk();
  await as(H, ALU, { dv: DV }, HDR);
  NOW += 7 * MIN;
  await as(H, ALU, { dv: DV }, HDR);
  assert.equal((await detail(H)).device.changes, 0);
  NOW += 8 * MIN;
  await as(H, ALU, { dv: { ...DV, pl: 'windows-edge', os: 'w10', sc: 'pc' } }, { ...HDR, 'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/130.0 Safari/537.36 Edg/130.0' });
  const d = (await detail(H)).device;
  assert.equal(d.changes, 1);
  assert.equal(d.now.pl, 'windows-edge');
  assert.equal(d.now.br, 'edge130');
  assert.equal(d.previous.pl, 'android-chrome');
});

test('sem ficha (app antigo): continua funcionando e o tempo de uso conta igual', async () => {
  const H = mk();
  await as(H, ALU, {}, HDR);
  const d = await detail(H);
  assert.equal(d.device.now, null);
  assert.equal(d.usage.sessions, 1);
});

test('tempo de uso: sessão contínua soma os minutos; depois de uma pausa começa outra sessão', async () => {
  const H = mk();
  await as(H, ALU, {});
  let u = (await detail(H)).usage;
  assert.equal(u.today, 1, 'sessão nova vale 1 min');
  assert.equal(u.sessions, 1);
  NOW += 10 * MIN; await as(H, ALU, {});
  NOW += 10 * MIN; await as(H, ALU, {});
  u = (await detail(H)).usage;
  assert.equal(u.today, 21);
  assert.equal(u.sessions, 1);
  NOW += 60 * MIN; await as(H, ALU, {});
  u = (await detail(H)).usage;
  assert.equal(u.sessions, 2);
  assert.equal(u.today, 22);
  assert.equal(u.totalMin, 22);
  assert.equal(u.days.length, 14);
  assert.equal(u.days[13].sessions, 2);
  assert.equal(u.min7, 22);
  assert.equal(u.activeDays14, 1);
  assert.equal(u.online, true);
});

test('tempo de uso: 14 dias de histórico e os mais velhos saem', async () => {
  const H = mk();
  await as(H, ALU, {});
  NOW += 20 * 86400000; await as(H, ALU, {});
  const u = (await detail(H)).usage;
  assert.equal(u.days.at(-1).min, 1);
  assert.equal(u.days.filter((x) => x.min > 0).length, 1);
  assert.equal(u.totalMin, 2);
  assert.equal(u.sessions, 2);
});

test('lista: mostra online e minutos de hoje', async () => {
  const H = mk();
  await as(H, ALU, {});
  NOW += 10 * MIN; await as(H, ALU, {});
  const it = (await adm(H, { action: 'list' })).json().items[0];
  assert.equal(it.online, true);
  assert.equal(it.todayMin, 11);
  NOW += 3 * 3600000;
  assert.equal((await adm(H, { action: 'list' })).json().items[0].online, false);
});

test('custo: a presença continua sendo 1 HSET + 1 ZADD (ficha e uso vão no mesmo comando)', async () => {
  const lists = [];
  const cmd = { pipeline: async (l) => { lists.push(l); return []; } };
  const dv = profiles.deviceInfo(DV, HDR);
  await profiles.seen(cmd, {}, ALU, NOW, { dv });
  assert.equal(lists.length, 1);
  assert.equal(lists[0].length, 2);
  assert.equal(lists[0][0][0], 'HSET');
  assert.equal(lists[0][1][0], 'ZADD');
  const saved = { pa: String(NOW), dv: JSON.stringify(dv), dt: String(NOW) };
  lists.length = 0;
  assert.equal(await profiles.seen(cmd, saved, ALU, NOW + 3 * MIN, { dv }), false);
  assert.equal(lists.length, 0, 'dentro dos 10 min e ficha igual: nenhum comando');
  assert.equal(await profiles.seen(cmd, saved, ALU, NOW + 3 * MIN, { dv: { ...dv, v: 'novo' } }), false);
  assert.equal(lists.length, 1);
  assert.equal(lists[0].length, 1, 'ficha mudou fora da hora da presença: só o HSET');
});

test('o painel nunca devolve segredo nem hash junto com a ficha', async () => {
  const H = mk();
  await as(H, ALU, { dv: DV }, HDR);
  const raw = (await adm(H, { action: 'detail', code: ALU })).body;
  assert.equal(raw.includes(secret(ALU)), false);
  assert.equal(raw.includes('"h"'), false);
});
