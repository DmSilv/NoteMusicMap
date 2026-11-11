// Testes do suporte do painel (vínculo, agenda, código de liberação e aviso ao usuário), sem rede:
// `node --test api/support.test.js`
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
const PROF = code(11111), ALU = code(22222), OUTRO = code(44444);
const secret = (c, extra = '') => crypto.createHash('sha256').update('s' + c + extra).digest('hex');
const KEY = 'chave-de-admin-de-teste';
const HOUR = 3600000;

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
  const deps = { config: () => config({ ADMIN_KEY: KEY }), allowMemory: true, fetch: async () => ({ status: 200 }), now: () => NOW };
  return { l: link.makeHandler(deps), a: admin.makeHandler(deps) };
}
async function as(H, who, body, sec = secret(who)) {
  const res = fakeRes();
  await H.l({ method: 'POST', headers: { 'x-forwarded-for': '6.6.6.' + ++ipN }, body: { code: who, secret: sec, ...body }, socket: {} }, res);
  return res;
}
async function adm(H, body) {
  const res = fakeRes();
  await H.a({ method: 'POST', headers: { 'x-forwarded-for': '5.5.5.' + ++ipN, authorization: 'Bearer ' + KEY }, body, socket: {} }, res);
  return res;
}
async function vincula(H, prof, aluno) {
  await as(H, aluno, { action: 'sync', name: 'Aluno ' + aluno.slice(0, 2) });
  await as(H, prof, { action: 'sync', name: 'Prof ' + prof.slice(0, 2) });
  assert.equal((await as(H, prof, { action: 'link', role: 'teacher', other: aluno })).statusCode, 200);
}

test('detalhe mostra os dois papéis e a última atividade dos vinculados', async () => {
  const H = mk();
  await vincula(H, PROF, ALU);
  await vincula(H, OUTRO, PROF); // PROF também é aluno de OUTRO
  const d = (await adm(H, { action: 'detail', code: PROF })).json();
  assert.equal(d.alsoStudent, true);
  assert.equal(d.students[0].code, ALU);
  assert.equal(d.teachers[0].code, OUTRO);
  assert.ok(d.students[0].last > 0 && d.students[0].since > 0);
  assert.equal(d.support.pendingUntil, 0);
});

test('suporte encerra o vínculo nos dois lados, registra e avisa os dois', async () => {
  const H = mk();
  await vincula(H, PROF, ALU);
  assert.equal((await adm(H, { action: 'unlink', code: PROF, other: ALU, as: 'student' })).statusCode, 404); // papel trocado
  assert.equal((await adm(H, { action: 'unlink', code: PROF, other: ALU, as: 'teacher' })).statusCode, 200);
  const sp = (await as(H, PROF, { action: 'sync' })).json();
  const sa = (await as(H, ALU, { action: 'rev' })).json();
  assert.equal(sp.asTeacher.length, 0);
  assert.equal((await as(H, ALU, { action: 'sync' })).json().asStudent.length, 0);
  assert.equal(sp.sn.k, 'unlink');
  assert.match(sp.sn.x, /Aluno/);
  assert.equal(sa.sn.k, 'unlink'); // vale também na consulta barata
  const log = (await adm(H, { action: 'log' })).json().items;
  assert.equal(log[0].a, 'unlink');
  assert.equal(log[0].x, ALU);
  assert.equal((await adm(H, { action: 'unlink', code: PROF, other: ALU, as: 'teacher' })).statusCode, 404); // já não existe
});

test('sem aviso do suporte, a resposta do app não muda (compatibilidade)', async () => {
  const H = mk();
  await vincula(H, PROF, ALU);
  const r = (await as(H, PROF, { action: 'sync' })).json();
  assert.equal('sn' in r, false);
  assert.equal('sn' in (await as(H, PROF, { action: 'rev' })).json(), false);
});

test('agenda: o suporte lista e apaga um item; os dois lados são avisados', async () => {
  const H = mk();
  await vincula(H, PROF, ALU);
  const slot = { id: 'aula1', s: NOW + 48 * HOUR, d: 60, u: NOW };
  assert.equal((await as(H, PROF, { action: 'sched_put', other: ALU, slot })).statusCode, 200);
  const ag = (await adm(H, { action: 'agenda', code: PROF })).json();
  assert.equal(ag.classes.length, 1);
  assert.equal(ag.classes[0].student, ALU);
  assert.equal((await adm(H, { action: 'agenda', code: ALU })).json().received.length, 1);
  assert.equal((await adm(H, { action: 'agenda_del', code: PROF, kind: 'class', id: 'aula1' })).statusCode, 200);
  assert.equal((await adm(H, { action: 'agenda', code: PROF })).json().classes.length, 0);
  assert.equal((await adm(H, { action: 'agenda', code: ALU })).json().received.length, 0);
  assert.equal((await as(H, ALU, { action: 'rev' })).json().sn.k, 'agenda');
  assert.equal((await as(H, PROF, { action: 'rev' })).json().sn.k, 'agenda');
  assert.equal((await adm(H, { action: 'agenda_del', code: PROF, kind: 'class', id: 'aula1' })).statusCode, 404);
  assert.equal((await adm(H, { action: 'agenda_del', code: PROF, kind: 'class', id: '../x' })).statusCode, 400);
});

test('código de suporte: libera a conta em outro aparelho, uma única vez', async () => {
  const H = mk();
  await vincula(H, PROF, ALU);
  const gen = (await adm(H, { action: 'support_code', code: ALU })).json();
  assert.match(gen.supportCode, /^[A-Z2-9]{4}-[A-Z2-9]{4}$/);
  assert.equal(gen.until, NOW + 24 * HOUR);
  // o painel só vê "pendente até", nunca o código
  const det = JSON.stringify((await adm(H, { action: 'detail', code: ALU })).json());
  assert.equal(det.includes(gen.supportCode.replace('-', '')), false);
  assert.equal(JSON.parse(det).support.pendingUntil, gen.until);

  const novo = secret(ALU, 'novo');
  // código errado: recusa
  assert.equal((await as(H, ALU, { action: 'claim', support: 'AAAA-BBBB' }, novo)).statusCode, 403);
  // código certo: o aparelho novo vira o dono
  assert.equal((await as(H, ALU, { action: 'claim', support: gen.supportCode.toLowerCase() }, novo)).statusCode, 200);
  assert.equal((await as(H, ALU, { action: 'sync' }, novo)).statusCode, 200);
  assert.equal((await as(H, ALU, { action: 'sync' })).statusCode, 403); // o segredo antigo deixou de valer
  // os vínculos continuam
  assert.equal((await as(H, ALU, { action: 'sync' }, novo)).json().asStudent[0].code, PROF);
  // uso único
  assert.equal((await as(H, ALU, { action: 'claim', support: gen.supportCode }, secret(ALU, 'outro'))).statusCode, 403);
  assert.equal((await adm(H, { action: 'detail', code: ALU })).json().support.pendingUntil, 0);
});

test('código de suporte vence em 24 h e pode ser cancelado; sem código gerado não há liberação', async () => {
  const H = mk();
  await vincula(H, PROF, ALU);
  assert.equal((await as(H, ALU, { action: 'claim', support: 'AAAA-BBBB' }, secret(ALU, 'n'))).statusCode, 403);
  const g1 = (await adm(H, { action: 'support_code', code: ALU })).json();
  NOW += 24 * HOUR + 1000;
  assert.equal((await as(H, ALU, { action: 'claim', support: g1.supportCode }, secret(ALU, 'n'))).statusCode, 403);
  const g2 = (await adm(H, { action: 'support_code', code: ALU })).json();
  assert.equal((await adm(H, { action: 'support_cancel', code: ALU })).statusCode, 200);
  assert.equal((await as(H, ALU, { action: 'claim', support: g2.supportCode }, secret(ALU, 'n'))).statusCode, 403);
  assert.equal((await adm(H, { action: 'support_code', code: code(99999) })).statusCode, 404); // perfil que não existe
});

test('tentativas erradas do código de suporte são limitadas', async () => {
  const H = mk();
  await vincula(H, PROF, ALU);
  await adm(H, { action: 'support_code', code: ALU });
  let last = 0;
  for (let i = 0; i < 12; i++) last = (await as(H, ALU, { action: 'claim', support: 'ZZZZ-ZZZ' + (i % 9 + 2) }, secret(ALU, 'n'))).statusCode;
  assert.equal(last, 429);
});

test('o painel exige a chave de admin para todas as ações de suporte', async () => {
  const H = mk();
  await vincula(H, PROF, ALU);
  for (const action of ['unlink', 'agenda', 'agenda_del', 'support_code', 'support_cancel']) {
    const res = fakeRes();
    await H.a({ method: 'POST', headers: { 'x-forwarded-for': '5.5.5.' + ++ipN, authorization: 'Bearer errada' }, body: { action, code: ALU }, socket: {} }, res);
    assert.equal(res.statusCode, 401, action);
  }
});
