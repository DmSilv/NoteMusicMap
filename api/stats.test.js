// Testes das métricas anônimas e do painel de admin, sem rede: `node --test api/stats.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const stats = require('./stats');
const link = require('./link');
const { config } = require('./_lib/config');
const { hashes, memory } = require('./_lib/store');
const { resetMem } = require('./_lib/store_cmd');
const { dayKey, K } = require('./_lib/metrics');

const ADMIN = 'chave-admin-de-teste';
const ENV = { ADMIN_KEY: ADMIN };
let NOW = Date.UTC(2026, 10, 9, 15, 0, 0); // 09/11/2026 12:00 em Brasília
let ipN = 0;

function mk(env = ENV) {
  hashes.clear();
  memory.clear();
  resetMem();
  const deps = { config: () => config(env), allowMemory: true, fetch: async () => { throw new Error('sem rede'); }, now: () => NOW, random: () => 0.5 };
  return { s: stats.makeHandler(deps), l: link.makeHandler(deps) };
}
function fakeRes() {
  const r = { headers: {}, statusCode: 0, body: '' };
  r.setHeader = (k, v) => { r.headers[k] = v; };
  r.end = (b) => { r.body = b; };
  r.json = () => JSON.parse(r.body);
  return r;
}
async function call(h, req) {
  const res = fakeRes();
  await h({ headers: { 'x-forwarded-for': '8.8.8.' + (req.ip || ++ipN), ...(req.headers || {}) }, socket: {}, ...req }, res);
  return res;
}
const rid = () => crypto.randomBytes(12).toString('hex'); // 24 caracteres
const ping = (H, body, ip) => call(H.s, { method: 'POST', body, ip });
const admin = (H, part = 'full', key = ADMIN, ip) => call(H.s, { method: 'GET', url: '/api/stats?part=' + part, query: { part }, headers: { authorization: 'Bearer ' + key }, ip });

test('abrir o app conta usuário do dia, do total, aparelho novo e online', async () => {
  const H = mk();
  const a = rid(), b = rid();
  await ping(H, { t: 'open', id: a, d: { pl: 'android-chrome', in: 'pwa', v: 'abc123' } });
  await ping(H, { t: 'open', id: b, d: { pl: 'ios-safari', in: 'browser', v: 'abc123' } });
  await ping(H, { t: 'open', id: a }); // o mesmo aparelho abre de novo: não vira outro usuário
  const j = (await admin(H)).json();
  assert.equal(j.total, 2);
  const hoje = j.series[j.series.length - 1];
  assert.equal(hoje.day, '2026-11-09');
  assert.equal(hoje.users, 2);
  assert.equal(hoje.opens, 3);
  assert.equal(hoje.news, 2);
  assert.equal(j.online5, 2);
  assert.equal(j.dims.pl['android-chrome'], 1);
  assert.equal(j.dims.in.pwa, 1);
  assert.equal(j.dims.v.abc123, 2);
  assert.equal(j.series.length, 30);
});

test('o dia é o de Brasília (UTC-3): 01h UTC ainda é o dia anterior', async () => {
  const H = mk();
  NOW = Date.UTC(2026, 10, 10, 1, 0, 0);
  await ping(H, { t: 'open', id: rid() });
  const j = (await admin(H)).json();
  assert.equal(j.today, '2026-11-09');
  assert.equal(dayKey(NOW), '2026-11-09');
  NOW = Date.UTC(2026, 10, 9, 15, 0, 0);
});

test('batida mantém online; batida solta (sem ter aberto) não cria aparelho online', async () => {
  const H = mk();
  const a = rid();
  await ping(H, { t: 'open', id: a });
  NOW += 4 * 60000;
  await ping(H, { t: 'beat', id: a });
  await ping(H, { t: 'beat', id: rid() }); // nunca abriu
  assert.equal((await admin(H, 'live')).json().online5, 1);
  NOW += 6 * 60000; // 10 min sem bater
  const live = (await admin(H, 'live')).json();
  assert.equal(live.online5, 0);
  NOW = Date.UTC(2026, 10, 9, 15, 0, 0);
});

test('abas visitadas contam aparelhos distintos; nome fora da lista é ignorado', async () => {
  const H = mk();
  const a = rid(), b = rid();
  await ping(H, { t: 'open', id: a, tabs: ['tuner', 'grid'] });
  await ping(H, { t: 'open', id: b, tabs: ['tuner', 'hacker'] });
  await ping(H, { t: 'beat', id: a, tabs: ['tuner', 'study'] });
  const j = (await admin(H)).json();
  assert.equal(j.tabs.tuner, 2);
  assert.equal(j.tabs.grid, 1);
  assert.equal(j.tabs.study, 1);
  assert.equal('hacker' in j.tabs, false);
});

test('semana e mês: usuários distintos nos últimos 7 e 30 dias', async () => {
  const H = mk();
  const a = rid(), b = rid(), c = rid();
  NOW = Date.UTC(2026, 10, 1, 15);
  await ping(H, { t: 'open', id: a });
  await ping(H, { t: 'open', id: b });
  NOW = Date.UTC(2026, 10, 9, 15);
  await ping(H, { t: 'open', id: a });
  await ping(H, { t: 'open', id: c });
  const j = (await admin(H)).json();
  assert.equal(j.wau, 2, 'a e c nos últimos 7 dias');
  assert.equal(j.mau, 3);
  assert.equal(j.total, 3);
});

test('entrada inválida é recusada e nada é gravado', async () => {
  const H = mk();
  assert.equal((await ping(H, { t: 'open', id: 'curto' })).statusCode, 400);
  assert.equal((await ping(H, { t: 'open', id: 'K7QM-4TXK-QUE-NAO-E' })).statusCode, 400, 'código de professor não vale como id');
  assert.equal((await ping(H, { t: 'zzz', id: rid() })).statusCode, 400);
  assert.equal((await ping(H, 'lixo')).statusCode, 400);
  assert.equal((await ping(H, { t: 'open', id: rid(), d: { pl: '<script>', in: 'x', v: '../../etc' } })).statusCode, 200);
  assert.equal((await ping(H, { t: 'open', id: rid(), big: 'x'.repeat(2000) })).statusCode, 400, 'corpo grande demais');
  const j = (await admin(H)).json();
  assert.equal(j.total, 1, 'só o pedido válido contou');
  assert.deepEqual(j.dims, { pl: {}, in: {}, v: {}, o: {} }, 'valores estranhos não viram categoria');
});

test('painel: sem chave configurada 404; chave errada 401; muitas tentativas 429; certa 200', async () => {
  let H = mk({});
  assert.equal((await admin(H, 'full', 'qualquer')).statusCode, 404);
  H = mk();
  assert.equal((await admin(H, 'full', 'errada', 1)).statusCode, 401);
  assert.equal((await admin(H, 'live', ADMIN, 1)).statusCode, 200);
  let last = 0;
  for (let i = 0; i < 12; i++) last = (await admin(H, 'full', 'errada', 2)).statusCode;
  assert.equal(last, 429);
  assert.equal((await admin(H, 'live', ADMIN, 3)).statusCode, 200, 'outra origem com a chave certa entra');
});

test('limite de aberturas por origem: depois de 200 por hora, 429', async () => {
  const H = mk();
  let code = 200;
  for (let i = 0; i < 205; i++) code = (await ping(H, { t: 'open', id: rid() }, 77)).statusCode;
  assert.equal(code, 429);
});

test('contadores de uso vindos do servidor: perfis, vínculos e aulas aparecem no painel', async () => {
  const H = mk();
  const A = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  const code = (seed) => { let p = '', x = seed; for (let i = 0; i < 7; i++) { p += A[x % 32]; x = Math.floor(x / 32) + 7 + i; } let s = 0; for (let i = 0; i < 7; i++) s += A.indexOf(p[i]) * (2 * i + 1); const c = p + A[s % 32]; return c.slice(0, 4) + '-' + c.slice(4); };
  const P = code(11111), S = code(22222);
  const sec = (c) => crypto.createHash('sha256').update('s' + c).digest('hex');
  const L = (who, body) => call(H.l, { method: 'POST', body: { code: who, secret: sec(who), ...body } });
  await L(S, { action: 'sync' });
  await L(P, { action: 'link', role: 'teacher', other: S, name: 'P' });
  const task = { id: 't1', title: 'x', kind: 'free', st: 0, pc: 0, oct: 1, goal: 0.8, done: false, c: new Date().toISOString() };
  await L(P, { action: 'lesson', other: S, lesson: { id: 'aula01', t: NOW - 1000, d: 600, tasks: [task], notes: [] } });
  let j = (await admin(H)).json();
  assert.equal(j.totals.profiles, 2);
  assert.equal(j.totals.links, 1);
  const hoje = j.series[j.series.length - 1];
  assert.equal(hoje.lessons, 1);
  assert.equal(hoje.links, 1);
  await L(S, { action: 'unlink', role: 'student', other: P });
  j = (await admin(H)).json();
  assert.equal(j.totals.links, 0);
});

test('privacidade: nenhuma chave guardada contém IP, e o painel não devolve ids de aparelhos', async () => {
  const H = mk();
  await ping(H, { t: 'open', id: rid(), d: { pl: 'android-chrome', in: 'pwa', v: 'v1' } }, 55);
  const keys = [...hashes.keys()];
  assert.equal(keys.some((k) => k.includes('8.8.8')), false, 'o IP não é guardado em texto');
  const body = (await admin(H)).body;
  assert.equal(/[a-f0-9]{24}/.test(JSON.stringify(JSON.parse(body).dims)), false);
});

test('sem Redis (e sem modo de teste) responde 503 e não grava nada', async () => {
  const h = stats.makeHandler({ config: () => config(ENV), fetch: async () => { throw new Error('x'); }, now: () => NOW });
  const res = await call(h, { method: 'POST', body: { t: 'open', id: rid() } });
  assert.equal(res.statusCode, 503);
});

test('as chaves ficam sob o prefixo st: (não misturam com vínculos)', () => {
  for (const v of [K.all, K.total, K.online, K.day('x'), K.ct('x'), K.dim('x'), K.tab('x', 'y')]) assert.ok(v.startsWith('st:'));
});
