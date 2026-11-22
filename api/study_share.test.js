// Resumo da semana de estudo que o aluno escolhe mostrar ao professor: `node --test api/study_share.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { makeHandler } = require('./link');
const { config } = require('./_lib/config');
const { hashes, memory } = require('./_lib/store');

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
const PROF = code(11111), ALU = code(22222), OUTRO = code(44444);
const sec = (ch) => ch.repeat(64).slice(0, 64);
const S_PROF = sec('a'), S_ALU = sec('b'), S_OUTRO = sec('c');

function fakeRes() {
  const r = { headers: {}, statusCode: 0, body: '' };
  r.setHeader = (k, v) => { r.headers[k] = v; };
  r.end = (b) => { r.body = b; };
  r.json = () => JSON.parse(r.body);
  return r;
}
let NOW = Date.UTC(2026, 10, 14, 15, 0, 0);
function mk() {
  hashes.clear();
  memory.clear();
  NOW = Date.UTC(2026, 10, 14, 15, 0, 0);
  return makeHandler({ config: () => config({}), allowMemory: true, now: () => NOW, fetch: async () => { throw new Error('sem rede'); } });
}
let n = 0;
async function call(h, body) {
  const res = fakeRes();
  await h({ method: 'POST', headers: { 'x-forwarded-for': '8.8.8.' + ++n }, body, socket: {} }, res);
  return res;
}
const as = (h, c, s, body) => call(h, { code: c, secret: s, ...body });
const sync = (h, c, s) => as(h, c, s, { action: 'sync' }).then((r) => r.json());

async function linked() {
  const h = mk();
  await as(h, PROF, S_PROF, { action: 'link', role: 'teacher', other: ALU, name: 'Profa. Ana' });
  await sync(h, ALU, S_ALU);
  return h;
}
const resumo = { w: '2026-11-09', m: 84, g: 120, d: 5, a: 78, tk: 3, tt: 4, n: 5, weak: ['Si', 'Fá#'], up: { t: 'Sol maior · 2 oitavas', a: 62, b: 78 } };

test('o aluno compartilha e o professor lê o resumo do seu aluno', async () => {
  const h = await linked();
  const put = await as(h, ALU, S_ALU, { action: 'study_put', study: resumo });
  assert.equal(put.statusCode, 200);
  const got = await as(h, PROF, S_PROF, { action: 'study_get' });
  assert.equal(got.statusCode, 200);
  const item = got.json().study[ALU];
  assert.equal(item.m, 84);
  assert.equal(item.a, 78);
  assert.deepEqual(item.weak, ['Si', 'Fá#']);
  assert.equal(item.up.t, 'Sol maior · 2 oitavas');
});

test('sem compartilhar, o professor não vê nada; desligar apaga', async () => {
  const h = await linked();
  assert.deepEqual((await as(h, PROF, S_PROF, { action: 'study_get' })).json().study, {});
  await as(h, ALU, S_ALU, { action: 'study_put', study: resumo });
  await as(h, ALU, S_ALU, { action: 'study_put', on: false });
  assert.deepEqual((await as(h, PROF, S_PROF, { action: 'study_get' })).json().study, {});
});

test('quem não é professor desse aluno não lê o resumo', async () => {
  const h = await linked();
  await as(h, ALU, S_ALU, { action: 'study_put', study: resumo });
  const r = await as(h, OUTRO, S_OUTRO, { action: 'study_get' });
  assert.deepEqual(r.json().study || {}, {});
});

test('o servidor limpa o resumo: só números e notas curtas', async () => {
  const h = await linked();
  const sujo = { ...resumo, m: 999999, d: 40, a: 500, weak: ['ok', '<script>', 'x'.repeat(30), 'Lá', 'Ré', 'Mi'], up: { t: 'a'.repeat(200) + '‮', a: -5, b: 900 }, extra: 'texto solto' };
  await as(h, ALU, S_ALU, { action: 'study_put', study: sujo });
  const item = (await as(h, PROF, S_PROF, { action: 'study_get' })).json().study[ALU];
  assert.equal(item.m, 6000);
  assert.equal(item.d, 7);
  assert.equal(item.a, 100);
  assert.deepEqual(item.weak, ['ok', 'Lá', 'Ré']);
  assert.equal(item.up.t.length, 40);
  assert.equal(item.up.a, 0);
  assert.equal(item.up.b, 100);
  assert.equal(item.extra, undefined);
});

test('resumo inválido é recusado e resumo velho some', async () => {
  const h = await linked();
  assert.equal((await as(h, ALU, S_ALU, { action: 'study_put', study: { m: 5 } })).statusCode, 400);
  assert.equal((await as(h, ALU, S_ALU, { action: 'study_put', study: 'oi' })).statusCode, 400);
  await as(h, ALU, S_ALU, { action: 'study_put', study: resumo });
  NOW += 15 * 86400000;
  assert.deepEqual((await as(h, PROF, S_PROF, { action: 'study_get' })).json().study, {});
});

test('há limite de envios por hora', async () => {
  const h = await linked();
  let last = 0;
  for (let i = 0; i < 14; i++) last = (await as(h, ALU, S_ALU, { action: 'study_put', study: resumo })).statusCode;
  assert.equal(last, 429);
});
