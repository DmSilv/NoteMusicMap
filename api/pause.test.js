// Aluno pausado, vários professores (conflito de horário) e resumo de estudo por professor: `node --test api/pause.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const link = require('./link');
const admin = require('./admin');
const { config } = require('./_lib/config');
const features = require('./_lib/features');
const { hashes, memory } = require('./_lib/store');
const { resetMem } = require('./_lib/store_cmd');

const A = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
function code(seed) {
  let p = '', x = seed;
  for (let i = 0; i < 7; i++) { p += A[x % 32]; x = Math.floor(x / 32) + 7 + i; }
  let s = 0;
  for (let i = 0; i < 7; i++) s += A.indexOf(p[i]) * (2 * i + 1);
  const c = p + A[s % 32];
  return `${c.slice(0, 4)}-${c.slice(4)}`;
}
const PROF = code(11111), PROF2 = code(44444);
const ALU = code(22222), ALU2 = code(33333);
const MAIS = [code(20001), code(20002), code(20003), code(20004)];
const sec = (c) => crypto.createHash('sha256').update('s' + c).digest('hex');
const ADMIN = 'chave-admin';
const DAY = 86400000;
let NOW = 1_800_000_000_000;
let ipN = 0;

function mk() {
  hashes.clear(); memory.clear(); resetMem(); features.resetCache();
  NOW = 1_800_000_000_000;
  const deps = { config: () => config({ ADMIN_KEY: ADMIN }), allowMemory: true, fetch: async () => ({ ok: true, status: 200, json: async () => ({}) }), now: () => NOW };
  return { l: link.makeHandler(deps), adm: admin.makeHandler(deps) };
}
function fakeRes() {
  const r = { headers: {}, statusCode: 0, body: '' };
  r.setHeader = (k, v) => { r.headers[k] = v; };
  r.end = (b) => { r.body = b; };
  r.json = () => JSON.parse(r.body);
  return r;
}
async function as(H, who, body) {
  const res = fakeRes();
  await H.l({ method: 'POST', headers: { 'x-forwarded-for': '4.4.4.' + ++ipN }, body: { code: who, secret: sec(who), ...body }, socket: {} }, res);
  return res;
}
async function adm(H, body) {
  const res = fakeRes();
  await H.adm({ method: 'POST', headers: { 'x-forwarded-for': '3.3.3.' + ++ipN, authorization: 'Bearer ' + ADMIN }, body, socket: {} }, res);
  return res;
}
const born = (H, c) => as(H, c, { action: 'sync' });
const linkT = (H, teacher, aluno) => as(H, teacher, { action: 'link', role: 'teacher', other: aluno, name: 'Prof' });
const pause = (H, aluno, on, teacher = PROF) => as(H, teacher, { action: 'pause', role: 'teacher', other: aluno, on });
const lesson = (id) => ({ id, t: NOW, at: NOW, n: 'Aula', tasks: [{ id: 't1', k: 'free', t: 'Estudar' }] });
const slot = (id, s) => ({ id, s, d: 60, u: NOW });
const open = (id, s) => ({ id, s, d: 60, u: NOW });
async function ligarLimite(H) {
  assert.equal((await adm(H, { action: 'feature_set', id: 'limite_alunos', mode: 'all' })).statusCode, 200);
  features.resetCache();
}

test('pausar: o aluno aparece como pausado nos dois lados e o histórico fica', async () => {
  const H = mk();
  await born(H, ALU);
  await linkT(H, PROF, ALU);
  assert.equal((await pause(H, ALU, true)).json().paused, true);
  const t = (await as(H, PROF, { action: 'sync' })).json();
  assert.equal(t.asTeacher.length, 1);
  assert.equal(t.asTeacher[0].pz, 1);
  const a = (await as(H, ALU, { action: 'sync' })).json();
  assert.equal(a.asStudent[0].pz, 1);
  assert.equal(a.asStudent[0].code, PROF, 'o vínculo continua');
  assert.ok(a.kr > 0);
  // reativar limpa a marca
  assert.equal((await pause(H, ALU, false)).json().paused, false);
  assert.equal((await as(H, ALU, { action: 'sync' })).json().asStudent[0].pz, undefined);
});

test('pausar: só o professor, só aluno vinculado e repetir não muda nada', async () => {
  const H = mk();
  await born(H, ALU);
  await born(H, ALU2);
  await linkT(H, PROF, ALU);
  assert.equal((await as(H, ALU, { action: 'pause', role: 'student', other: PROF, on: true })).statusCode, 403, 'o aluno não pausa a si mesmo');
  assert.equal((await pause(H, ALU2, true)).statusCode, 404, 'aluno que não é dele');
  assert.equal((await pause(H, ALU, true)).statusCode, 200);
  assert.equal((await pause(H, ALU, true)).statusCode, 200, 'repetir é inofensivo');
});

test('pausado não recebe aula, nem aula marcada, nem pega horário; reativar libera', async () => {
  const H = mk();
  await born(H, ALU);
  await linkT(H, PROF, ALU);
  await pause(H, ALU, true);
  const l = await as(H, PROF, { action: 'lesson', other: ALU, lesson: lesson('p1') });
  assert.equal(l.statusCode, 409);
  assert.equal(l.json().error, 'student_paused');
  const s = await as(H, PROF, { action: 'sched_put', other: ALU, slot: slot('c1', NOW + 3 * DAY) });
  assert.equal(s.json().error, 'student_paused');
  await as(H, PROF, { action: 'avail_put', slot: open('h1', NOW + 3 * DAY) });
  const t = await as(H, ALU, { action: 'avail_take', other: PROF, slot: 'h1' });
  assert.equal(t.json().error, 'student_paused');
  await pause(H, ALU, false);
  assert.equal((await as(H, PROF, { action: 'lesson', other: ALU, lesson: lesson('p2') })).statusCode, 200);
});

test('limite grátis: pausado não ocupa vaga; reativar com a vaga cheia dá 402', async () => {
  const H = mk();
  await born(H, PROF);
  for (const a of [ALU, ...MAIS]) await born(H, a);
  await ligarLimite(H);
  for (const a of [ALU, MAIS[0], MAIS[1]]) assert.equal((await linkT(H, PROF, a)).statusCode, 200);
  assert.equal((await linkT(H, PROF, MAIS[2])).statusCode, 402, 'cheio');
  await pause(H, ALU, true);
  assert.equal((await linkT(H, PROF, MAIS[2])).statusCode, 200, 'o pausado liberou a vaga');
  const r = await pause(H, ALU, false);
  assert.equal(r.statusCode, 402, 'sem vaga para reativar');
  assert.equal(r.json().error, 'student_limit');
  assert.ok((await as(H, PROF, { action: 'sync' })).json().asTeacher.find((x) => x.code === ALU).pz, 'continua pausado');
  await adm(H, { action: 'pro_grant', code: PROF, days: 30 });
  assert.equal((await pause(H, ALU, false)).statusCode, 200, 'com Pro reativa');
});

test('o apelido do professor mudar não perde a pausa', async () => {
  const H = mk();
  await born(H, ALU);
  await linkT(H, PROF, ALU);
  await pause(H, ALU, true);
  await as(H, PROF, { action: 'sync', name: 'Novo Nome' });
  assert.equal((await as(H, ALU, { action: 'sync' })).json().asStudent[0].pz, 1);
});

test('vários professores: o aluno não pega horário que bate com aula de OUTRO professor', async () => {
  const H = mk();
  await born(H, ALU);
  await linkT(H, PROF, ALU);
  await linkT(H, PROF2, ALU);
  const when = NOW + 3 * DAY;
  await as(H, PROF, { action: 'avail_put', slot: open('a1', when) });
  await as(H, PROF2, { action: 'avail_put', slot: open('b1', when + 30 * 60000) });
  assert.equal((await as(H, ALU, { action: 'avail_take', other: PROF, slot: 'a1' })).statusCode, 200);
  const r = await as(H, ALU, { action: 'avail_take', other: PROF2, slot: 'b1' });
  assert.equal(r.statusCode, 409);
  assert.equal(r.json().error, 'student_conflict');
  // horário que não bate funciona
  await as(H, PROF2, { action: 'avail_put', slot: open('b2', when + 3 * 3600000) });
  assert.equal((await as(H, ALU, { action: 'avail_take', other: PROF2, slot: 'b2' })).statusCode, 200);
});

test('vários professores: o professor que marca aula em cima de outra recebe o aviso "clash"', async () => {
  const H = mk();
  await born(H, ALU);
  await linkT(H, PROF, ALU);
  await linkT(H, PROF2, ALU);
  const when = NOW + 3 * DAY;
  const a = await as(H, PROF, { action: 'sched_put', other: ALU, slot: slot('c1', when) });
  assert.equal(a.json().clash, undefined);
  const b = await as(H, PROF2, { action: 'sched_put', other: ALU, slot: slot('c2', when + 15 * 60000) });
  assert.equal(b.statusCode, 200);
  assert.equal(b.json().clash, 1);
  const c = await as(H, PROF2, { action: 'sched_put', other: ALU, slot: slot('c3', when + 5 * 3600000) });
  assert.equal(c.json().clash, undefined);
});

const resumo = { w: '2026-11-23', m: 120, g: 30, d: 4, a: 80, tk: 3, tt: 5, n: 7 };

test('resumo de estudo: sem "to" todos os professores veem; com "to" só os escolhidos', async () => {
  const H = mk();
  await born(H, ALU);
  await linkT(H, PROF, ALU);
  await linkT(H, PROF2, ALU);
  await as(H, ALU, { action: 'study_put', study: resumo });
  assert.ok((await as(H, PROF, { action: 'study_get' })).json().study[ALU], 'antigo: todos');
  assert.ok((await as(H, PROF2, { action: 'study_get' })).json().study[ALU]);
  await as(H, ALU, { action: 'study_put', study: resumo, to: [PROF2] });
  assert.equal((await as(H, PROF, { action: 'study_get' })).json().study[ALU], undefined, 'PROF fora da lista');
  assert.ok((await as(H, PROF2, { action: 'study_get' })).json().study[ALU]);
  await as(H, ALU, { action: 'study_put', study: resumo, to: [] });
  assert.equal((await as(H, PROF2, { action: 'study_get' })).json().study[ALU], undefined, 'lista vazia: ninguém');
  await as(H, ALU, { action: 'study_put', study: resumo });
  assert.ok((await as(H, PROF, { action: 'study_get' })).json().study[ALU], 'sem "to" volta a valer para todos');
});

test('resumo de estudo: aluno pausado não aparece para o professor', async () => {
  const H = mk();
  await born(H, ALU);
  await linkT(H, PROF, ALU);
  await as(H, ALU, { action: 'study_put', study: resumo });
  await pause(H, ALU, true);
  assert.equal((await as(H, PROF, { action: 'study_get' })).json().study[ALU], undefined);
});
