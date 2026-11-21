// Grupos de recursos, precedência e diagnóstico "por que vê isto?": `node --test api/features_groups.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const link = require('./link');
const admin = require('./admin');
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
const PROF = code(11), PROF2 = code(22), ALU = code(33), ALU2 = code(44);
const secret = (c) => crypto.createHash('sha256').update('s' + c).digest('hex');
const KEY = 'chave-de-admin-de-teste';
const SUP = 'chave-suporte-teste';
let ipN = 0;
function fakeRes() {
  const r = { headers: {}, statusCode: 0, body: '' };
  r.setHeader = (k, v) => { r.headers[k] = v; };
  r.end = (b) => { r.body = b; };
  r.json = () => JSON.parse(r.body);
  return r;
}
function mk(env = {}) {
  hashes.clear(); memory.clear(); resetMem(); features.resetCache();
  const cfg = config({ ADMIN_KEY: KEY, ...env });
  const deps = { config: () => cfg, allowMemory: true, fetch: async () => ({ status: 200 }), now: () => 1_800_000_000_000 };
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
async function setup(env) {
  const H = mk(env);
  for (const [who, nm] of [[PROF, 'Vinícius'], [PROF2, 'Outro'], [ALU, 'Ana'], [ALU2, 'Bia']]) await as(H, who, { action: 'sync', name: nm });
  await as(H, PROF, { action: 'link', role: 'teacher', other: ALU });
  await as(H, PROF, { action: 'link', role: 'teacher', other: ALU2 });
  return H;
}
const sync = async (H, who) => (await as(H, who, { action: 'sync' })).json();
const cardOf = async (H, id) => (await adm(H, { action: 'features' })).json().items.find((x) => x.id === id);
const grp = async (H, name) => (await adm(H, { action: 'group_save', name })).json().id;
const why = async (H, c, key) => (await adm(H, { action: 'feature_why', code: c }, key)).json();
const itemOf = (j, id) => j.items.find((x) => x.id === id);

test('grupo manual liga o recurso para quem está nele (e só para eles)', async () => {
  const H = await setup();
  const g = await grp(H, 'Testadores');
  assert.match(g, /^g[0-9a-f]{6}$/);
  assert.equal((await adm(H, { action: 'group_member', id: g, code: ALU, on: true })).statusCode, 200);
  assert.equal((await adm(H, { action: 'feature_groups', id: 'acervo', groups: [g] })).statusCode, 200);
  const a = itemOf(await why(H, ALU), 'acervo');
  assert.equal(a.on, true);
  assert.equal(a.why, 'group');
  assert.equal(a.groupName, 'Testadores');
  assert.equal(itemOf(await why(H, ALU2), 'acervo').on, false);
  assert.ok((await sync(H, ALU)).ff.includes('acervo'));
  assert.ok(!(await sync(H, ALU2)).ff.includes('acervo'));
});

test('precedência: desligar geral vence grupo e lista; todos vence tudo; lista aparece antes do grupo', async () => {
  const H = await setup();
  const g = await grp(H, 'Grupo G');
  await adm(H, { action: 'group_member', id: g, code: ALU, on: true });
  await adm(H, { action: 'feature_groups', id: 'acervo', groups: [g] });
  await adm(H, { action: 'feature_grant', id: 'acervo', code: ALU });
  assert.equal(itemOf(await why(H, ALU), 'acervo').why, 'list');
  await adm(H, { action: 'feature_set', id: 'acervo', mode: 'off' });
  const off = itemOf(await why(H, ALU), 'acervo');
  assert.equal(off.on, false);
  assert.equal(off.why, 'off');
  await adm(H, { action: 'feature_set', id: 'acervo', mode: 'all' });
  assert.equal(itemOf(await why(H, ALU2), 'acervo').why, 'all');
});

test('mudar o estado não apaga os grupos do recurso; excluir o grupo limpa membros e recursos', async () => {
  const H = await setup();
  const g = await grp(H, 'Grupo G');
  await adm(H, { action: 'group_member', id: g, code: ALU, on: true });
  await adm(H, { action: 'feature_groups', id: 'acervo', groups: [g, 'auto:t', 'lixo'] });
  await adm(H, { action: 'feature_set', id: 'acervo', mode: 'pct', pct: 10 });
  assert.deepEqual((await cardOf(H, 'acervo')).groups, [g, 'auto:t']);
  const r = (await adm(H, { action: 'group_delete', id: g })).json();
  assert.equal(r.cleaned, 1);
  assert.deepEqual((await cardOf(H, 'acervo')).groups, ['auto:t']);
  assert.notEqual(itemOf(await why(H, ALU), 'acervo').why, 'group');
});

test('grupos automáticos: professores e alunos pelo perfil', () => {
  const cfg = { acervo: { m: 'list', p: 0, g: ['auto:t'] }, aula_online: { m: 'list', p: 0, g: ['auto:s'] } };
  assert.equal(features.why(cfg, 'acervo', 'X', { rt: '1' }).why, 'group');
  assert.equal(features.why(cfg, 'acervo', 'X', { rs: '1' }).on, false);
  assert.equal(features.why(cfg, 'aula_online', 'X', { rs: '1' }).on, true);
});

test('limites: 20 grupos, nome mínimo e perfil inexistente', async () => {
  const H = await setup();
  assert.equal((await adm(H, { action: 'group_save', name: 'a' })).statusCode, 400);
  for (let i = 0; i < 20; i++) assert.equal((await adm(H, { action: 'group_save', name: 'Grupo ' + i })).statusCode, 200);
  assert.equal((await adm(H, { action: 'group_save', name: 'Um a mais' })).statusCode, 400);
  const g = (await adm(H, { action: 'group_list' })).json().manual[0].id;
  assert.equal((await adm(H, { action: 'group_member', id: g, code: code(999), on: true })).statusCode, 404);
});

test('suporte vê o diagnóstico e a lista de grupos, mas não cria nem apaga grupos', async () => {
  const H = await setup({ SUPPORT_KEY: SUP });
  const g = await grp(H, 'Grupo G');
  assert.equal((await why(H, ALU, SUP)).ok, true);
  assert.equal((await adm(H, { action: 'group_list' }, SUP)).statusCode, 200);
  for (const a of [{ action: 'group_save', name: 'X1' }, { action: 'group_delete', id: g }, { action: 'group_member', id: g, code: ALU }, { action: 'feature_groups', id: 'acervo', groups: [] }])
    assert.equal((await adm(H, a, SUP)).statusCode, 403, a.action);
});

test('sem grupos configurados o resultado da sincronização é o de sempre', async () => {
  const H = await setup();
  assert.deepEqual((await sync(H, ALU)).ff, []);
  await adm(H, { action: 'feature_grant', id: 'aula_online', code: ALU });
  assert.deepEqual((await sync(H, ALU)).ff, ['aula_online']);
});
