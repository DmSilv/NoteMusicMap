// Pro de cortesia (painel) e limite de 3 alunos no plano grátis, sem rede: `node --test api/pro_gift.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const link = require('./link');
const admin = require('./admin');
const account = require('./account');
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
const PROF = code(11111);
const ALUNOS = [code(20001), code(20002), code(20003), code(20004), code(20005)];
const sec = (c) => require('node:crypto').createHash('sha256').update('s' + c).digest('hex');
const ADMIN = 'chave-admin', SUPPORT = 'chave-suporte';
const DAY = 86400000;
let NOW = Date.UTC(2026, 10, 24, 15, 0, 0);
let ipN = 0;

function mk() {
  hashes.clear(); memory.clear(); resetMem(); features.resetCache();
  NOW = Date.UTC(2026, 10, 24, 15, 0, 0);
  const deps = { config: () => config({ ADMIN_KEY: ADMIN, SUPPORT_KEY: SUPPORT }), allowMemory: true, fetch: async () => ({ ok: true, json: async () => ({}) }), now: () => NOW };
  return { l: link.makeHandler(deps), adm: admin.makeHandler(deps), a: account.makeHandler(deps) };
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
  await H.l({ method: 'POST', headers: { 'x-forwarded-for': '6.6.6.' + ++ipN }, body: { code: who, secret: sec(who), ...body }, socket: {} }, res);
  return res;
}
async function adm(H, body, key = ADMIN) {
  const res = fakeRes();
  await H.adm({ method: 'POST', headers: { 'x-forwarded-for': '5.5.5.' + ++ipN, ...(key ? { authorization: 'Bearer ' + key } : {}) }, body, socket: {} }, res);
  return res;
}
const born = (H, c) => as(H, c, { action: 'sync' });
const linkTo = (H, aluno) => as(H, PROF, { action: 'link', role: 'teacher', other: aluno, name: 'Prof' });

test('cortesia: o admin dá Pro por N dias, soma ao que já tem e aparece na lista', async () => {
  const H = mk();
  await born(H, PROF);
  const r = await adm(H, { action: 'pro_grant', code: PROF, days: 90 });
  assert.equal(r.statusCode, 200);
  assert.equal(r.json().until, NOW + 90 * DAY);
  assert.equal((await adm(H, { action: 'pro_grant', code: PROF, days: 30 })).json().until, NOW + 120 * DAY, 'soma ao que já tem');
  const l = (await adm(H, { action: 'pro_list' })).json();
  assert.equal(l.items.length, 1);
  assert.equal(l.items[0].code, PROF);
  assert.equal(l.items[0].active, true);
  assert.equal(l.items[0].src, 'gift');
  assert.equal(l.items[0].gift, 120);
});

test('cortesia: o professor vê o Pro no plano e na sincronização', async () => {
  const H = mk();
  await born(H, PROF);
  await adm(H, { action: 'pro_grant', code: PROF, days: 30 });
  const sync = (await as(H, PROF, { action: 'sync' })).json();
  assert.equal(sync.pro, NOW + 30 * DAY);
  const res = fakeRes();
  await H.a({ method: 'POST', headers: { 'x-forwarded-for': '9.9.9.1' }, body: { action: 'plan', code: PROF, secret: sec(PROF) }, socket: {} }, res);
  assert.equal(res.json().pro, true);
  assert.equal(res.json().daysLeft, 30);
});

test('cortesia vence sozinha e tirar o Pro funciona', async () => {
  const H = mk();
  await born(H, PROF);
  await adm(H, { action: 'pro_grant', code: PROF, days: 10 });
  NOW += 11 * DAY;
  assert.equal((await adm(H, { action: 'pro_list' })).json().items[0].active, false, 'venceu');
  await adm(H, { action: 'pro_grant', code: PROF, days: 10 });
  assert.equal((await adm(H, { action: 'pro_revoke', code: PROF })).statusCode, 200);
  assert.equal((await adm(H, { action: 'pro_list' })).json().items[0].active, false);
  assert.equal((await as(H, PROF, { action: 'sync' })).json().pro, undefined, 'sem Pro, a sincronização não manda a data');
});

test('cortesia: entradas ruins e permissões', async () => {
  const H = mk();
  await born(H, PROF);
  for (const days of [0, -5, 3651, 'abc', null, NaN, {}]) assert.equal((await adm(H, { action: 'pro_grant', code: PROF, days })).statusCode, 400, String(days));
  assert.equal((await adm(H, { action: 'pro_grant', code: 'abc', days: 5 })).statusCode, 400, 'código inválido');
  assert.equal((await adm(H, { action: 'pro_grant', code: code(99999), days: 5 })).statusCode, 404, 'perfil que não existe');
  for (const action of ['pro_grant', 'pro_revoke', 'pro_list']) {
    assert.equal((await adm(H, { action, code: PROF, days: 5 }, '')).statusCode, 401, action + ' sem chave');
    assert.equal((await adm(H, { action, code: PROF, days: 5 }, SUPPORT)).statusCode, 403, action + ' suporte');
  }
});

async function ligarLimite(H) {
  assert.equal((await adm(H, { action: 'feature_set', id: 'limite_alunos', mode: 'all' })).statusCode, 200);
  features.resetCache();
}

test('limite: com o recurso DESLIGADO (padrão) o professor vincula quantos alunos quiser', async () => {
  const H = mk();
  await born(H, PROF);
  for (const a of ALUNOS) { await born(H, a); assert.equal((await linkTo(H, a)).statusCode, 200); }
});

test('limite: ligado, o professor sem Pro vincula 3 e o 4º é recusado (402); quem já tem continua', async () => {
  const H = mk();
  await born(H, PROF);
  for (const a of ALUNOS) await born(H, a);
  await ligarLimite(H);
  for (const a of ALUNOS.slice(0, 3)) assert.equal((await linkTo(H, a)).statusCode, 200, 'os 3 primeiros entram');
  const r = await linkTo(H, ALUNOS[3]);
  assert.equal(r.statusCode, 402);
  assert.equal(r.json().error, 'student_limit');
  assert.equal((await linkTo(H, ALUNOS[0])).statusCode, 200, 'repetir um vínculo que já existe não conta');
});

test('limite: o aluno que lê o QR de um professor lotado recebe o mesmo aviso', async () => {
  const H = mk();
  await born(H, PROF);
  for (const a of ALUNOS) await born(H, a);
  await ligarLimite(H);
  for (const a of ALUNOS.slice(0, 3)) await linkTo(H, a);
  const r = await as(H, ALUNOS[3], { action: 'link', role: 'student', other: PROF, name: 'Aluno' });
  assert.equal(r.statusCode, 402);
});

test('limite: com Pro (pago ou cortesia) não há limite, e vencido o limite volta', async () => {
  const H = mk();
  await born(H, PROF);
  for (const a of ALUNOS) await born(H, a);
  await ligarLimite(H);
  await adm(H, { action: 'pro_grant', code: PROF, days: 30 });
  for (const a of ALUNOS) assert.equal((await linkTo(H, a)).statusCode, 200, 'com Pro entram todos');
  const extra = code(20006);
  await born(H, extra);
  NOW += 31 * DAY; // o Pro venceu
  assert.equal((await linkTo(H, extra)).statusCode, 402, 'sem Pro, quem já passou de 3 não adiciona outro');
});

test('limite: o recurso pode ser ligado só para um professor (lista) e os outros seguem livres', async () => {
  const H = mk();
  const OUTRO = code(11112);
  await born(H, PROF);
  await born(H, OUTRO);
  for (const a of ALUNOS) await born(H, a);
  assert.equal((await adm(H, { action: 'feature_set', id: 'limite_alunos', mode: 'list' })).statusCode, 200);
  assert.equal((await adm(H, { action: 'feature_grant', id: 'limite_alunos', code: PROF })).statusCode, 200);
  features.resetCache();
  for (const a of ALUNOS.slice(0, 3)) await linkTo(H, a);
  assert.equal((await linkTo(H, ALUNOS[3])).statusCode, 402, 'o professor da lista fica limitado');
  for (const a of ALUNOS) assert.equal((await as(H, OUTRO, { action: 'link', role: 'teacher', other: a, name: 'Outro' })).statusCode, 200, 'o outro professor não');
});

test('a sincronização do professor informa que o limite está ligado (o app usa para avisar antes)', async () => {
  const H = mk();
  await born(H, PROF);
  assert.ok(!(await as(H, PROF, { action: 'sync' })).json().ff.includes('limite_alunos'));
  await ligarLimite(H);
  assert.ok((await as(H, PROF, { action: 'sync' })).json().ff.includes('limite_alunos'));
});
