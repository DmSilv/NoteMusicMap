// Testes do funil de ativação e da comparação de agendas do painel: `node --test api/funnel.test.js`
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
const PROF = code(11), ALU = code(33), ALU2 = code(44);
const secret = (c) => crypto.createHash('sha256').update('s' + c).digest('hex');
const KEY = 'chave-de-admin-de-teste';
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
  const cfg = config({ ADMIN_KEY: KEY });
  const deps = { config: () => cfg, allowMemory: true, fetch: async () => ({ status: 200 }), now: () => NOW };
  return { l: link.makeHandler(deps), a: admin.makeHandler(deps) };
}
async function as(H, who, body) {
  const res = fakeRes();
  await H.l({ method: 'POST', headers: { 'x-forwarded-for': '4.4.4.' + ++ipN }, body: { code: who, secret: secret(who), ...body }, socket: {} }, res);
  return res;
}
async function adm(H, body, key = KEY) {
  const res = fakeRes();
  await H.a({ method: 'POST', headers: { 'x-forwarded-for': '5.5.5.' + ++ipN, authorization: 'Bearer ' + key }, body, socket: {} }, res);
  return res;
}
const funnel = async (H) => {
  const j = (await adm(H, { action: 'funnel' })).json();
  return Object.fromEntries(j.steps.map((s) => [s.k, s.n]));
};
const slot = (id, extra = {}) => ({ id, s: NOW + 3 * DAY, d: 60, u: NOW, ...extra });

async function setup() {
  const H = mk();
  for (const [who, nm] of [[PROF, 'Prof'], [ALU, 'Ana'], [ALU2, 'Bia']]) await as(H, who, { action: 'sync', name: nm });
  return H;
}

test('funil: começa zerado e conta cada perfil só uma vez em cada etapa', async () => {
  const H = await setup();
  let f = await funnel(H);
  assert.equal(f.linked, 0);
  assert.equal(f.klass, 0);
  await as(H, PROF, { action: 'link', role: 'teacher', other: ALU });
  f = await funnel(H);
  assert.equal(f.linked, 2); // o professor e o aluno
  await as(H, PROF, { action: 'link', role: 'teacher', other: ALU2 });
  f = await funnel(H);
  assert.equal(f.linked, 3); // o professor não conta de novo
  await as(H, PROF, { action: 'sched_put', other: ALU, slot: slot('aaaa') });
  await as(H, PROF, { action: 'sched_put', other: ALU2, slot: slot('bbbb', { s: NOW + 4 * DAY }) });
  f = await funnel(H);
  assert.equal(f.klass, 1);
});

test('funil: horário pego, tarefa enviada e tarefa concluída', async () => {
  const H = await setup();
  await as(H, PROF, { action: 'link', role: 'teacher', other: ALU });
  await as(H, PROF, { action: 'avail_put', slot: slot('hv01') });
  assert.equal((await as(H, ALU, { action: 'avail_take', other: PROF, slot: 'hv01' })).statusCode, 200);
  assert.equal((await funnel(H)).pick, 1);
  const les = { id: 'l1', t: NOW, d: 30, tasks: [{ id: 't1', title: 'Escala', k: 'scale', st: 0, pc: 7, oct: 1, goal: 0.8 }], notes: [] };
  const r = await as(H, PROF, { action: 'lesson', other: ALU, lesson: les });
  assert.equal(r.statusCode, 200, r.body);
  assert.equal((await funnel(H)).task, 1);
});

test('funil: a data de início aparece e o painel exige a chave', async () => {
  const H = await setup();
  await as(H, PROF, { action: 'link', role: 'teacher', other: ALU });
  const j = (await adm(H, { action: 'funnel' })).json();
  assert.equal(j.since, NOW);
  assert.ok(j.steps[0].n >= 3);
  assert.equal((await adm(H, { action: 'funnel' }, 'errada')).statusCode, 401);
});

test('comparar agendas: igual, falta no aluno, sobra no aluno e diferente', async () => {
  const H = await setup();
  await as(H, PROF, { action: 'link', role: 'teacher', other: ALU });
  await as(H, PROF, { action: 'sched_put', other: ALU, slot: slot('aaaa') });
  await as(H, PROF, { action: 'sched_put', other: ALU, slot: slot('bbbb', { s: NOW + 4 * DAY }) });
  let r = (await adm(H, { action: 'agenda_pair', code: PROF, other: ALU })).json();
  assert.equal(r.rows.length, 2);
  assert.ok(r.rows.every((x) => x.status === 'same'));
  // some uma cópia do lado do aluno (falta) e muda a outra (diferente), e cria uma que o professor não tem (sobra)
  const { createStore } = require('./_lib/store');
  const store = createStore(config({ ADMIN_KEY: KEY }), async () => ({ status: 200 }), () => NOW, { allowMemory: true });
  await store.hdel(`ss:${ALU}`, `${PROF}:aaaa`);
  await store.hset(`ss:${ALU}`, `${PROF}:bbbb`, JSON.stringify({ ...slot('bbbb', { s: NOW + 4 * DAY }), d: 30, tn: 'Prof' }));
  await store.hset(`ss:${ALU}`, `${PROF}:zzzz`, JSON.stringify({ ...slot('zzzz'), tn: 'Prof' }));
  r = (await adm(H, { action: 'agenda_pair', code: PROF, other: ALU })).json();
  const by = Object.fromEntries(r.rows.map((x) => [x.id, x.status]));
  assert.deepEqual(by, { aaaa: 'missing', bbbb: 'diff', zzzz: 'extra' });
  assert.equal(r.teacherCount, 2);
  assert.equal(r.studentCount, 2);
});

test('comparar agendas: código inválido é recusado e não mostra o link da aula', async () => {
  const H = await setup();
  assert.equal((await adm(H, { action: 'agenda_pair', code: PROF, other: 'XXXX' })).statusCode, 400);
  assert.equal((await adm(H, { action: 'agenda_pair', code: 'XXXX', other: ALU })).statusCode, 400);
  const r = (await adm(H, { action: 'agenda_pair', code: PROF, other: ALU })).json();
  assert.deepEqual(r.rows, []);
});
