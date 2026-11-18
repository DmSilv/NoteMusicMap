// Pesquisa rápida no painel: quem respondeu (perfil), de qual aparelho; `node --test api/survey.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const link = require('./link');
const admin = require('./admin');
const feedback = require('./feedback');
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
const ANA = code(11111);
const secret = (c) => crypto.createHash('sha256').update('s' + c).digest('hex');
const KEY = 'chave-de-admin-de-teste';
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
  const deps = { config: () => config({ ADMIN_KEY: KEY, FEEDBACK_ADMIN_KEY: 'fk' }), allowMemory: true, fetch: async () => ({ status: 200 }), now: () => NOW };
  return { l: link.makeHandler(deps), a: admin.makeHandler(deps), f: feedback.makeHandler(deps) };
}
async function fb(H, dev, body) {
  const res = fakeRes();
  await H.f({ method: 'POST', headers: { 'x-forwarded-for': '4.4.4.' + ++ipN, 'x-device-id': dev }, body, socket: {} }, res);
  return res;
}
async function adm(H, body) {
  const res = fakeRes();
  await H.a({ method: 'POST', headers: { 'x-forwarded-for': '5.5.5.' + ++ipN, authorization: 'Bearer ' + KEY }, body, socket: {} }, res);
  return res;
}
async function profile(H, c, name) {
  const res = fakeRes();
  await H.l({ method: 'POST', headers: { 'x-forwarded-for': '6.6.6.' + ++ipN }, body: { action: 'sync', code: c, secret: secret(c), name }, socket: {} }, res);
}

test('resposta nova leva o perfil e aparece no painel com o nome e o aparelho', async () => {
  const H = mk();
  await profile(H, ANA, 'Ana');
  assert.equal((await fb(H, 'dev-ana', { kind: 'survey', qid: 'mais_usa', answer: 'Afinador', version: '1.0', platform: 'web', profile: ANA })).statusCode, 200);
  const r = (await adm(H, { action: 'survey' })).json();
  assert.equal(r.parts.length, 1);
  assert.equal(r.parts[0].code, ANA);
  assert.equal(r.parts[0].who.name, 'Ana');
  assert.equal(r.parts[0].answers[0].q, 'mais_usa');
  assert.equal(r.parts[0].answers[0].a, 'Afinador');
  assert.equal(r.summary.surveys.mais_usa.total, 1);
});

test('resposta antiga (sem perfil) ganha dono quando o aparelho se identifica depois', async () => {
  const H = mk();
  await profile(H, ANA, 'Ana');
  await fb(H, 'dev-ana-2', { kind: 'rating', rating: 4, comment: 'comentario-antigo' });
  const find = async () => (await adm(H, { action: 'survey' })).json().parts.filter((x) => x.c === 'comentario-antigo');
  let rows = await find();
  assert.equal(rows.length, 1);
  assert.equal(rows[0].code, '');
  assert.equal((await fb(H, 'dev-ana-2', { kind: 'identify', profile: ANA })).statusCode, 200);
  rows = await find();
  assert.equal(rows.length, 1, 'identificar não cria resposta nova');
  assert.equal(rows[0].code, ANA);
  assert.equal(rows[0].who.name, 'Ana');
  assert.equal(rows[0].r, 4);
});

test('identificar sem perfil válido é recusado; código inválido na resposta é ignorado', async () => {
  const H = mk();
  assert.equal((await fb(H, 'd-x1', { kind: 'identify', profile: 'lixo' })).statusCode, 400);
  assert.equal((await fb(H, 'd-x1', { kind: 'identify' })).statusCode, 400);
  assert.equal((await fb(H, 'd-x1', { kind: 'survey', qid: 'melhorar', answer: 'texto-invalido', profile: 'A0A0-1111' })).statusCode, 200);
  const row = (await adm(H, { action: 'survey' })).json().parts.find((x) => x.answers.some((y) => y.a === 'texto-invalido'));
  assert.equal(row.code, '');
});

test('só o administrador vê a pesquisa', async () => {
  const H = mk();
  const res = fakeRes();
  await H.a({ method: 'POST', headers: { 'x-forwarded-for': '5.5.5.1', authorization: 'Bearer errada' }, body: { action: 'survey' }, socket: {} }, res);
  assert.equal(res.statusCode, 401);
});

// ---------------- participações, limite e disponibilidade ----------------
async function pub(H) {
  const res = fakeRes();
  await H.f({ method: 'GET', url: '/api/feedback?survey=1', headers: { 'x-forwarded-for': '7.7.7.' + ++ipN }, socket: {} }, res);
  return res;
}
const QS = [
  { k: 'choice', q: 'Qual recurso?', r: true, o: ['Afinador', 'Metrônomo'] },
  { k: 'text', q: 'O que melhorar?' },
];

test('as respostas de um envio viram UMA participação; envios antigos sem id juntam por aparelho e tempo', async () => {
  const H = mk();
  const b = { version: '1', platform: 'web', sv: 'pesq1', pid: 'abcd1234efgh' };
  await fb(H, 'dev-a', { ...b, kind: 'survey', qid: 'p1_1', answer: 'Afinador' });
  await fb(H, 'dev-a', { ...b, kind: 'survey', qid: 'p1_2', answer: 'Mais escalas' });
  await fb(H, 'dev-a', { ...b, kind: 'rating', rating: 5, pid: 'zzzz9999aaaa' });
  // app antigo: duas linhas quase juntas
  await fb(H, 'dev-old', { kind: 'survey', qid: 'mais_usa', answer: 'Grade' });
  await fb(H, 'dev-old', { kind: 'survey', qid: 'melhorar', answer: 'x' });
  const r = (await adm(H, { action: 'survey' })).json();
  r.parts = r.parts.filter((p) => p.sv === 'pesq1' || p.answers.some((x) => x.a === 'Grade') || (p.kind === 'rating' && p.r === 5)); // a lista de respostas dura entre testes
  assert.equal(r.parts.length, 3);
  const nova = r.parts.find((p) => p.sv === 'pesq1');
  assert.deepEqual(nova.answers.map((x) => x.a), ['Afinador', 'Mais escalas']);
  assert.equal(r.parts.find((p) => p.kind === 'rating').r, 5);
  const velha = r.parts.find((p) => p.answers.some((x) => x.a === 'Grade'));
  assert.equal(velha.answers.length, 2);
});

test('limite: 1 por pesquisa por aparelho e no máximo 3 participações por mês', async () => {
  const H = mk();
  const send = (dev, sv, pid, q = 'q_1') => fb(H, dev, { kind: 'survey', qid: q, answer: 'a', sv, pid });
  assert.equal((await send('dev-l', 'sa', 'aaaaaaaa1')).statusCode, 200);
  assert.equal((await send('dev-l', 'sa', 'aaaaaaaa1', 'q_2')).statusCode, 200, 'outra pergunta do mesmo envio passa');
  const dup = await send('dev-l', 'sa', 'bbbbbbbb2');
  assert.equal(dup.statusCode, 429);
  assert.equal(dup.json().limited, 'dup');
  assert.equal((await send('dev-l', 'sb', 'cccccccc3')).statusCode, 200);
  assert.equal((await send('dev-l', 'sc', 'dddddddd4')).statusCode, 200);
  const mes = await send('dev-l', 'sd', 'eeeeeeee5');
  assert.equal(mes.statusCode, 429);
  assert.equal(mes.json().limited, 'month');
  assert.equal((await send('dev-outro', 'sa', 'ffffffff6')).statusCode, 200, 'outro aparelho não é afetado');
  NOW += 40 * 86400000;
  assert.equal((await send('dev-l', 'sd', 'gggggggg7')).statusCode, 200, 'no mês seguinte volta a poder');
  // app antigo (sem sv/pid) não é limitado por isso
  assert.equal((await fb(H, 'dev-l', { kind: 'survey', qid: 'mais_usa', answer: 'Grade' })).statusCode, 200);
});

test('disponibilidade: rascunho não vai ao app; liberar, agendar e retirar mudam o que o app recebe', async () => {
  const H = mk();
  assert.equal((await pub(H)).json().survey, null);
  const r = (await adm(H, { action: 'sv_save', t: 'Pesquisa de teste', qs: QS })).json();
  assert.equal(r.ok, true);
  assert.equal((await pub(H)).json().survey, null, 'rascunho');
  assert.equal((await adm(H, { action: 'sv_state', id: r.id, st: 'live' })).statusCode, 200);
  let res = await pub(H);
  assert.match(res.headers['Cache-Control'], /s-maxage=300/);
  const sv = res.json().survey;
  assert.equal(sv.id, r.id);
  assert.equal(sv.qs.length, 2);
  assert.equal(sv.qs[0].o[0].v, 'Afinador');
  assert.equal(sv.max, 3);
  // agenda: liberar daqui a 1 dia e retirar em 2
  await adm(H, { action: 'sv_save', id: r.id, t: 'Pesquisa de teste', qs: sv.qs, from: NOW + 86400000, to: NOW + 2 * 86400000 });
  assert.equal((await pub(H)).json().survey, null, 'ainda não chegou a data');
  NOW += 86400000 + 1000;
  assert.equal((await pub(H)).json().survey.id, r.id, 'chegou a data de liberar');
  NOW += 86400000;
  assert.equal((await pub(H)).json().survey, null, 'passou a data de retirar');
  const list = (await adm(H, { action: 'survey' })).json();
  assert.equal(list.defs[0].status, 'closed');
  assert.ok(list.defs[0].h.length >= 3, 'histórico guarda criação, edição e liberação');
  await adm(H, { action: 'sv_state', id: r.id, st: 'off' });
  assert.equal((await adm(H, { action: 'sv_delete', id: r.id })).statusCode, 200);
  assert.equal((await adm(H, { action: 'survey' })).json().defs.length, 0);
});

test('pesquisa inválida é recusada e o modelo pronto aparece só uma vez', async () => {
  const H = mk();
  assert.equal((await adm(H, { action: 'sv_save', t: '', qs: QS })).statusCode, 400);
  assert.equal((await adm(H, { action: 'sv_save', t: 'x', qs: [] })).statusCode, 400);
  assert.equal((await adm(H, { action: 'sv_save', t: 'x', qs: [{ k: 'choice', q: 'a', o: ['so uma'] }] })).statusCode, 400);
  assert.equal((await adm(H, { action: 'sv_save', t: 'x', qs: QS, from: 5000, to: 4000 })).statusCode, 400);
  let l = (await adm(H, { action: 'survey' })).json();
  assert.equal(l.suggestions.length, 1);
  const seed = l.suggestions[0];
  const r = (await adm(H, { action: 'sv_save', t: seed.t, qs: seed.qs, k: seed.k })).json();
  assert.equal(r.ok, true);
  l = (await adm(H, { action: 'survey' })).json();
  assert.equal(l.suggestions.length, 0);
  assert.equal(l.defs[0].qs[0].id, 'mais_usa', 'o modelo mantém os ids das perguntas antigas');
});
