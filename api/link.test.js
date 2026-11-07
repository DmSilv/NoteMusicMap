// Testes do vínculo professor-aluno, sem rede: `node --test api/link.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { makeHandler, _internal } = require('./link');
const { config } = require('./_lib/config');
const { hashes, memory } = require('./_lib/store');

const A = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
/** Gera um código válido a partir de 7 símbolos. */
function code(seed) {
  let p = '';
  let x = seed;
  for (let i = 0; i < 7; i++) { p += A[x % 32]; x = Math.floor(x / 32) + 7 + i; }
  let s = 0;
  for (let i = 0; i < 7; i++) s += A.indexOf(p[i]) * (2 * i + 1);
  const c = p + A[s % 32];
  return `${c.slice(0, 4)}-${c.slice(4)}`;
}
const PROF = code(11111); // professor
const ALU = code(22222); // aluno
const ALU2 = code(33333);
const secret = (n) => String(n).padStart(2, '0').repeat(32).slice(0, 64).replace(/[^0-9a-f]/g, 'a');
const S_PROF = secret(1), S_ALU = secret(2), S_ALU2 = secret(3);

function fakeRes() {
  const r = { headers: {}, statusCode: 0, body: '' };
  r.setHeader = (k, v) => { r.headers[k] = v; };
  r.end = (b) => { r.body = b; };
  r.json = () => JSON.parse(r.body);
  return r;
}
function mk(env = {}, extra = {}) {
  hashes.clear();
  memory.clear();
  return makeHandler({ config: () => config(env), allowMemory: true, fetch: async () => { throw new Error('sem rede'); }, ...extra });
}
let n = 0;
async function call(h, body, ip) {
  const res = fakeRes();
  await h({ method: 'POST', headers: { 'x-forwarded-for': ip || '7.7.7.' + ++n }, body, socket: {} }, res);
  return res;
}
const sync = (h, c, s) => call(h, { action: 'sync', code: c, secret: s }).then((r) => r.json());

test('os códigos de teste são válidos', () => {
  for (const c of [PROF, ALU, ALU2]) assert.equal(_internal.normCode(c), c);
  assert.equal(_internal.normCode('ABCD-1234'), null);
});

test('sem Redis (e sem modo de teste) devolve 503 e não grava nada', async () => {
  const h = makeHandler({ config: () => config({}), fetch: async () => { throw new Error('x'); } });
  const r = await call(h, { action: 'sync', code: PROF, secret: S_PROF });
  assert.equal(r.statusCode, 503);
  assert.equal(r.json().error, 'sync_unavailable');
});

test('professor lê o QR do aluno: vínculo aparece nos DOIS lados', async () => {
  const h = mk();
  const r = await call(h, { action: 'link', code: PROF, secret: S_PROF, role: 'teacher', other: ALU, name: 'Profa. Ana' });
  assert.equal(r.statusCode, 200);
  assert.equal(r.json().created, true);
  const t = await sync(h, PROF, S_PROF);
  assert.deepEqual(t.asTeacher.map((x) => x.code), [ALU]);
  assert.equal(t.asStudent.length, 0);
  const a = await sync(h, ALU, S_ALU); // o aluno abre o app depois e já vê o professor
  assert.deepEqual(a.asStudent.map((x) => x.code), [PROF]);
  assert.equal(a.asStudent[0].name, 'Profa. Ana');
  assert.equal(a.asTeacher.length, 0);
});

test('aluno lê o QR do professor: o aluno aparece na lista do professor', async () => {
  const h = mk();
  const r = await call(h, { action: 'link', code: ALU, secret: S_ALU, role: 'student', other: PROF, name: 'Bia' });
  assert.equal(r.statusCode, 200);
  const t = await sync(h, PROF, S_PROF);
  assert.deepEqual(t.asTeacher.map((x) => [x.code, x.name]), [[ALU, 'Bia']]);
  const a = await sync(h, ALU, S_ALU);
  assert.deepEqual(a.asStudent.map((x) => x.code), [PROF]);
});

test('repetir o vínculo não duplica', async () => {
  const h = mk();
  const body = { action: 'link', code: PROF, secret: S_PROF, role: 'teacher', other: ALU };
  assert.equal((await call(h, body)).json().created, true);
  assert.equal((await call(h, body)).json().created, false);
  assert.equal((await sync(h, PROF, S_PROF)).asTeacher.length, 1);
});

test('ninguém se vincula a si mesmo', async () => {
  const h = mk();
  const r = await call(h, { action: 'link', code: PROF, secret: S_PROF, role: 'teacher', other: PROF });
  assert.equal(r.statusCode, 400);
  assert.match(r.json().error, /si mesmo/);
});

test('o segredo prova quem é o dono do código; outro segredo é recusado', async () => {
  const h = mk();
  assert.equal((await sync(h, PROF, S_PROF)).ok, true); // registra o dono
  const r = await call(h, { action: 'sync', code: PROF, secret: secret(9) });
  assert.equal(r.statusCode, 403);
  const r2 = await call(h, { action: 'link', code: PROF, secret: secret(9), role: 'teacher', other: ALU });
  assert.equal(r2.statusCode, 403);
  assert.equal((await sync(h, PROF, S_PROF)).asTeacher.length, 0); // nada foi criado
});

test('entradas inválidas', async () => {
  const h = mk();
  assert.equal((await call(h, null)).statusCode, 400);
  assert.equal((await call(h, { action: 'sync', code: 'ABCD-1234', secret: S_PROF })).statusCode, 400);
  assert.equal((await call(h, { action: 'sync', code: PROF, secret: 'curto' })).statusCode, 400);
  assert.equal((await call(h, { action: 'link', code: PROF, secret: S_PROF, role: 'teacher', other: 'XXXX-XXXX' })).statusCode, 400);
  assert.equal((await call(h, { action: 'link', code: PROF, secret: S_PROF, role: 'chefe', other: ALU })).statusCode, 400);
  assert.equal((await call(h, { action: 'voar', code: PROF, secret: S_PROF, role: 'teacher', other: ALU })).statusCode, 400);
  const get = fakeRes();
  await h({ method: 'GET', headers: {}, socket: {} }, get);
  assert.equal(get.statusCode, 405);
});

test('qualquer lado pode desfazer o vínculo', async () => {
  const h = mk();
  await call(h, { action: 'link', code: PROF, secret: S_PROF, role: 'teacher', other: ALU });
  await call(h, { action: 'link', code: PROF, secret: S_PROF, role: 'teacher', other: ALU2 });
  // O aluno encerra:
  assert.equal((await call(h, { action: 'unlink', code: ALU, secret: S_ALU, role: 'student', other: PROF })).statusCode, 200);
  assert.deepEqual((await sync(h, PROF, S_PROF)).asTeacher.map((x) => x.code), [ALU2]);
  assert.equal((await sync(h, ALU, S_ALU)).asStudent.length, 0);
  // O professor encerra o outro:
  await call(h, { action: 'unlink', code: PROF, secret: S_PROF, role: 'teacher', other: ALU2 });
  assert.equal((await sync(h, PROF, S_PROF)).asTeacher.length, 0);
});

test('mesma pessoa pode ser professora de uns e aluna de outros', async () => {
  const h = mk();
  await call(h, { action: 'link', code: PROF, secret: S_PROF, role: 'teacher', other: ALU });
  await call(h, { action: 'link', code: PROF, secret: S_PROF, role: 'student', other: ALU2 });
  const r = await sync(h, PROF, S_PROF);
  assert.deepEqual(r.asTeacher.map((x) => x.code), [ALU]);
  assert.deepEqual(r.asStudent.map((x) => x.code), [ALU2]);
});

test('mudar o apelido atualiza o que o outro lado vê', async () => {
  const h = mk();
  await call(h, { action: 'link', code: ALU, secret: S_ALU, role: 'student', other: PROF, name: 'Bia' });
  await call(h, { action: 'sync', code: ALU, secret: S_ALU, name: 'Beatriz' });
  assert.equal((await sync(h, PROF, S_PROF)).asTeacher[0].name, 'Beatriz');
});

test('limite de alterações por hora', async () => {
  let t = 1_800_000_000_000;
  const h = mk({}, { now: () => t });
  let last;
  for (let i = 0; i < 62; i++) {
    last = await call(h, { action: 'link', code: PROF, secret: S_PROF, role: 'teacher', other: code(40000 + i) });
  }
  assert.equal(last.statusCode, 429);
});

test('apelido: limpa controle e corta o tamanho', async () => {
  const h = mk();
  await call(h, { action: 'link', code: ALU, secret: S_ALU, role: 'student', other: PROF, name: 'A\u0000B\n' + 'x'.repeat(100) });
  const n = (await sync(h, PROF, S_PROF)).asTeacher[0].name;
  assert.ok(n.length <= 40);
  assert.ok(!/[\u0000-\u001f]/.test(n));
});

test('a resposta nunca devolve segredos nem hashes', async () => {
  const h = mk();
  await call(h, { action: 'link', code: PROF, secret: S_PROF, role: 'teacher', other: ALU });
  const out = JSON.stringify(await sync(h, PROF, S_PROF));
  assert.ok(!out.includes(S_PROF));
  assert.ok(!out.includes('"h"'));
});
