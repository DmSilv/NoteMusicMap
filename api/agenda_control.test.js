// Testes do controle da agenda (trocar o aluno de uma aula, remarcar uma data, pausar): `node --test api/agenda_control.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const link = require('./link');
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
const PROF = code(11), ALU = code(33), ALU2 = code(44);
const secret = (c) => crypto.createHash('sha256').update('s' + c).digest('hex');
const NOW = 1_800_000_000_000;
const DAY = 86400000;
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
  const cfg = config({});
  const deps = { config: () => cfg, allowMemory: true, fetch: async () => ({ status: 200 }), now: () => NOW };
  return link.makeHandler(deps);
}
async function as(H, who, body) {
  const res = fakeRes();
  await H({ method: 'POST', headers: { 'x-forwarded-for': '4.4.4.' + ++ipN }, body: { code: who, secret: secret(who), ...body }, socket: {} }, res);
  return res;
}
async function setup() {
  const H = mk();
  for (const [who, nm] of [[PROF, 'Prof'], [ALU, 'Ana'], [ALU2, 'Bia']]) await as(H, who, { action: 'sync', name: nm });
  await as(H, PROF, { action: 'link', role: 'teacher', other: ALU });
  await as(H, PROF, { action: 'link', role: 'teacher', other: ALU2 });
  return H;
}
const slot = (id, extra = {}) => ({ id, s: NOW + 3 * DAY, d: 60, u: NOW, ...extra });
const put = (H, s, other = ALU) => as(H, PROF, { action: 'sched_put', other, slot: s });
const mine = async (H, who) => (await as(H, who, { action: 'sched' })).json().slots;

test('trocar o aluno da aula: o novo aluno recebe e o anterior deixa de ver', async () => {
  const H = await setup();
  await put(H, slot('aaaa'), ALU);
  assert.equal((await mine(H, ALU)).length, 1);
  assert.equal((await put(H, slot('aaaa', { u: NOW + 1 }), ALU2)).statusCode, 200);
  assert.equal((await mine(H, ALU)).length, 0);
  const r = await mine(H, ALU2);
  assert.equal(r.length, 1);
  assert.equal(r[0].id, 'aaaa');
  const rev = (await as(H, ALU, { action: 'rev' })).json();
  assert.ok(rev.sr > 0, 'o aluno anterior é avisado (a revisão da agenda dele andou)');
});

test('editar a aula sem trocar o aluno não mexe nas cópias dos outros', async () => {
  const H = await setup();
  await put(H, slot('aaaa'), ALU);
  await put(H, slot('bbbb'), ALU2);
  await put(H, slot('aaaa', { d: 45, u: NOW + 1 }), ALU);
  const a = await mine(H, ALU);
  assert.equal(a.length, 1);
  assert.equal(a[0].d, 45);
  assert.equal((await mine(H, ALU2)).length, 1);
});

test('remarcar só uma data: a regra ganha a data cancelada, nasce uma aula avulsa e o aluno recebe as duas', async () => {
  const H = await setup();
  const regra = slot('rrrr', { w: 1 });
  await put(H, regra);
  const data = regra.s + 7 * DAY;
  await put(H, { ...regra, x: [data], u: NOW + 1 });
  await put(H, slot('nnnn', { s: data + 3600000, u: NOW + 1 }));
  const r = await mine(H, ALU);
  assert.equal(r.length, 2);
  assert.deepEqual(r.find((x) => x.id === 'rrrr').x, [data]);
  assert.equal(r.find((x) => x.id === 'nnnn').w, undefined);
});

test('pausar: a aula cancelada continua marcada como cancelada para o aluno', async () => {
  const H = await setup();
  await put(H, slot('aaaa'));
  await put(H, slot('aaaa', { c: 1, u: NOW + 1 }));
  assert.equal((await mine(H, ALU))[0].c, 1);
});
