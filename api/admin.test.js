// Testes do painel do administrador (indicadores e gestão de perfis), sem rede:
// `node --test api/admin.test.js`
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
const PROF = code(11111), ALU = code(22222), ALU2 = code(33333), VELHO = code(55555);
const secret = (c) => crypto.createHash('sha256').update('s' + c).digest('hex');
const KEY = 'chave-de-admin-de-teste';
const DAY = 86400000;

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
async function as(H, who, body) {
  const res = fakeRes();
  await H.l({ method: 'POST', headers: { 'x-forwarded-for': '6.6.6.' + ++ipN }, body: { code: who, secret: secret(who), ...body }, socket: {} }, res);
  return res;
}
async function adm(H, body, key = KEY, method = 'POST') {
  const res = fakeRes();
  await H.a({ method, headers: { 'x-forwarded-for': '5.5.5.' + ++ipN, authorization: 'Bearer ' + key }, body, socket: {} }, res);
  return res;
}
async function vincula(H, aluno = ALU) {
  await as(H, aluno, { action: 'sync' });
  assert.equal((await as(H, PROF, { action: 'link', role: 'teacher', other: aluno, name: 'Profa. Ana' })).statusCode, 200);
}

test('sem chave certa não entra; sem chave configurada o painel nem existe', async () => {
  const H = mk();
  assert.equal((await adm(H, { action: 'kpis' }, 'errada')).statusCode, 401);
  assert.equal((await adm(H, { action: 'kpis' }, '')).statusCode, 401);
  assert.equal((await adm(H, { action: 'kpis' }, KEY, 'GET')).statusCode, 405);
  const semChave = admin.makeHandler({ config: () => config({}), allowMemory: true, fetch: async () => ({}), now: () => NOW });
  const res = fakeRes();
  await semChave({ method: 'POST', headers: {}, body: { action: 'kpis' }, socket: {} }, res);
  assert.equal(res.statusCode, 404);
});

test('muitas chaves erradas: bloqueia a origem (429)', async () => {
  const H = mk();
  let last = 0;
  for (let i = 0; i < 12; i++) {
    const res = fakeRes();
    await H.a({ method: 'POST', headers: { 'x-forwarded-for': '4.4.4.4', authorization: 'Bearer x' + i }, body: { action: 'kpis' }, socket: {} }, res);
    last = res.statusCode;
  }
  assert.equal(last, 429);
});

test('perfil novo entra no índice com data de entrada e última atividade', async () => {
  const H = mk();
  await as(H, ALU, { action: 'sync', name: 'Marina' });
  const l = (await adm(H, { action: 'list' })).json();
  assert.equal(l.total, 1);
  assert.equal(l.items[0].code, ALU);
  assert.equal(l.items[0].name, 'Marina');
  assert.equal(l.items[0].ca, NOW);
  assert.equal(l.items[0].la, NOW);
  assert.equal(l.items[0].inactive, false);
});

test('atividade só é regravada depois de 6 h (barato)', async () => {
  const H = mk();
  await as(H, ALU, { action: 'sync' });
  NOW += 2 * 3600000;
  await as(H, ALU, { action: 'sync' });
  assert.equal((await adm(H, { action: 'list' })).json().items[0].la, 1_800_000_000_000, 'ainda o mesmo');
  NOW += 5 * 3600000;
  await as(H, ALU, { action: 'sync' });
  assert.equal((await adm(H, { action: 'list' })).json().items[0].la, NOW);
});

test('indicadores: total, ativos x inativos, papéis e crescimento', async () => {
  const H = mk();
  // perfil antigo: ativo há 45 dias
  NOW -= 45 * DAY;
  await as(H, VELHO, { action: 'sync' });
  NOW += 45 * DAY;
  await vincula(H);
  await vincula(H, ALU2);
  const k = (await adm(H, { action: 'kpis' })).json();
  assert.equal(k.ok, true);
  assert.equal(k.profiles.total, 4);
  assert.equal(k.profiles.active30, 3);
  assert.equal(k.profiles.inactive, 1);
  assert.equal(k.profiles.new7, 3);
  assert.equal(k.teachers.total, 1);
  assert.equal(k.students.total, 2);
  assert.equal(k.teachers.active30, 1);
  assert.equal(k.growth.length, 14);
  assert.equal(k.growth.at(-1).news, 3, 'hoje entraram 3');
});

test('retenção: quem voltou depois do dia 1 e do dia 7', async () => {
  const H = mk();
  // 3 perfis entraram há 10 dias; um voltou há 2 dias, outro voltou no dia seguinte, outro nunca voltou
  const base = NOW;
  NOW = base - 10 * DAY;
  for (const c of [ALU, ALU2, VELHO]) await as(H, c, { action: 'sync' });
  NOW = base - 9 * DAY + 7 * 3600000;
  await as(H, ALU2, { action: 'sync' }); // voltou ~1 dia depois (> 6h desde a última)
  NOW = base - 2 * DAY;
  await as(H, ALU, { action: 'sync' }); // voltou no dia 8
  NOW = base;
  const k = (await adm(H, { action: 'kpis' })).json();
  assert.equal(k.retention.sample, 3);
  assert.deepEqual([k.retention.d1.back, k.retention.d1.of], [2, 3], 'D1: ALU e ALU2 voltaram a partir do dia 1');
  assert.equal(k.retention.d7.back, 1);
  assert.equal(k.retention.d7.of, 3);
  assert.equal(k.retention.d30, null, 'ninguém tem 30 dias ainda');
});

test('lista: páginas, busca por trecho do código, papéis', async () => {
  const H = mk();
  await vincula(H);
  const all = (await adm(H, { action: 'list' })).json();
  assert.equal(all.total, 2);
  const prof = all.items.find((x) => x.code === PROF);
  assert.equal(prof.teacher, true);
  const alu = all.items.find((x) => x.code === ALU);
  assert.equal(alu.student, true);
  const q = (await adm(H, { action: 'list', q: ALU.slice(0, 4).toLowerCase() })).json();
  assert.ok(q.items.some((x) => x.code === ALU));
  assert.equal((await adm(H, { action: 'list', q: 'ZZZZ' })).json().items.length, 0);
});

test('detalhe: papel, vínculos e volume de dados; nunca devolve o segredo', async () => {
  const H = mk();
  await vincula(H);
  const d = (await adm(H, { action: 'detail', code: PROF })).json();
  assert.equal(d.profile.code, PROF);
  assert.deepEqual(d.students.map((s) => s.code), [ALU]);
  assert.equal(JSON.stringify(d).includes(secret(PROF)), false);
  assert.equal('h' in d.profile, false);
  assert.equal((await adm(H, { action: 'detail', code: code(77777) })).statusCode, 404);
  assert.equal((await adm(H, { action: 'detail', code: 'xx' })).statusCode, 400);
});

test('bloquear impede o vínculo online; liberar devolve; fica no registro', async () => {
  const H = mk();
  await vincula(H);
  assert.equal((await adm(H, { action: 'block', code: ALU })).statusCode, 200);
  const r = await as(H, ALU, { action: 'sync' });
  assert.equal(r.statusCode, 403);
  assert.equal(r.json().error, 'blocked');
  assert.equal((await adm(H, { action: 'list' })).json().items.find((x) => x.code === ALU).blocked, true);
  await adm(H, { action: 'unblock', code: ALU });
  assert.equal((await as(H, ALU, { action: 'sync' })).statusCode, 200);
  const log = (await adm(H, { action: 'log' })).json();
  assert.deepEqual(log.items.map((x) => x.a), ['unblock', 'block']);
});

test('excluir exige repetir o código; limpa perfil, vínculos e dados dos dois lados', async () => {
  const H = mk();
  await vincula(H);
  await as(H, ALU, { action: 'done', other: PROF, lesson: 'aula0001', task: 'k1', done: true });
  assert.equal((await adm(H, { action: 'delete', code: ALU })).statusCode, 400);
  assert.equal((await adm(H, { action: 'delete', code: ALU, confirm: PROF })).statusCode, 400);
  assert.equal((await adm(H, { action: 'delete', code: ALU, confirm: ALU.toLowerCase() })).statusCode, 200);
  assert.equal((await adm(H, { action: 'detail', code: ALU })).statusCode, 404);
  const l = (await adm(H, { action: 'list' })).json();
  assert.deepEqual(l.items.map((x) => x.code), [PROF]);
  const sync = (await as(H, PROF, { action: 'sync' })).json();
  assert.equal(sync.asTeacher.length, 0, 'o professor não vê mais o aluno');
  assert.equal((await as(H, PROF, { action: 'dones' })).json().dones.length, 0);
  const k = (await adm(H, { action: 'kpis' })).json();
  assert.equal(k.profiles.total, 1);
  assert.equal(k.teachers.total, 0, 'sem alunos, deixa de contar como professor');
});

test('excluir um professor tira as aulas e horários dos alunos dele', async () => {
  const H = mk();
  await vincula(H);
  const slot = { id: 'aula1', s: NOW + 3 * DAY, d: 60, u: NOW };
  await as(H, PROF, { action: 'sched_put', other: ALU, slot });
  assert.equal((await as(H, ALU, { action: 'sched' })).json().slots.length, 1);
  await adm(H, { action: 'delete', code: PROF, confirm: PROF });
  assert.equal((await as(H, ALU, { action: 'sched' })).json().slots.length, 0);
  assert.equal((await as(H, ALU, { action: 'sync' })).json().asStudent.length, 0);
});

test('ação desconhecida e corpo inválido', async () => {
  const H = mk();
  assert.equal((await adm(H, { action: 'nada' })).statusCode, 400);
  const res = fakeRes();
  await H.a({ method: 'POST', headers: { authorization: 'Bearer ' + KEY }, body: 'não é json', socket: {} }, res);
  assert.equal(res.statusCode, 400);
});

// ---------------- Sistema: banco, servidor, variáveis e limites ----------------
test('sistema: teste do banco, versão, variáveis e limites, sem vazar segredos', async () => {
  const H = mk();
  const r = await adm(H, { action: 'system' });
  assert.equal(r.statusCode, 200);
  const j = r.json();
  assert.equal(j.ok, true);
  assert.equal(j.db.ok, true);
  assert.equal(typeof j.db.ms, 'number');
  assert.equal(j.db.memoryMode, true, 'sem Redis real: modo de teste');
  assert.equal(j.server.functions.max, 12);
  assert.equal(j.server.serverErrors.length, 14);
  assert.equal(j.limits.redisMonth, 500000);
  const byId = Object.fromEntries(j.checks.map((c) => [c.id, c]));
  assert.equal(byId.admin.ok, true);
  assert.equal(byId.redis.ok, false, 'sem URL/token do Redis');
  assert.equal(byId.redis.required, true);
  assert.equal(byId.qstash.ok, false);
  assert.equal(byId.qstash.required, false);
  assert.equal(JSON.stringify(j).includes(KEY), false, 'a chave do painel nunca aparece');
});

test('sistema: só com a chave certa', async () => {
  const H = mk();
  assert.equal((await adm(H, { action: 'system' }, 'errada')).statusCode, 401);
});

test('sistema: erros do servidor aparecem por dia', async () => {
  const H = mk();
  const { serverError } = require('./_lib/error_store');
  const cfg = config({ ADMIN_KEY: KEY });
  await serverError({ cfg, fetchImpl: async () => ({ status: 200 }), clock: () => NOW, allowMemory: true }, 'link', new Error('falha de teste'));
  const j = (await adm(H, { action: 'system' })).json();
  assert.equal(j.server.serverErrors.reduce((a, d) => a + d.srv, 0) >= 1, true);
});
