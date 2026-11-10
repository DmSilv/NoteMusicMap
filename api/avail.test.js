// Testes dos horários disponíveis (professor) e de "pegar horário" (aluno), sem rede:
// `node --test api/avail.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const link = require('./link');
const { config } = require('./_lib/config');
const { hashes, memory } = require('./_lib/store');

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
const PROF = code(11111), ALU = code(22222), ALU2 = code(33333), OUTRO = code(44444);
const secret = (c) => crypto.createHash('sha256').update('s' + c).digest('hex');
const S = { [PROF]: secret(PROF), [ALU]: secret(ALU), [ALU2]: secret(ALU2), [OUTRO]: secret(OUTRO) };
const H1 = 3600000, DAY = 86400000;

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
  NOW = 1_800_000_000_000;
  return link.makeHandler({ config: () => config({}), allowMemory: true, fetch: async () => ({ status: 200 }), now: () => NOW });
}
async function as(h, who, body) {
  const res = fakeRes();
  await h({ method: 'POST', headers: { 'x-forwarded-for': '8.8.8.' + ++ipN }, body: { code: who, secret: S[who], ...body }, socket: {} }, res);
  return res;
}
async function vincula(h, aluno = ALU) {
  await as(h, aluno, { action: 'sync' });
  assert.equal((await as(h, PROF, { action: 'link', role: 'teacher', other: aluno, name: 'Profa. Ana' })).statusCode, 200);
}
const open = (id, extra = {}) => ({ id, s: NOW + 3 * DAY, d: 60, u: NOW, ...extra });
const put = (h, slot) => as(h, PROF, { action: 'avail_put', slot });
const list = (h, who = ALU, teacher = PROF) => as(h, who, { action: 'avail', other: teacher });
const take = (h, id, who = ALU, teacher = PROF) => as(h, who, { action: 'avail_take', other: teacher, slot: id });

test('professor cria horário; aluno vinculado vê só os que ainda dá para pegar', async () => {
  const h = mk();
  await vincula(h);
  assert.equal((await put(h, open('h1'))).statusCode, 200);
  assert.equal((await put(h, open('h2', { s: NOW + 30 * 60000 }))).statusCode, 200, 'perto demais: criado, mas não aparece');
  assert.equal((await put(h, open('h3', { s: NOW - 2 * DAY }))).statusCode, 200, 'passado: criado, mas não aparece');
  const j = (await list(h)).json();
  assert.deepEqual(j.open.map((x) => x.id), ['h1']);
});

test('semanal antigo ainda aparece (próxima semana)', async () => {
  const h = mk();
  await vincula(h);
  await put(h, open('sem1', { s: NOW - 20 * DAY, w: 1 }));
  assert.deepEqual((await list(h)).json().open.map((x) => x.id), ['sem1']);
});

test('quem não é vinculado não vê nem pega', async () => {
  const h = mk();
  await vincula(h);
  await put(h, open('h1'));
  await as(h, OUTRO, { action: 'sync' });
  assert.equal((await list(h, OUTRO)).statusCode, 403);
  assert.equal((await take(h, 'h1', OUTRO)).statusCode, 403);
});

test('apagar horário (c=1) tira da lista; pegar o apagado dá 409', async () => {
  const h = mk();
  await vincula(h);
  await put(h, open('h1'));
  await put(h, open('h1', { c: 1 }));
  assert.equal((await list(h)).json().open.length, 0);
  const r = await take(h, 'h1');
  assert.equal(r.statusCode, 409);
  assert.equal(r.json().error, 'slot_gone');
});

test('aluno pega: vira aula marcada nos dois lados, some da lista e o professor é avisado (ar)', async () => {
  const h = mk();
  await vincula(h);
  await put(h, open('h1', { w: 1, n: 'Trazer o arco' }));
  assert.equal((await as(h, PROF, { action: 'rev' })).json().ar, 0);
  const r = await take(h, 'h1');
  assert.equal(r.statusCode, 200);
  const cls = r.json().slot;
  assert.match(cls.id, /^p[0-9a-f]{12}$/);
  assert.equal(cls.w, 1);
  assert.equal((await list(h)).json().open.length, 0);
  const sched = (await as(h, ALU, { action: 'sched' })).json();
  assert.equal(sched.slots.length, 1);
  assert.equal(sched.slots[0].id, cls.id);
  assert.ok((await as(h, ALU, { action: 'rev' })).json().sr > 0, 'aluno: agenda mudou');
  assert.ok((await as(h, PROF, { action: 'rev' })).json().ar > 0, 'professor: alguém pegou');
  const picks = (await as(h, PROF, { action: 'picks' })).json();
  assert.equal(picks.slots.length, 1);
  assert.equal(picks.slots[0].sc, ALU);
  assert.equal(picks.slots[0].id, cls.id);
});

test('o primeiro que pega leva; o segundo recebe 409', async () => {
  const h = mk();
  await vincula(h);
  await vincula(h, ALU2);
  await put(h, open('h1'));
  const [a, b] = await Promise.all([take(h, 'h1', ALU), take(h, 'h1', ALU2)]);
  const codes = [a.statusCode, b.statusCode].sort();
  assert.deepEqual(codes, [200, 409]);
  const loser = a.statusCode === 409 ? a : b;
  assert.match(loser.json().error, /slot_(taken|gone)/);
  const picks = (await as(h, PROF, { action: 'picks' })).json();
  assert.equal(picks.slots.length, 1, 'só uma aula nasceu');
});

test('horário perto demais ou passado não pode ser pego', async () => {
  const h = mk();
  await vincula(h);
  await put(h, open('perto', { s: NOW + 20 * 60000 }));
  await put(h, open('velho', { s: NOW - DAY }));
  assert.equal((await take(h, 'perto')).json().error, 'slot_soon');
  assert.equal((await take(h, 'velho')).json().error, 'slot_past');
});

test('não pega horário que bate com outra aula do professor', async () => {
  const h = mk();
  await vincula(h);
  const aula = { id: 'aula1', s: NOW + 3 * DAY + 30 * 60000, d: 60, u: NOW };
  assert.equal((await as(h, PROF, { action: 'sched_put', other: ALU, slot: aula })).statusCode, 200);
  await put(h, open('h1'));
  const r = await take(h, 'h1');
  assert.equal(r.statusCode, 409);
  assert.equal(r.json().error, 'slot_conflict');
});

test('limite de aulas do aluno com o mesmo professor', async () => {
  const h = mk();
  await vincula(h);
  for (let i = 0; i < 12; i++) {
    await put(h, open('hh' + i, { s: NOW + (3 + i) * DAY }));
    assert.equal((await take(h, 'hh' + i)).statusCode, 200);
  }
  await put(h, open('extra', { s: NOW + 40 * DAY }));
  const r = await take(h, 'extra');
  assert.equal(r.statusCode, 400);
  assert.equal(r.json().error, 'pick_limit');
});

test('limite de horários disponíveis por professor', async () => {
  const h = mk();
  await vincula(h);
  const base = NOW;
  for (let i = 0; i < 100; i++) {
    if (i % 40 === 0) NOW = base + (i / 40) * 2 * H1; // muda a hora do limite de alterações
    assert.equal((await put(h, open('l' + i, { s: base + (3 + i) * DAY, u: NOW }))).statusCode, 200);
  }
  NOW = base + 6 * H1;
  assert.equal((await put(h, open('l100', { s: base + 200 * DAY, u: NOW }))).statusCode, 400);
  assert.equal((await put(h, open('l5', { s: base + 8 * DAY, n: 'editado', u: NOW }))).statusCode, 200, 'editar um existente continua valendo');
});

test('horário já pego não pode ser recriado com o mesmo id', async () => {
  const h = mk();
  await vincula(h);
  await put(h, open('h1'));
  await take(h, 'h1');
  const r = await put(h, open('h1'));
  assert.equal(r.statusCode, 409);
});

test('entradas inválidas: horário malformado, id ruim, sem o código do professor', async () => {
  const h = mk();
  await vincula(h);
  assert.equal((await put(h, { id: 'X', s: 1, d: 60, u: 1 })).statusCode, 400);
  assert.equal((await as(h, ALU, { action: 'avail_take', other: PROF, slot: 'AB C' })).statusCode, 400);
  assert.equal((await as(h, ALU, { action: 'avail_take', slot: 'h1' })).statusCode, 400);
  assert.equal((await as(h, ALU, { action: 'avail' })).statusCode, 400);
});

test('aluno não consegue criar horário no lugar do professor nem ler as aulas pegas', async () => {
  const h = mk();
  await vincula(h);
  // criar horário vale só para o próprio perfil: o do aluno não aparece para o professor dele
  await as(h, ALU, { action: 'avail_put', slot: open('falso') });
  assert.equal((await list(h)).json().open.length, 0);
  assert.equal((await as(h, ALU, { action: 'picks' })).json().slots.length, 0);
});

test('desvincular: a aula pegada some do aluno', async () => {
  const h = mk();
  await vincula(h);
  await put(h, open('h1'));
  await take(h, 'h1');
  await as(h, ALU, { action: 'unlink', role: 'student', other: PROF });
  assert.equal((await as(h, ALU, { action: 'sched' })).json().slots.length, 0);
  assert.equal((await as(h, PROF, { action: 'picks' })).json().slots.length, 0, 'sem vínculo, o professor também não recebe');
});

test('desvincular limpa a trava dos horários pegos por esse aluno (e só dele)', async () => {
  const h = mk();
  await vincula(h);
  await vincula(h, ALU2);
  await put(h, open('h1'));
  await put(h, open('h2', { s: NOW + 5 * DAY }));
  await take(h, 'h1', ALU);
  await take(h, 'h2', ALU2);
  const { hashes } = require('./_lib/store');
  assert.equal(hashes.get('tk:' + PROF).size, 2);
  await as(h, ALU, { action: 'unlink', role: 'student', other: PROF });
  assert.deepEqual([...hashes.get('tk:' + PROF).entries()], [['h2', ALU2]]);
});
