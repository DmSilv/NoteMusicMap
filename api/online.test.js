// Testes da aula online (link da aula, modo online/presencial, link padrão): `node --test api/online.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const link = require('./link');
const admin = require('./admin');
const ag = require('./_lib/agenda');
const features = require('./_lib/features');
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
const MEET = 'https://meet.google.com/abc-defg-hij';
let ipN = 0;
function fakeRes() {
  const r = { headers: {}, statusCode: 0, body: '' };
  r.setHeader = (k, v) => { r.headers[k] = v; };
  r.end = (b) => { r.body = b; };
  r.json = () => JSON.parse(r.body);
  return r;
}
function mk() {
  hashes.clear(); memory.clear(); resetMem(); features.resetCache();
  const cfg = config({ ADMIN_KEY: KEY });
  const deps = { config: () => cfg, allowMemory: true, fetch: async () => ({ status: 200 }), now: () => NOW };
  return { l: link.makeHandler(deps), a: admin.makeHandler(deps) };
}
async function as(H, who, body) {
  const res = fakeRes();
  await H.l({ method: 'POST', headers: { 'x-forwarded-for': '4.4.4.' + ++ipN }, body: { code: who, secret: secret(who), ...body }, socket: {} }, res);
  return res;
}
async function adm(H, body) {
  const res = fakeRes();
  await H.a({ method: 'POST', headers: { 'x-forwarded-for': '5.5.5.' + ++ipN, authorization: 'Bearer ' + KEY }, body, socket: {} }, res);
  return res;
}
async function setup(ligado = true) {
  const H = mk();
  for (const [who, nm] of [[PROF, 'Prof'], [ALU, 'Ana'], [ALU2, 'Bia']]) await as(H, who, { action: 'sync', name: nm });
  await as(H, PROF, { action: 'link', role: 'teacher', other: ALU });
  await as(H, PROF, { action: 'link', role: 'teacher', other: ALU2 });
  if (ligado) await adm(H, { action: 'feature_grant', id: 'aula_online', code: PROF });
  return H;
}
const slot = (id, extra = {}) => ({ id, s: NOW + 3 * DAY, d: 60, u: NOW, ...extra });
const put = (H, s, other = ALU) => as(H, PROF, { action: 'sched_put', other, slot: s });
const mine = async (H, who) => (await as(H, who, { action: 'sched' })).json().slots;
const teacherSide = async (H) => (await as(H, PROF, { action: 'picks' })).json();

test('o filtro do link: só https de verdade, sem usuário e sem enfeites', () => {
  assert.equal(ag.cleanMeetUrl(MEET), MEET);
  assert.ok(ag.cleanMeetUrl('https://zoom.us/j/123456789?pwd=abc'));
  assert.ok(ag.cleanMeetUrl('https://minha-sala.exemplo.com.br/aula'));
  assert.equal(ag.cleanMeetUrl('http://meet.google.com/abc'), null);
  assert.equal(ag.cleanMeetUrl('javascript:alert(1)'), null);
  assert.equal(ag.cleanMeetUrl('https://user:pw@meet.google.com/abc'), null);
  assert.equal(ag.cleanMeetUrl('https://meet.google.com/abc def'), null);
  assert.equal(ag.cleanMeetUrl('https://localhost/sala'), null);
  assert.equal(ag.cleanMeetUrl('https://' + 'a'.repeat(310) + '.com'), null);
  assert.equal(ag.cleanMeetUrl(''), null);
  assert.equal(ag.cleanMeetUrl(null), null);
});

test('sem a chave ligada o servidor ignora modo e link', async () => {
  const H = await setup(false);
  assert.equal((await put(H, slot('aaaa', { m: 'o', l: MEET }))).statusCode, 200);
  const [c] = await mine(H, ALU);
  assert.equal(c.m, undefined);
  assert.equal(c.l, undefined);
});

test('com a chave: a aula online e o link chegam ao aluno vinculado', async () => {
  const H = await setup();
  assert.equal((await put(H, slot('aaaa', { m: 'o', l: MEET }))).statusCode, 200);
  const [c] = await mine(H, ALU);
  assert.equal(c.m, 'o');
  assert.equal(c.l, MEET);
  assert.deepEqual(await mine(H, ALU2), []); // outro aluno não recebe
});

test('presencial fica como presencial e não carrega link', async () => {
  const H = await setup();
  await put(H, slot('aaaa', { m: 'p', l: MEET }));
  const [c] = await mine(H, ALU);
  assert.equal(c.m, 'p');
  assert.equal(c.l, undefined);
});

test('link inválido é descartado, mas a aula continua online (link pode vir depois)', async () => {
  const H = await setup();
  await put(H, slot('aaaa', { m: 'o', l: 'javascript:alert(1)' }));
  const [c] = await mine(H, ALU);
  assert.equal(c.m, 'o');
  assert.equal(c.l, undefined);
});

test('o professor põe o link depois, e troca ou tira o link', async () => {
  const H = await setup();
  await put(H, slot('aaaa', { m: 'o' }));
  assert.equal((await mine(H, ALU))[0].l, undefined);
  await put(H, slot('aaaa', { m: 'o', l: MEET, u: NOW + 1 }));
  assert.equal((await mine(H, ALU))[0].l, MEET);
  await put(H, slot('aaaa', { m: 'o', l: 'https://zoom.us/j/1', u: NOW + 2 }));
  assert.equal((await mine(H, ALU))[0].l, 'https://zoom.us/j/1');
  await put(H, slot('aaaa', { m: 'o', u: NOW + 3 }));
  assert.equal((await mine(H, ALU))[0].l, undefined);
});

test('app antigo (sem a chave m) edita a aula e NÃO apaga o modo nem o link', async () => {
  const H = await setup();
  await put(H, slot('aaaa', { m: 'o', l: MEET }));
  await put(H, slot('aaaa', { d: 45, u: NOW + 5 })); // pedido de um app antigo: só os campos que ele conhece
  const [c] = await mine(H, ALU);
  assert.equal(c.d, 45);
  assert.equal(c.m, 'o');
  assert.equal(c.l, MEET);
});

test('desligar o recurso não apaga o que já existe', async () => {
  const H = await setup();
  await put(H, slot('aaaa', { m: 'o', l: MEET }));
  await adm(H, { action: 'feature_set', id: 'aula_online', mode: 'off' });
  await put(H, slot('aaaa', { d: 30, m: 'p', u: NOW + 9 }));
  const [c] = await mine(H, ALU);
  assert.equal(c.d, 30);
  assert.equal(c.m, 'o'); // com o recurso desligado o pedido não muda o modo
  assert.equal(c.l, MEET);
});

test('horário livre online com link: quem pega recebe a aula online com o link', async () => {
  const H = await setup();
  const open = slot('hv01', { m: 'o', l: MEET, w: 1 });
  assert.equal((await as(H, PROF, { action: 'avail_put', slot: open })).statusCode, 200);
  const r = await as(H, ALU, { action: 'avail_take', other: PROF, slot: 'hv01' });
  assert.equal(r.statusCode, 200);
  assert.equal(r.json().slot.m, 'o');
  const [c] = await mine(H, ALU);
  assert.equal(c.m, 'o');
  assert.equal(c.l, MEET);
  const t = await teacherSide(H);
  const mineT = (t.slots || []).find((x) => x.sc === ALU || x.m === 'o');
  assert.ok(mineT && mineT.m === 'o');
});

test('horário livre online sem link usa o link padrão do professor', async () => {
  const H = await setup();
  assert.equal((await as(H, PROF, { action: 'meet_set', link: MEET })).statusCode, 200);
  await as(H, PROF, { action: 'avail_put', slot: slot('hv02', { m: 'o' }) });
  await as(H, ALU, { action: 'avail_take', other: PROF, slot: 'hv02' });
  assert.equal((await mine(H, ALU))[0].l, MEET);
});

test('horário livre presencial não ganha link', async () => {
  const H = await setup();
  await as(H, PROF, { action: 'meet_set', link: MEET });
  await as(H, PROF, { action: 'avail_put', slot: slot('hv03', { m: 'p' }) });
  await as(H, ALU, { action: 'avail_take', other: PROF, slot: 'hv03' });
  const [c] = await mine(H, ALU);
  assert.equal(c.m, 'p');
  assert.equal(c.l, undefined);
});

test('link padrão: só com a chave, só link válido, volta na sincronização e dá para limpar', async () => {
  const off = await setup(false);
  assert.equal((await as(off, PROF, { action: 'meet_set', link: MEET })).statusCode, 403);
  const H = await setup();
  assert.equal((await as(H, PROF, { action: 'meet_set', link: 'http://meet.google.com/x' })).statusCode, 400);
  assert.equal((await as(H, PROF, { action: 'meet_set', link: MEET })).statusCode, 200);
  assert.equal((await as(H, PROF, { action: 'sync' })).json().ml, MEET);
  assert.equal((await as(H, ALU, { action: 'sync' })).json().ml, undefined); // aluno não recebe o link do professor assim
  assert.equal((await as(H, PROF, { action: 'meet_set', link: '' })).statusCode, 200);
  assert.equal((await as(H, PROF, { action: 'sync' })).json().ml, undefined);
});

test('o painel de suporte não mostra o link da aula', async () => {
  const H = await setup();
  await put(H, slot('aaaa', { m: 'o', l: MEET }));
  const r = (await adm(H, { action: 'agenda', code: PROF })).json();
  assert.ok(!JSON.stringify(r).includes('meet.google.com'));
});
