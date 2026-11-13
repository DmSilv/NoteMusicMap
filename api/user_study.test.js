// Tempo de estudo, modelo e cidade por perfil no painel, sem rede: `node --test api/user_study.test.js`
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
const UA_REDUZIDO = 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 Chrome/130.0.0.0 Mobile Safari/537.36';
const UA_COM_MODELO = 'Mozilla/5.0 (Linux; Android 12; SM-A325M) AppleWebKit/537.36 SamsungBrowser/24.0 Chrome/117.0.0.0 Mobile Safari/537.36';

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
async function as(H, body, headers = {}) {
  const res = fakeRes();
  await H.l({ method: 'POST', headers: { 'x-forwarded-for': '6.6.6.' + ++ipN, ...headers }, body: { code: ALU, secret: secret(ALU), action: 'sync', ...body }, socket: {} }, res);
  return res;
}
async function detail(H) {
  const res = fakeRes();
  await H.a({ method: 'POST', headers: { 'x-forwarded-for': '5.5.5.' + ++ipN, authorization: 'Bearer ' + KEY }, body: { action: 'detail', code: ALU }, socket: {} }, res);
  return res.json();
}
const DV = { pl: 'android-chrome', in: 'pwa', v: 'abc1234', os: 'a14', sc: 'celular' };

test('modelo: vem da dica de cliente; sem ela, do User-Agent; o "K" do UA reduzido não vale', async () => {
  let H = mk();
  await as(H, { dv: DV }, { 'user-agent': UA_REDUZIDO, 'sec-ch-ua-model': '"Pixel 7"' });
  assert.equal((await detail(H)).device.now.md, 'Pixel 7');
  H = mk();
  await as(H, { dv: DV }, { 'user-agent': UA_COM_MODELO });
  assert.equal((await detail(H)).device.now.md, 'SM-A325M');
  H = mk();
  await as(H, { dv: DV }, { 'user-agent': UA_REDUZIDO });
  assert.equal('md' in (await detail(H)).device.now, false);
});

test('cidade aproximada: vem decodificada e limpa; nunca o IP', async () => {
  const H = mk();
  await as(H, { dv: DV }, { 'user-agent': UA_REDUZIDO, 'x-vercel-ip-city': 'S%C3%A3o%20Paulo', 'x-vercel-ip-country': 'BR', 'x-vercel-ip-country-region': 'SP', 'x-forwarded-for': '203.0.113.9' });
  const raw = JSON.stringify(await detail(H));
  const d = JSON.parse(raw).device.now;
  assert.equal(d.ct, 'São Paulo');
  assert.equal(d.g, 'br-sp');
  assert.equal(raw.includes('203.0.113.9'), false, 'o IP não é guardado nem devolvido');
});

test('cidade/modelo malucos são limpos', async () => {
  const H = mk();
  await as(H, { dv: DV }, { 'user-agent': UA_REDUZIDO, 'x-vercel-ip-city': '%3Cscript%3Ealert(1)%3C%2Fscript%3E', 'sec-ch-ua-model': '"<b>X</b>;DROP"' });
  const d = (await detail(H)).device.now;
  assert.equal(/[<>;()]/.test(d.ct || ''), false);
  assert.equal(/[<>;()]/.test(d.md || ''), false);
  assert.equal((await as(H, { dv: DV }, { 'x-vercel-ip-city': '%E0%A4%A' })).statusCode, 200, 'cabeçalho torto não derruba');
});

test('estudo: 7 dias de minutos aparecem com as datas certas; formato ruim é ignorado', async () => {
  const H = mk();
  await as(H, { dv: { ...DV, sm: '0,10,20,0,5,30,45' } });
  const s = (await detail(H)).study;
  assert.equal(s.days.length, 7);
  assert.equal(s.days[6].min, 45);
  assert.equal(s.total7, 110);
  assert.equal(s.updated, NOW);
  const H2 = mk();
  await as(H2, { dv: { ...DV, sm: '1,2,3' } });
  assert.equal((await detail(H2)).study, null);
  const H3 = mk();
  await as(H3, { dv: { ...DV, sm: 'a,b,c,d,e,f,g' } });
  assert.equal((await detail(H3)).study, null);
});

test('estudo: só regrava quando muda; o mesmo valor não gasta comando', async () => {
  const lists = [];
  const cmd = { pipeline: async (l) => { lists.push(l); return []; } };
  const dv = profiles.deviceInfo(DV, {});
  const saved = { pa: String(NOW), dv: JSON.stringify(dv), dt: String(NOW), sm: '0,0,0,0,0,0,10' };
  assert.equal(await profiles.seen(cmd, saved, ALU, NOW + 2 * MIN, { dv, sm: '0,0,0,0,0,0,10' }), false);
  assert.equal(lists.length, 0);
  assert.equal(await profiles.seen(cmd, saved, ALU, NOW + 2 * MIN, { dv, sm: '0,0,0,0,0,0,25' }), false);
  assert.equal(lists.length, 1);
  assert.equal(lists[0].length, 1, 'só o HSET, junto com o resto');
});

test('quem desligou as estatísticas (sem dv) não manda estudo nem ficha', async () => {
  const H = mk();
  await as(H, {}, { 'user-agent': UA_COM_MODELO, 'x-vercel-ip-city': 'Rio' });
  const d = await detail(H);
  assert.equal(d.study, null);
  assert.equal(d.device.now, null);
});
