// Agenda com o professor no comando: "confirmo antes", pedidos, desfazer, avisos do aluno, "pegar horário" por aluno,
// data final, fuso. `node --test api/agenda_plus.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const link = require('./link');
const agenda = require('./_lib/agenda');
const { config } = require('./_lib/config');
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
const PROF = code(11111), PROF2 = code(44444), ALU = code(22222), ALU2 = code(33333), OUTRO = code(55555);
const sec = (c) => crypto.createHash('sha256').update('s' + c).digest('hex');
const DAY = 86400000, MIN = 60000;
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
  hashes.clear(); memory.clear(); resetMem();
  NOW = 1_800_000_000_000;
  return link.makeHandler({ config: () => config({}), allowMemory: true, fetch: async () => ({ status: 200 }), now: () => NOW });
}
async function as(H, who, body) {
  const res = fakeRes();
  await H({ method: 'POST', headers: { 'x-forwarded-for': '2.2.2.' + ++ipN }, body: { code: who, secret: sec(who), ...body }, socket: {} }, res);
  return res;
}
async function setup(students = [ALU]) {
  const H = mk();
  await as(H, PROF, { action: 'sync', name: 'Prof' });
  await as(H, PROF2, { action: 'sync', name: 'Prof2' });
  for (const a of students) {
    await as(H, a, { action: 'sync', name: 'Aluno' });
    assert.equal((await as(H, PROF, { action: 'link', role: 'teacher', other: a })).statusCode, 200);
  }
  return H;
}
const open = (id, extra = {}) => ({ id, s: NOW + 3 * DAY, d: 60, u: NOW, ...extra });
const putOpen = (H, s, who = PROF) => as(H, who, { action: 'avail_put', slot: s });
const take = (H, who, sid, extra = {}, teacher = PROF) => as(H, who, { action: 'avail_take', other: teacher, slot: sid, ...extra });
const inbox = async (H, who = PROF) => (await as(H, who, { action: 't_inbox' })).json();
const sched = async (H, who) => (await as(H, who, { action: 'sched' })).json().slots;

// ---------------- campos novos do horário ----------------
test('campos novos: cf, z e e passam; fuso estranho e data final impossível são descartados', () => {
  const ok = agenda.cleanSlot({ id: 'ab', s: NOW + DAY, d: 60, u: NOW, w: 1, cf: 1, z: -180, e: NOW + 30 * DAY }, NOW);
  assert.equal(ok.cf, 1);
  assert.equal(ok.z, -180);
  assert.equal(ok.e, NOW + 30 * DAY);
  const bad = agenda.cleanSlot({ id: 'ab', s: NOW + DAY, d: 60, u: NOW, w: 1, z: 99999, e: NOW }, NOW);
  assert.equal(bad.z, undefined);
  assert.equal(bad.e, undefined, 'data final antes do início');
  const far = agenda.cleanSlot({ id: 'ab', s: NOW + DAY, d: 60, u: NOW, w: 1, e: NOW + 30 * 366 * DAY }, NOW);
  assert.equal(far.e, undefined, 'mais de 5 anos');
  const single = agenda.cleanSlot({ id: 'ab', s: NOW + DAY, d: 60, u: NOW, e: NOW + 30 * DAY }, NOW);
  assert.equal(single.e, undefined, 'data final só vale para aula semanal');
});

test('data final: a aula semanal não acontece depois dela (próxima, ocorrências e conflito)', () => {
  const s = agenda.cleanSlot({ id: 'ab', s: NOW + DAY, d: 60, u: NOW, w: 1, e: NOW + DAY + 14 * DAY }, NOW);
  assert.equal(agenda.occurrences(s, NOW, NOW + 90 * DAY).length, 3, 'início, +7 e +14 dias');
  assert.equal(agenda.nextStart(s, NOW + DAY + 15 * DAY), null);
  assert.equal(agenda.nextStart(s, NOW + DAY + 8 * DAY), NOW + DAY + 14 * DAY);
  const other = { id: 'zz', s: NOW + DAY + 21 * DAY, d: 60, u: NOW };
  assert.equal(agenda.slotsOverlap(s, other, NOW), false, 'depois do fim não bate');
});

test('app antigo que edita a aula não apaga data final, fuso nem "confirmo antes"', async () => {
  const H = await setup();
  const base = open('h1', { w: 1, cf: 1, z: -180, e: NOW + 40 * DAY });
  await putOpen(H, base);
  await putOpen(H, { id: 'h1', s: base.s, d: 60, u: NOW + 1, w: 1 }); // sem cf, z, e: app antigo
  const lista = (await as(H, ALU, { action: 'avail', other: PROF })).json().open[0];
  assert.equal(lista.cf, 1);
  assert.equal(lista.z, -180);
  assert.equal(lista.e, base.e);
  await putOpen(H, { id: 'h1', s: base.s, d: 60, u: NOW + 2, w: 1, cf: 0, e: 0 }); // app novo apaga
  const depois = (await as(H, ALU, { action: 'avail', other: PROF })).json().open[0];
  assert.equal(depois.cf, undefined);
  assert.equal(depois.e, undefined);
  assert.equal(depois.z, -180);
});

// ---------------- confirmo antes ----------------
test('confirmo antes: o pedido não cria aula; o professor vê e aceita; a aula nasce nos dois lados', async () => {
  const H = await setup();
  await putOpen(H, open('h1', { cf: 1 }));
  const r = await take(H, ALU, 'h1', { cv: 2 });
  assert.equal(r.statusCode, 200);
  assert.equal(r.json().requested, true);
  assert.equal((await sched(H, ALU)).length, 0, 'nada na agenda ainda');
  assert.equal((await as(H, ALU, { action: 'avail', other: PROF })).json().open.length, 1, 'o horário continua livre');
  const t = await inbox(H);
  assert.equal(t.reqs.length, 1);
  assert.equal(t.reqs[0].st, ALU);
  assert.ok(t.ar > 0);
  const ok = await as(H, PROF, { action: 'req_answer', other: ALU, slot: 'h1', accept: true });
  assert.equal(ok.statusCode, 200);
  assert.equal(ok.json().accepted, true);
  assert.equal((await sched(H, ALU)).length, 1);
  assert.equal((await inbox(H)).reqs.length, 0);
  assert.equal((await as(H, ALU, { action: 'avail', other: PROF })).json().open.length, 0);
});

test('confirmo antes: app antigo recebe "atualize" e nada é criado; pedido repetido não duplica', async () => {
  const H = await setup();
  await putOpen(H, open('h1', { cf: 1 }));
  const old = await take(H, ALU, 'h1');
  assert.equal(old.statusCode, 409);
  assert.equal(old.json().error, 'needs_update');
  assert.equal((await inbox(H)).reqs.length, 0);
  await take(H, ALU, 'h1', { cv: 2 });
  const dup = await take(H, ALU, 'h1', { cv: 2 });
  assert.equal(dup.json().dup, true);
  assert.equal((await inbox(H)).reqs.length, 1);
});

test('confirmo antes: recusar avisa o aluno e libera o pedido; no máximo 3 pedidos esperando', async () => {
  const H = await setup();
  for (const id of ['h1', 'h2', 'h3', 'h4']) await putOpen(H, open(id, { cf: 1, s: NOW + (3 + ['h1', 'h2', 'h3', 'h4'].indexOf(id)) * DAY }));
  for (const id of ['h1', 'h2', 'h3']) assert.equal((await take(H, ALU, id, { cv: 2 })).statusCode, 200);
  const lim = await take(H, ALU, 'h4', { cv: 2 });
  assert.equal(lim.statusCode, 409);
  assert.equal(lim.json().error, 'req_limit');
  assert.equal((await as(H, PROF, { action: 'req_answer', other: ALU, slot: 'h1', accept: false })).json().accepted, false);
  const resp = (await as(H, ALU, { action: 's_inbox' })).json().answers;
  assert.deepEqual(resp.map((x) => [x.f, x.st]), [[`r:${PROF}:h1`, 'no']]);
  assert.equal((await take(H, ALU, 'h4', { cv: 2 })).statusCode, 200, 'liberou uma vaga de pedido');
});

test('confirmo antes: dois alunos pedem o mesmo horário; aceitar um recusa o outro', async () => {
  const H = await setup([ALU, ALU2]);
  await putOpen(H, open('h1', { cf: 1 }));
  await take(H, ALU, 'h1', { cv: 2 });
  await take(H, ALU2, 'h1', { cv: 2 });
  assert.equal((await inbox(H)).reqs.length, 2);
  await as(H, PROF, { action: 'req_answer', other: ALU2, slot: 'h1', accept: true });
  assert.equal((await sched(H, ALU2)).length, 1);
  assert.equal((await sched(H, ALU)).length, 0);
  assert.equal((await inbox(H)).reqs.length, 0);
  const resp = (await as(H, ALU, { action: 's_inbox' })).json().answers;
  assert.equal(resp[0].st, 'no');
});

test('confirmo antes: só o professor dono responde; pedido que não existe dá 404; aluno que saiu some', async () => {
  const H = await setup();
  await putOpen(H, open('h1', { cf: 1 }));
  await take(H, ALU, 'h1', { cv: 2 });
  assert.equal((await as(H, PROF2, { action: 'req_answer', other: ALU, slot: 'h1', accept: true })).statusCode, 404, 'outro professor não responde pedido alheio');
  assert.equal((await as(H, PROF, { action: 'req_answer', other: ALU, slot: 'nada', accept: true })).statusCode, 404);
  await as(H, ALU, { action: 'unlink', role: 'student', other: PROF });
  assert.equal((await inbox(H)).reqs.length, 0, 'vínculo encerrado limpa os pedidos');
});

test('confirmo antes: aceitar bate com aula do professor ou do aluno? recusa com explicação', async () => {
  const H = await setup();
  await putOpen(H, open('h1', { cf: 1 }));
  await take(H, ALU, 'h1', { cv: 2 });
  await as(H, PROF, { action: 'sched_put', other: ALU, slot: { id: 'aula1', s: NOW + 3 * DAY, d: 60, u: NOW } });
  const r = await as(H, PROF, { action: 'req_answer', other: ALU, slot: 'h1', accept: true });
  assert.equal(r.statusCode, 409);
  assert.equal(r.json().error, 'slot_conflict');
});

// ---------------- pegar horário desligado por aluno ----------------
test('pegar horário desligado para um aluno: ele não vê horários e não pega; os outros continuam', async () => {
  const H = await setup([ALU, ALU2]);
  await putOpen(H, open('h1'));
  assert.equal((await as(H, PROF, { action: 'pick_allow', role: 'teacher', other: ALU, on: false })).statusCode, 200);
  const l = (await as(H, ALU, { action: 'avail', other: PROF })).json();
  assert.deepEqual(l.open, []);
  assert.equal(l.off, 1);
  const t = await take(H, ALU, 'h1');
  assert.equal(t.statusCode, 409);
  assert.equal(t.json().error, 'pick_off');
  assert.equal((await as(H, ALU2, { action: 'avail', other: PROF })).json().open.length, 1);
  assert.equal((await take(H, ALU2, 'h1')).statusCode, 200);
  const sync = (await as(H, ALU, { action: 'sync' })).json();
  assert.equal(sync.asStudent[0].np, 1, 'o aluno sabe que está desligado');
  await as(H, PROF, { action: 'pick_allow', role: 'teacher', other: ALU, on: true });
  assert.equal((await as(H, ALU, { action: 'sync' })).json().asStudent[0].np, undefined);
});

test('pegar horário por aluno: aluno não liga pelo professor; outro professor não mexe', async () => {
  const H = await setup();
  assert.equal((await as(H, ALU, { action: 'pick_allow', role: 'student', other: PROF, on: false })).statusCode, 403);
  assert.equal((await as(H, PROF2, { action: 'pick_allow', role: 'teacher', other: ALU, on: false })).statusCode, 404);
});

// ---------------- desfazer ----------------
test('desfazer: o aluno desfaz nos primeiros 10 min, o horário volta e a aula some dos dois lados', async () => {
  const H = await setup();
  await putOpen(H, open('h1'));
  const got = (await take(H, ALU, 'h1')).json().slot;
  NOW += 5 * MIN;
  const u = await as(H, ALU, { action: 'pick_undo', other: PROF, slot: got.id });
  assert.equal(u.statusCode, 200);
  assert.equal((await as(H, ALU, { action: 'avail', other: PROF })).json().open.length, 1, 'horário livre de novo');
  const mine = await sched(H, ALU);
  assert.equal(mine[0].c, 1, 'cancelada para o aluno');
  const picks = (await as(H, PROF, { action: 'picks' })).json().slots;
  assert.equal(picks[0].c, 1, 'cancelada para o professor');
  assert.equal((await take(H, ALU, 'h1')).statusCode, 200, 'e dá para pegar outra vez');
});

test('desfazer: depois de 10 min, de outro aluno ou com a aula já mexida pelo professor, não dá', async () => {
  const H = await setup([ALU, ALU2]);
  await putOpen(H, open('h1'));
  await putOpen(H, open('h2', { s: NOW + 4 * DAY }));
  const a = (await take(H, ALU, 'h1')).json().slot;
  const b = (await take(H, ALU, 'h2')).json().slot;
  assert.equal((await as(H, ALU2, { action: 'pick_undo', other: PROF, slot: a.id })).json().error, 'undo_closed', 'a aula é de outro aluno');
  // o professor edita a aula do h2: perde a marca de "pegou agora"
  await as(H, PROF, { action: 'sched_put', other: ALU, slot: { id: b.id, s: b.s, d: 45, u: NOW + 1 } });
  assert.equal((await as(H, ALU, { action: 'pick_undo', other: PROF, slot: b.id })).json().error, 'undo_closed');
  NOW += 11 * MIN;
  const late = await as(H, ALU, { action: 'pick_undo', other: PROF, slot: a.id });
  assert.equal(late.statusCode, 409);
  assert.equal(late.json().error, 'undo_closed');
});

// ---------------- avisos do aluno ----------------
const warnBody = (slotId, occ, k = 'no', teacher = PROF) => ({ action: 'warn_put', other: teacher, slot: slotId, occ, k });
async function withClass(H, who = ALU) {
  const sl = { id: 'aula1', s: NOW + 2 * DAY, d: 60, u: NOW, w: 1 };
  await as(H, PROF, { action: 'sched_put', other: who, slot: sl });
  return sl;
}

test('aviso do aluno: não muda a aula; o professor vê e responde; o aluno vê a resposta', async () => {
  const H = await setup();
  const sl = await withClass(H);
  const occ = sl.s + 7 * DAY;
  assert.equal((await as(H, ALU, warnBody('aula1', occ, 'rs'))).statusCode, 200);
  assert.equal((await sched(H, ALU))[0].s, sl.s, 'a aula continua igual');
  const t = await inbox(H);
  assert.equal(t.warns.length, 1);
  assert.deepEqual([t.warns[0].st, t.warns[0].k, t.warns[0].occ, t.warns[0].late], [ALU, 'rs', occ, false]);
  assert.equal((await as(H, PROF, { action: 'warn_answer', other: ALU, slot: 'aula1', occ, d: 'ok' })).statusCode, 200);
  assert.equal((await inbox(H)).warns.length, 0);
  const resp = (await as(H, ALU, { action: 's_inbox' })).json().answers;
  assert.deepEqual(resp.map((x) => [x.f, x.st]), [[`w:${PROF}:aula1:${occ}`, 'ok']]);
});

test('aviso do aluno: em cima da hora (menos de 24 h) vem marcado', async () => {
  const H = await setup();
  await as(H, PROF, { action: 'sched_put', other: ALU, slot: { id: 'aula1', s: NOW + 5 * 3600000, d: 60, u: NOW } });
  await as(H, ALU, warnBody('aula1', NOW + 5 * 3600000));
  assert.equal((await inbox(H)).warns[0].late, true);
});

test('aviso do aluno: ocorrência inventada, aula passada, aula de outro e duplicado são tratados', async () => {
  const H = await setup([ALU, ALU2]);
  const sl = await withClass(H);
  assert.equal((await as(H, ALU, warnBody('aula1', sl.s + 123456))).statusCode, 400, 'horário que não é uma aula');
  assert.equal((await as(H, ALU, warnBody('nada', sl.s))).statusCode, 404);
  assert.equal((await as(H, ALU2, warnBody('aula1', sl.s))).statusCode, 404, 'a aula não é dele');
  assert.equal((await as(H, ALU, { ...warnBody('aula1', sl.s), k: 'xx' })).statusCode, 400);
  assert.equal((await as(H, ALU, warnBody('aula1', sl.s))).statusCode, 200);
  assert.equal((await as(H, ALU, warnBody('aula1', sl.s))).json().dup, true);
  assert.equal((await inbox(H)).warns.length, 1);
  assert.equal((await as(H, OUTRO, warnBody('aula1', sl.s))).statusCode, 403, 'quem não é aluno deste professor');
  NOW += 3 * DAY;
  assert.equal((await as(H, ALU, warnBody('aula1', sl.s + 7 * DAY, 'rs'))).statusCode, 200, 'a próxima ainda vale');
  const past = await as(H, ALU, warnBody('aula1', sl.s, 'late'));
  assert.equal(past.statusCode, 409, 'a primeira aula já passou');
  assert.equal(past.json().error, 'class_past');
});

test('aviso do aluno: no máximo 3 por dia', async () => {
  const H = await setup();
  const sl = await withClass(H);
  for (let i = 0; i < 3; i++) assert.equal((await as(H, ALU, warnBody('aula1', sl.s + i * 7 * DAY))).statusCode, 200);
  const r = await as(H, ALU, warnBody('aula1', sl.s + 3 * 7 * DAY));
  assert.equal(r.statusCode, 429);
  assert.equal(r.json().error, 'warn_limit');
});

test('aviso do aluno: o professor silencia um aluno ou todos; o aluno recebe a explicação', async () => {
  const H = await setup([ALU, ALU2]);
  await withClass(H);
  await as(H, PROF, { action: 'sched_put', other: ALU2, slot: { id: 'aula2', s: NOW + 2 * DAY + 2 * 3600000, d: 60, u: NOW, w: 1 } });
  const sl = { s: NOW + 2 * DAY };
  assert.equal((await as(H, PROF, { action: 'warn_mute', role: 'teacher', other: ALU, on: true })).statusCode, 200);
  const r = await as(H, ALU, warnBody('aula1', sl.s));
  assert.equal(r.statusCode, 409);
  assert.equal(r.json().error, 'warn_off');
  assert.equal((await as(H, ALU2, warnBody('aula2', sl.s + 2 * 3600000))).statusCode, 200, 'o outro aluno continua');
  await as(H, PROF, { action: 'warn_global', on: false });
  assert.equal((await as(H, PROF, { action: 'sync' })).json().wm, 1, 'o professor sabe que desligou');
  await as(H, PROF, { action: 'warn_mute', role: 'teacher', other: ALU, on: false });
  assert.equal((await as(H, ALU, warnBody('aula1', sl.s))).json().error, 'warn_off', 'global ainda desligado');
  await as(H, PROF, { action: 'warn_global', on: true });
  assert.equal((await as(H, ALU, warnBody('aula1', sl.s))).statusCode, 200);
});

test('aviso do aluno: aluno pausado não avisa; o professor só responde o que existe; outro professor não responde', async () => {
  const H = await setup();
  const sl = await withClass(H);
  await as(H, ALU, warnBody('aula1', sl.s));
  assert.equal((await as(H, PROF2, { action: 'warn_answer', other: ALU, slot: 'aula1', occ: sl.s, d: 'ok' })).statusCode, 404);
  assert.equal((await as(H, PROF, { action: 'warn_answer', other: ALU, slot: 'aula1', occ: sl.s, d: 'zz' })).statusCode, 400);
  assert.equal((await as(H, PROF, { action: 'warn_answer', other: ALU, slot: 'aula1', occ: sl.s + 7 * DAY, d: 'ok' })).statusCode, 404);
  await as(H, PROF, { action: 'pause', role: 'teacher', other: ALU, on: true });
  assert.equal((await as(H, ALU, warnBody('aula1', sl.s + 7 * DAY))).json().error, 'student_paused');
});

test('encerrar o vínculo limpa pedidos, avisos e respostas dos dois lados', async () => {
  const H = await setup();
  const sl = await withClass(H);
  await putOpen(H, open('h1', { cf: 1 }));
  await take(H, ALU, 'h1', { cv: 2 });
  await as(H, ALU, warnBody('aula1', sl.s));
  await as(H, PROF, { action: 'req_answer', other: ALU, slot: 'h1', accept: false });
  await as(H, PROF, { action: 'unlink', role: 'teacher', other: ALU });
  assert.equal((await inbox(H)).reqs.length + (await inbox(H)).warns.length, 0);
  assert.equal((await as(H, ALU, { action: 's_inbox' })).json().answers.length, 0);
});

test('segurança: ações novas exigem o segredo, dados ruins viram 400 e nada vaza o segredo', async () => {
  const H = await setup();
  const bad = fakeRes();
  await H({ method: 'POST', headers: { 'x-forwarded-for': '9.9.9.9' }, body: { code: PROF, secret: 'f'.repeat(64), action: 't_inbox' }, socket: {} }, bad);
  assert.notEqual(bad.statusCode, 200);
  for (const body of [
    { action: 'req_answer', other: 'x', slot: 'h1', accept: true },
    { action: 'warn_put', other: PROF, slot: '<script>', occ: 1, k: 'no' },
    { action: 'warn_put', other: PROF, slot: 'aula1', occ: 'abc', k: 'no' },
    { action: 'warn_answer', other: ALU, slot: 'a', occ: 1, d: 'ok' },
    { action: 'pick_undo', other: PROF, slot: '../x' },
  ]) {
    const r = await as(H, body.action === 'req_answer' || body.action === 'warn_answer' ? PROF : ALU, body);
    assert.ok(r.statusCode >= 400 && r.statusCode < 500, JSON.stringify(body) + ' -> ' + r.statusCode);
  }
  const t = (await as(H, PROF, { action: 't_inbox' })).body;
  assert.ok(!t.includes(sec(PROF)));
});

// ---------------- o professor guardou o WhatsApp do aluno (só o aviso; o número nunca vem ao servidor) ----------------
test('contato guardado: o aluno vê a marca, só o professor dele marca e o número não é aceito nem guardado', async () => {
  const H = await setup([ALU]);
  const r = await as(H, PROF, { action: 'contact_note', role: 'teacher', other: ALU, on: true, number: '5511912345678', whats: '5511912345678' });
  assert.equal(r.statusCode, 200);
  const sync = (await as(H, ALU, { action: 'sync' })).body;
  assert.equal(JSON.parse(sync).asStudent[0].wa, 1);
  assert.ok(!JSON.stringify([...hashes.entries()].map(([k, v]) => [k, v instanceof Map ? [...v] : v])).includes('5511912345678'), 'o número não fica em lugar nenhum do servidor');
  assert.equal((await as(H, ALU, { action: 'contact_note', role: 'student', other: PROF, on: true })).statusCode, 403);
  assert.equal((await as(H, PROF2, { action: 'contact_note', role: 'teacher', other: ALU, on: true })).statusCode, 404);
  await as(H, PROF, { action: 'contact_note', role: 'teacher', other: ALU, on: false });
  assert.equal((await as(H, ALU, { action: 'sync' })).json().asStudent[0].wa, undefined);
});
