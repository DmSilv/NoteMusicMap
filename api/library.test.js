// Testes do Acervo e Repertório do professor (só links): `node --test api/library.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const link = require('./link');
const admin = require('./admin');
const lib = require('./_lib/library');
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
const PROF = code(11), OUTRO = code(22), ALU = code(33), ALU2 = code(44), ESTR = code(55);
const secret = (c) => crypto.createHash('sha256').update('s' + c).digest('hex');
const KEY = 'chave-de-admin-de-teste';
let ipN = 0;
function fakeRes() {
  const r = { headers: {}, statusCode: 0, body: '' };
  r.setHeader = (k, v) => { r.headers[k] = v; };
  r.end = (b) => { r.body = b; };
  r.json = () => JSON.parse(r.body);
  return r;
}
function mk(testers = PROF) {
  hashes.clear(); memory.clear(); resetMem();
  const cfg = config({ ADMIN_KEY: KEY, LIBRARY_TESTERS: testers });
  const deps = { config: () => cfg, allowMemory: true, fetch: async () => ({ status: 200 }), now: () => 1_800_000_000_000 };
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
const item = (over = {}) => ({ id: 'i' + Math.random().toString(36).slice(2, 8), k: 'a', f: 'Wohlfahrt', t: 'Estudos op. 45', a: 'Franz Wohlfahrt', u: 'https://drive.google.com/file/d/abc123/view', ok: true, ...over });
async function setup() {
  const H = mk();
  for (const [who, nm] of [[PROF, 'Vinícius'], [ALU, 'Ana'], [ALU2, 'Bia'], [ESTR, 'Estranho']]) await as(H, who, { action: 'sync', name: nm });
  await as(H, PROF, { action: 'link', role: 'teacher', other: ALU });
  await as(H, PROF, { action: 'link', role: 'teacher', other: ALU2 });
  return H;
}

test('só endereços https de sites aceitos passam (e domínios parecidos não)', () => {
  assert.ok(lib.cleanUrl('https://drive.google.com/file/d/x/view'));
  assert.ok(lib.cleanUrl('https://imslp.org/wiki/Violin_Concerto'));
  assert.ok(lib.cleanUrl('https://www.youtube.com/watch?v=abc'));
  assert.equal(lib.cleanUrl('http://drive.google.com/file/d/x'), null);
  assert.equal(lib.cleanUrl('https://drive.google.com.golpe.com/x'), null);
  assert.equal(lib.cleanUrl('https://golpe.com/drive.google.com'), null);
  assert.equal(lib.cleanUrl('javascript:alert(1)'), null);
  assert.equal(lib.cleanUrl('https://user:pw@drive.google.com/x'), null);
  assert.equal(lib.cleanUrl('https://drive.google.com/x y'), null);
});

test('quem não está na lista não usa o acervo, e o sync avisa quem pode', async () => {
  const H = await setup();
  for (const act of [{ action: 'lib_list' }, { action: 'lib_put', item: item() }, { action: 'lib_del', id: 'abc12' }]) {
    const r = await as(H, ALU, act);
    assert.equal(r.statusCode, 403, JSON.stringify(act));
    assert.equal(r.json().error, 'library_off');
  }
  const sp = (await as(H, PROF, { action: 'sync' })).json();
  assert.equal(sp.lb, 1);
  const sa = (await as(H, ALU, { action: 'sync' })).json();
  assert.equal(sa.lb, 0);
  assert.deepEqual(sa.lbT, [PROF]);
  const so = (await as(H, ESTR, { action: 'sync' })).json();
  assert.deepEqual(so.lbT, []);
});

test('o professor cadastra com a declaração, e o aluno vê só o que é para ele', async () => {
  const H = await setup();
  const todos = item({ t: 'Para todos' });
  const soAna = item({ t: 'Só a Ana', to: [ALU] });
  assert.equal((await as(H, PROF, { action: 'lib_put', item: todos })).statusCode, 200);
  assert.equal((await as(H, PROF, { action: 'lib_put', item: soAna })).statusCode, 200);
  const semDecl = await as(H, PROF, { action: 'lib_put', item: item({ ok: false }) });
  assert.equal(semDecl.statusCode, 400);
  assert.equal(semDecl.json().error, 'declaration');
  const ruim = await as(H, PROF, { action: 'lib_put', item: item({ u: 'https://golpe.com/x' }) });
  assert.equal(ruim.json().error, 'bad_url');
  const meus = (await as(H, PROF, { action: 'lib_list' })).json().items;
  assert.equal(meus.length, 2);
  const ana = (await as(H, ALU, { action: 'lib_list', other: PROF })).json().items.map((x) => x.t).sort();
  assert.deepEqual(ana, ['Para todos', 'Só a Ana']);
  const bia = (await as(H, ALU2, { action: 'lib_list', other: PROF })).json().items.map((x) => x.t);
  assert.deepEqual(bia, ['Para todos']);
  // quem não é aluno dele não vê nada
  const estr = await as(H, ESTR, { action: 'lib_list', other: PROF });
  assert.equal(estr.statusCode, 403);
});

test('apagar, denunciar e a moderação do painel escondem o item do aluno', async () => {
  const H = await setup();
  const it = item({ t: 'Método' });
  await as(H, PROF, { action: 'lib_put', item: it });
  assert.equal((await as(H, ALU, { action: 'lib_report', other: PROF, id: it.id })).statusCode, 200);
  assert.equal((await as(H, ESTR, { action: 'lib_report', other: PROF, id: it.id })).statusCode, 403);
  const painel = (await adm(H, { action: 'library' })).json();
  assert.equal(painel.testers[0].code, PROF);
  assert.equal(painel.testers[0].items, 1);
  assert.equal(painel.reports.length, 1);
  assert.equal(painel.reports[0].n, 1);
  await adm(H, { action: 'library_hide', teacher: PROF, id: it.id });
  assert.equal((await as(H, ALU, { action: 'lib_list', other: PROF })).json().items.length, 0);
  assert.equal((await as(H, PROF, { action: 'lib_list' })).json().items[0].x, 1); // o professor continua vendo
  // editar o item não desfaz a moderação
  await as(H, PROF, { action: 'lib_put', item: { ...it, t: 'Método 2' } });
  assert.equal((await as(H, ALU, { action: 'lib_list', other: PROF })).json().items.length, 0);
  await adm(H, { action: 'library_hide', teacher: PROF, id: it.id, hide: false });
  assert.equal((await as(H, ALU, { action: 'lib_list', other: PROF })).json().items.length, 1);
  await as(H, PROF, { action: 'lib_del', id: it.id });
  assert.equal((await as(H, ALU, { action: 'lib_list', other: PROF })).json().items.length, 0);
});

test('encerrar o vínculo tira o acesso do aluno ao acervo', async () => {
  const H = await setup();
  await as(H, PROF, { action: 'lib_put', item: item() });
  await as(H, PROF, { action: 'unlink', role: 'teacher', other: ALU });
  assert.equal((await as(H, ALU, { action: 'lib_list', other: PROF })).statusCode, 403);
});

test('sem LIBRARY_TESTERS ninguém usa', async () => {
  const H = mk('');
  await as(H, PROF, { action: 'sync' });
  assert.equal((await as(H, PROF, { action: 'lib_list' })).statusCode, 403);
});
