// Testes do vínculo professor-aluno, sem rede: `node --test api/link.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { makeHandler, _internal } = require('./link');
const { config } = require('./_lib/config');
const { hashes, memory } = require('./_lib/store');

const A = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
/** Gera um código válido a partir de 7 símbolos. */
function code(seed) {
  let p = '';
  let x = seed;
  for (let i = 0; i < 7; i++) { p += A[x % 32]; x = Math.floor(x / 32) + 7 + i; }
  let s = 0;
  for (let i = 0; i < 7; i++) s += A.indexOf(p[i]) * (2 * i + 1);
  const c = p + A[s % 32];
  return `${c.slice(0, 4)}-${c.slice(4)}`;
}
const PROF = code(11111); // professor
const ALU = code(22222); // aluno
const ALU2 = code(33333);
const secret = (n) => String(n).padStart(2, '0').repeat(32).slice(0, 64).replace(/[^0-9a-f]/g, 'a');
const S_PROF = secret(1), S_ALU = secret(2), S_ALU2 = secret(3);

function fakeRes() {
  const r = { headers: {}, statusCode: 0, body: '' };
  r.setHeader = (k, v) => { r.headers[k] = v; };
  r.end = (b) => { r.body = b; };
  r.json = () => JSON.parse(r.body);
  return r;
}
function mk(env = {}, extra = {}) {
  hashes.clear();
  memory.clear();
  return makeHandler({ config: () => config(env), allowMemory: true, fetch: async () => { throw new Error('sem rede'); }, ...extra });
}
let n = 0;
async function call(h, body, ip) {
  const res = fakeRes();
  await h({ method: 'POST', headers: { 'x-forwarded-for': ip || '7.7.7.' + ++n }, body, socket: {} }, res);
  return res;
}
const sync = (h, c, s) => call(h, { action: 'sync', code: c, secret: s }).then((r) => r.json());

test('os códigos de teste são válidos', () => {
  for (const c of [PROF, ALU, ALU2]) assert.equal(_internal.normCode(c), c);
  assert.equal(_internal.normCode('ABCD-1234'), null);
});

test('sem Redis (e sem modo de teste) devolve 503 e não grava nada', async () => {
  const h = makeHandler({ config: () => config({}), fetch: async () => { throw new Error('x'); } });
  const r = await call(h, { action: 'sync', code: PROF, secret: S_PROF });
  assert.equal(r.statusCode, 503);
  assert.equal(r.json().error, 'sync_unavailable');
});

test('professor lê o QR do aluno: vínculo aparece nos DOIS lados', async () => {
  const h = mk();
  const r = await call(h, { action: 'link', code: PROF, secret: S_PROF, role: 'teacher', other: ALU, name: 'Profa. Ana' });
  assert.equal(r.statusCode, 200);
  assert.equal(r.json().created, true);
  const t = await sync(h, PROF, S_PROF);
  assert.deepEqual(t.asTeacher.map((x) => x.code), [ALU]);
  assert.equal(t.asStudent.length, 0);
  const a = await sync(h, ALU, S_ALU); // o aluno abre o app depois e já vê o professor
  assert.deepEqual(a.asStudent.map((x) => x.code), [PROF]);
  assert.equal(a.asStudent[0].name, 'Profa. Ana');
  assert.equal(a.asTeacher.length, 0);
});

test('aluno lê o QR do professor: o aluno aparece na lista do professor', async () => {
  const h = mk();
  const r = await call(h, { action: 'link', code: ALU, secret: S_ALU, role: 'student', other: PROF, name: 'Bia' });
  assert.equal(r.statusCode, 200);
  const t = await sync(h, PROF, S_PROF);
  assert.deepEqual(t.asTeacher.map((x) => [x.code, x.name]), [[ALU, 'Bia']]);
  const a = await sync(h, ALU, S_ALU);
  assert.deepEqual(a.asStudent.map((x) => x.code), [PROF]);
});

test('repetir o vínculo não duplica', async () => {
  const h = mk();
  const body = { action: 'link', code: PROF, secret: S_PROF, role: 'teacher', other: ALU };
  assert.equal((await call(h, body)).json().created, true);
  assert.equal((await call(h, body)).json().created, false);
  assert.equal((await sync(h, PROF, S_PROF)).asTeacher.length, 1);
});

test('ninguém se vincula a si mesmo', async () => {
  const h = mk();
  const r = await call(h, { action: 'link', code: PROF, secret: S_PROF, role: 'teacher', other: PROF });
  assert.equal(r.statusCode, 400);
  assert.match(r.json().error, /si mesmo/);
});

test('o segredo prova quem é o dono do código; outro segredo é recusado', async () => {
  const h = mk();
  assert.equal((await sync(h, PROF, S_PROF)).ok, true); // registra o dono
  const r = await call(h, { action: 'sync', code: PROF, secret: secret(9) });
  assert.equal(r.statusCode, 403);
  const r2 = await call(h, { action: 'link', code: PROF, secret: secret(9), role: 'teacher', other: ALU });
  assert.equal(r2.statusCode, 403);
  assert.equal((await sync(h, PROF, S_PROF)).asTeacher.length, 0); // nada foi criado
});

test('entradas inválidas', async () => {
  const h = mk();
  assert.equal((await call(h, null)).statusCode, 400);
  assert.equal((await call(h, { action: 'sync', code: 'ABCD-1234', secret: S_PROF })).statusCode, 400);
  assert.equal((await call(h, { action: 'sync', code: PROF, secret: 'curto' })).statusCode, 400);
  assert.equal((await call(h, { action: 'link', code: PROF, secret: S_PROF, role: 'teacher', other: 'XXXX-XXXX' })).statusCode, 400);
  assert.equal((await call(h, { action: 'link', code: PROF, secret: S_PROF, role: 'chefe', other: ALU })).statusCode, 400);
  assert.equal((await call(h, { action: 'voar', code: PROF, secret: S_PROF, role: 'teacher', other: ALU })).statusCode, 400);
  const get = fakeRes();
  await h({ method: 'GET', headers: {}, socket: {} }, get);
  assert.equal(get.statusCode, 405);
});

test('qualquer lado pode desfazer o vínculo', async () => {
  const h = mk();
  await call(h, { action: 'link', code: PROF, secret: S_PROF, role: 'teacher', other: ALU });
  await call(h, { action: 'link', code: PROF, secret: S_PROF, role: 'teacher', other: ALU2 });
  // O aluno encerra:
  assert.equal((await call(h, { action: 'unlink', code: ALU, secret: S_ALU, role: 'student', other: PROF })).statusCode, 200);
  assert.deepEqual((await sync(h, PROF, S_PROF)).asTeacher.map((x) => x.code), [ALU2]);
  assert.equal((await sync(h, ALU, S_ALU)).asStudent.length, 0);
  // O professor encerra o outro:
  await call(h, { action: 'unlink', code: PROF, secret: S_PROF, role: 'teacher', other: ALU2 });
  assert.equal((await sync(h, PROF, S_PROF)).asTeacher.length, 0);
});

test('mesma pessoa pode ser professora de uns e aluna de outros', async () => {
  const h = mk();
  await call(h, { action: 'link', code: PROF, secret: S_PROF, role: 'teacher', other: ALU });
  await call(h, { action: 'link', code: PROF, secret: S_PROF, role: 'student', other: ALU2 });
  const r = await sync(h, PROF, S_PROF);
  assert.deepEqual(r.asTeacher.map((x) => x.code), [ALU]);
  assert.deepEqual(r.asStudent.map((x) => x.code), [ALU2]);
});

test('mudar o apelido atualiza o que o outro lado vê', async () => {
  const h = mk();
  await call(h, { action: 'link', code: ALU, secret: S_ALU, role: 'student', other: PROF, name: 'Bia' });
  await call(h, { action: 'sync', code: ALU, secret: S_ALU, name: 'Beatriz' });
  assert.equal((await sync(h, PROF, S_PROF)).asTeacher[0].name, 'Beatriz');
});

test('limite de alterações por hora', async () => {
  let t = 1_800_000_000_000;
  const h = mk({}, { now: () => t });
  let last;
  for (let i = 0; i < 62; i++) {
    last = await call(h, { action: 'link', code: PROF, secret: S_PROF, role: 'teacher', other: code(40000 + i) });
  }
  assert.equal(last.statusCode, 429);
});

test('apelido: limpa controle e corta o tamanho', async () => {
  const h = mk();
  await call(h, { action: 'link', code: ALU, secret: S_ALU, role: 'student', other: PROF, name: 'A\u0000B\n' + 'x'.repeat(100) });
  const n = (await sync(h, PROF, S_PROF)).asTeacher[0].name;
  assert.ok(n.length <= 40);
  assert.ok(!/[\u0000-\u001f]/.test(n));
});

test('a resposta nunca devolve segredos nem hashes', async () => {
  const h = mk();
  await call(h, { action: 'link', code: PROF, secret: S_PROF, role: 'teacher', other: ALU });
  const out = JSON.stringify(await sync(h, PROF, S_PROF));
  assert.ok(!out.includes(S_PROF));
  assert.ok(!out.includes('"h"'));
});

// ---------------- segurança das entradas ----------------
test('pedido gigante ou que não é objeto é recusado sem tocar no banco', async () => {
  const h = mk();
  const big = await call(h, { action: 'sync', code: PROF, secret: S_PROF, name: 'x'.repeat(5000) });
  assert.equal(big.statusCode, 400);
  const arr = await call(h, [1, 2, 3]);
  assert.equal(arr.statusCode, 400);
  const str = await call(h, 'isto nao e json');
  assert.equal(str.statusCode, 400);
  // com Content-Length declarado enorme também
  const res = fakeRes();
  await h({ method: 'POST', headers: { 'content-length': '999999', 'x-forwarded-for': '8.8.8.8' }, body: { action: 'sync', code: PROF, secret: S_PROF }, socket: {} }, res);
  assert.equal(res.statusCode, 400);
  assert.equal(hashes.size, 0);
});

test('a mesma origem não consegue criar perfis falsos sem limite', async () => {
  const h = mk();
  let blocked = 0;
  for (let i = 0; i < 40; i++) {
    const r = await call(h, { action: 'sync', code: code(50000 + i * 977), secret: secret(i + 10) }, '9.9.9.9');
    if (r.statusCode === 429) blocked++;
  }
  assert.ok(blocked >= 9, 'depois de 30 perfis novos no dia a origem é barrada, bloqueou ' + blocked);
  assert.ok(hashes.size <= 31, 'o banco não cresce sem controle');
  // outra origem continua podendo
  const ok = await call(h, { action: 'sync', code: code(70001), secret: secret(77) }, '10.10.10.10');
  assert.equal(ok.statusCode, 200);
});

test('código e segredo mal formados, ou com lixo, são recusados', async () => {
  const h = mk();
  for (const bad of [
    { code: "'; DROP TABLE x;--", secret: S_PROF },
    { code: PROF, secret: 'zz'.repeat(32) },
    { code: PROF, secret: S_PROF.slice(0, 63) },
    { code: { $ne: null }, secret: S_PROF },
    { code: PROF, secret: ['a'] },
    { code: '<script>alert(1)</script>', secret: S_PROF },
  ]) {
    const r = await call(h, { action: 'sync', ...bad });
    assert.equal(r.statusCode, 400, JSON.stringify(bad));
  }
});

test('apelido enorme ou com controle é cortado e limpo', async () => {
  const h = mk();
  const r = await call(h, { action: 'sync', code: PROF, secret: S_PROF, name: '  Ana\u0000\u0007 ' + 'z'.repeat(500) });
  assert.equal(r.statusCode, 200);
  const j = await sync(h, PROF, S_PROF);
  assert.equal(j.ok, true);
  assert.ok([...hashes.get('u:' + PROF).get('n')].length <= 40);
  assert.ok(!/[\u0000-\u001f]/.test(hashes.get('u:' + PROF).get('n')));
});

// ---------------- aulas: professor publica, aluno busca ----------------
const lessonOf = (id, extra = {}) => ({
  id,
  t: Date.now() - 1000,
  d: 2400,
  tn: 'Profa. Ana',
  tasks: [
    { id: 'k1', title: 'Suzuki · Lição 5', kind: 'method', sub: 'Suzuki', det: 'Lição 5', note: 'Atenção ao arco.\nSem pressa.', st: 0, pc: 0, oct: 1, goal: 0.8, done: false, c: new Date().toISOString() },
    { id: 'k2', title: 'Escala de Sol', kind: 'scale', st: 0, pc: 7, oct: 2, goal: 0.9, c: new Date().toISOString() },
  ],
  notes: ['Soltar o ombro'],
  ...extra,
});
async function vincula(h) {
  await sync(h, ALU, S_ALU); // o aluno abre o app com o vínculo ligado: reivindica o próprio código
  const r = await call(h, { action: 'link', code: PROF, secret: S_PROF, role: 'teacher', other: ALU, name: 'Profa. Ana' });
  assert.equal(r.statusCode, 200);
}
const publish = (h, lesson, other = ALU) => call(h, { action: 'lesson', code: PROF, secret: S_PROF, other, lesson });
const pull = (h, c = ALU, s = S_ALU) => call(h, { action: 'lessons', code: c, secret: s });

test('aula encerrada: o professor publica e o aluno busca tarefas e observações', async () => {
  const h = mk();
  await vincula(h);
  const before = (await sync(h, ALU, S_ALU)).lr;
  assert.equal(before, 0);
  const p = await publish(h, lessonOf('aula0001'));
  assert.equal(p.statusCode, 200);
  const after = (await sync(h, ALU, S_ALU)).lr;
  assert.ok(after > 0, 'o aluno vê que há novidade (lr muda)');
  const r = await pull(h);
  assert.equal(r.statusCode, 200);
  const j = r.json();
  assert.equal(j.lessons.length, 1);
  const l = j.lessons[0];
  assert.equal(l.id, 'aula0001');
  assert.equal(l.by, PROF);
  assert.equal(l.tasks.length, 2);
  assert.equal(l.tasks[0].title, 'Suzuki · Lição 5');
  assert.equal(l.tasks[0].note, 'Atenção ao arco.\nSem pressa.');
  assert.deepEqual(l.notes, ['Soltar o ombro']);
  assert.equal(l.tn, 'Profa. Ana');
});

test('republicar a mesma aula não duplica (mesmo id)', async () => {
  const h = mk();
  await vincula(h);
  await publish(h, lessonOf('aula0002'));
  await publish(h, lessonOf('aula0002', { d: 3000 }));
  const j = (await pull(h)).json();
  assert.equal(j.lessons.length, 1);
  assert.equal(j.lessons[0].d, 3000);
});

test('só publica para aluno VINCULADO; outro professor não escreve na área alheia', async () => {
  const h = mk();
  await vincula(h);
  // aluno 2 nunca se vinculou a este professor
  const r = await publish(h, lessonOf('aula0003'), ALU2);
  assert.equal(r.statusCode, 403);
  // o aluno não pode publicar "como professor" para si mesmo
  const self = await call(h, { action: 'lesson', code: ALU, secret: S_ALU, other: PROF, lesson: lessonOf('aula0004') });
  assert.equal(self.statusCode, 403);
  assert.equal((await pull(h)).json().lessons.length, 0);
});

test('o aluno só recebe aulas de quem ainda está vinculado; ao desvincular elas somem', async () => {
  const h = mk();
  await vincula(h);
  await publish(h, lessonOf('aula0005'));
  assert.equal((await pull(h)).json().lessons.length, 1);
  const u = await call(h, { action: 'unlink', code: ALU, secret: S_ALU, role: 'student', other: PROF });
  assert.equal(u.statusCode, 200);
  assert.equal((await pull(h)).json().lessons.length, 0);
  // religar não ressuscita aulas antigas: foram apagadas
  await vincula(h);
  assert.equal((await pull(h)).json().lessons.length, 0);
});

test('autenticação: outro aparelho não busca as aulas do aluno', async () => {
  const h = mk();
  await vincula(h);
  await publish(h, lessonOf('aula0006'));
  const r = await pull(h, ALU, secret(9));
  assert.equal(r.statusCode, 403);
});

test('aula inválida é recusada: id, data, tipos errados, formato', async () => {
  const h = mk();
  await vincula(h);
  for (const bad of [
    lessonOf('<script>'),
    lessonOf('AULA'),
    lessonOf('aula0007', { t: 5 }),
    lessonOf('aula0007', { t: Date.now() + 10 * 86400000 }),
    lessonOf('aula0007', { tasks: 'x' }),
    lessonOf('aula0007', { notes: { a: 1 } }),
    'texto',
    null,
    [],
  ]) {
    const r = await publish(h, bad);
    assert.equal(r.statusCode, 400, JSON.stringify(bad));
  }
});

test('o servidor limpa e limita o conteúdo da aula', async () => {
  const h = mk();
  await vincula(h);
  const tasks = [];
  for (let i = 0; i < 36; i++) tasks.push({ id: 't' + i, title: 'Tarefa\u202E ' + 'x'.repeat(150), kind: 'hack', note: 'n'.repeat(600), pc: 99, oct: 50, goal: 7, st: -5 });
  tasks.push({ id: '<b>', title: 'sem id valido' });
  const r = await publish(h, lessonOf('aula0008', { tasks, notes: ['a\u0000b', '', 'z'.repeat(3000), ...Array(30).fill('ok')] }));
  assert.equal(r.statusCode, 200, r.body);
  const l = (await pull(h)).json().lessons[0];
  assert.equal(l.tasks.length, 30);
  const t = l.tasks[0];
  assert.ok(t.title.length <= 80 && !t.title.includes('\u202E'));
  assert.equal(t.kind, 'scale');
  assert.equal(t.note.length, 500);
  assert.equal(t.pc, 11);
  assert.equal(t.oct, 3);
  assert.equal(t.goal, 1);
  assert.equal(t.st, 0);
  assert.equal(t.done, false);
  assert.ok(l.notes.length <= 10);
  assert.equal(l.notes[0], 'a b');
});

test('guarda só as 60 aulas mais recentes por aluno', async () => {
  let clk = Date.now();
  const h = mk({}, { now: () => clk });
  await vincula(h);
  for (let i = 0; i < 64; i++) {
    if (i % 30 === 29) clk += 3700000; // passa uma hora: o limite de alterações por hora zera
    const id = 'a' + String(1000 + i);
    const r = await call(h, { action: 'lesson', code: PROF, secret: S_PROF, other: ALU, lesson: lessonOf(id, { t: clk - (100 - i) * 60000 }) }, '5.5.5.' + (i % 200));
    assert.equal(r.statusCode, 200, r.body);
  }
  const j = (await pull(h)).json();
  assert.equal(j.lessons.length, 60);
  assert.ok(!j.lessons.some((l) => l.id === 'a1000'), 'a mais antiga foi descartada');
  assert.ok(j.lessons.some((l) => l.id === 'a1063'));
});

test('pedido de aula grande demais é recusado antes de ler', async () => {
  const h = mk();
  await vincula(h);
  const r = await publish(h, lessonOf('aula0009', { notes: ['x'.repeat(60000)] }));
  assert.equal(r.statusCode, 400);
});

test('aluno que ainda não reivindicou o código não recebe aula (ninguém "rouba" o código antes)', async () => {
  const h = mk();
  // o professor liga o aluno ANTES de o aluno abrir o app com o vínculo ligado
  const l = await call(h, { action: 'link', code: PROF, secret: S_PROF, role: 'teacher', other: ALU, name: 'Profa. Ana' });
  assert.equal(l.statusCode, 200);
  const r = await publish(h, lessonOf('aula0010'));
  assert.equal(r.statusCode, 409);
  assert.equal(r.json().error, 'student_not_ready');
  // um terceiro tenta reivindicar o código do aluno e ler: não há nada guardado
  const thief = await pull(h, ALU, secret(9));
  assert.equal(thief.statusCode, 200);
  assert.equal(thief.json().lessons.length, 0);
});

// ---------------- dois professores para o mesmo aluno ----------------
const PROF2 = code(44444);
const S_PROF2 = secret(4);
async function vinculaDois(h) {
  await sync(h, ALU, S_ALU);
  for (const [c, s] of [[PROF, S_PROF], [PROF2, S_PROF2]]) {
    const r = await call(h, { action: 'link', code: c, secret: s, role: 'teacher', other: ALU });
    assert.equal(r.statusCode, 200);
  }
}

test('dois professores: o aluno recebe as aulas dos dois, mesmo com o mesmo id de aula', async () => {
  const h = mk();
  await vinculaDois(h);
  const a = await call(h, { action: 'lesson', code: PROF, secret: S_PROF, other: ALU, lesson: lessonOf('mesmoid01') });
  const b = await call(h, { action: 'lesson', code: PROF2, secret: S_PROF2, other: ALU, lesson: lessonOf('mesmoid01', { tn: 'Prof. B' }) });
  assert.equal(a.statusCode, 200);
  assert.equal(b.statusCode, 200);
  const j = (await pull(h)).json();
  assert.equal(j.lessons.length, 2);
  assert.deepEqual(j.lessons.map((l) => l.by).sort(), [PROF, PROF2].sort());
});

test('dois professores: desvincular um só apaga as aulas dele', async () => {
  const h = mk();
  await vinculaDois(h);
  await call(h, { action: 'lesson', code: PROF, secret: S_PROF, other: ALU, lesson: lessonOf('aula0020') });
  await call(h, { action: 'lesson', code: PROF2, secret: S_PROF2, other: ALU, lesson: lessonOf('aula0021') });
  const u = await call(h, { action: 'unlink', code: ALU, secret: S_ALU, role: 'student', other: PROF });
  assert.equal(u.statusCode, 200);
  const j = (await pull(h)).json();
  assert.deepEqual(j.lessons.map((l) => l.id), ['aula0021']);
  assert.equal(j.lessons[0].by, PROF2);
});

test('compatível com app antigo: sync continua devolvendo as listas e só acrescenta lr', async () => {
  const h = mk();
  await vincula(h);
  const j = await sync(h, ALU, S_ALU);
  assert.equal(j.ok, true);
  assert.ok(Array.isArray(j.asStudent) && Array.isArray(j.asTeacher));
  assert.equal(typeof j.lr, 'number');
  assert.deepEqual(Object.keys(j.asStudent[0]).sort(), ['by', 'code', 'name', 'since']);
});

test('tarefas avulsas (fora de aula, sem duração) são aceitas e chegam ao aluno', async () => {
  const h = mk();
  await vincula(h);
  const pkg = lessonOf('avulsa001', { d: 0, notes: [] });
  const r = await call(h, { action: 'lesson', code: PROF, secret: S_PROF, other: ALU, lesson: pkg });
  assert.equal(r.statusCode, 200);
  const j = (await pull(h)).json();
  const got = j.lessons.find((l) => l.id === 'avulsa001');
  assert.ok(got, 'o aluno recebe o pacote');
  assert.equal(got.d, 0);
  assert.ok(got.tasks.length >= 1);
  assert.equal(got.by, PROF);
});

test('o controle de envio do professor (snt) nunca é guardado no servidor', async () => {
  const h = mk();
  await vincula(h);
  const pkg = lessonOf('avulsa002', { d: 0 });
  pkg.tasks = pkg.tasks.map((t) => ({ ...t, snt: false }));
  const r = await call(h, { action: 'lesson', code: PROF, secret: S_PROF, other: ALU, lesson: pkg });
  assert.equal(r.statusCode, 200);
  const j = (await pull(h)).json();
  const got = j.lessons.find((l) => l.id === 'avulsa002');
  assert.ok(got);
  for (const t of got.tasks) assert.equal('snt' in t, false);
});

// ---- Tarefas marcadas como feitas pelo aluno (o professor valida) ----
const markDone = (h, task = 'k1', done = true, lesson = 'aula0001', teacher = PROF) =>
  call(h, { action: 'done', code: ALU, secret: S_ALU, other: teacher, lesson, task, done });
const teacherDones = (h) => call(h, { action: 'dones', code: PROF, secret: S_PROF });

test('aluno marca tarefa como feita: o professor vê a marcação e a revisão dr muda', async () => {
  const h = mk();
  await vincula(h);
  assert.equal((await sync(h, PROF, S_PROF)).dr, 0);
  const r = await markDone(h);
  assert.equal(r.statusCode, 200);
  assert.ok((await sync(h, PROF, S_PROF)).dr > 0, 'dr avisa o professor');
  const j = (await teacherDones(h)).json();
  assert.equal(j.dones.length, 1);
  assert.deepEqual({ s: j.dones[0].s, l: j.dones[0].l, k: j.dones[0].k }, { s: ALU, l: 'aula0001', k: 'k1' });
  assert.ok(j.dones[0].t > 0);
});

test('aluno desmarca: a marcação some para o professor', async () => {
  const h = mk();
  await vincula(h);
  await markDone(h);
  await markDone(h, 'k2');
  await markDone(h, 'k1', false);
  const j = (await teacherDones(h)).json();
  assert.deepEqual(j.dones.map((d) => d.k), ['k2']);
});

test('marcar a mesma tarefa duas vezes não duplica', async () => {
  const h = mk();
  await vincula(h);
  await markDone(h);
  await markDone(h);
  assert.equal((await teacherDones(h)).json().dones.length, 1);
});

test('só o aluno vinculado marca; ids inválidos e professor não vinculado são recusados', async () => {
  const h = mk();
  await vincula(h);
  const outro = code(99999);
  assert.equal((await markDone(h, 'k1', true, 'aula0001', outro)).statusCode, 403);
  assert.equal((await markDone(h, 'k 1')).statusCode, 400);
  assert.equal((await markDone(h, 'k1', true, 'AULA 1')).statusCode, 400);
  assert.equal((await markDone(h, 'k1', true, 'aula0001', 'xxxx')).statusCode, 400);
  assert.equal((await teacherDones(h)).json().dones.length, 0);
});

test('professor só vê marcações de aluno ainda vinculado; desvincular apaga as marcações', async () => {
  const h = mk();
  await vincula(h);
  await markDone(h);
  const u = await call(h, { action: 'unlink', code: ALU, secret: S_ALU, role: 'student', other: PROF });
  assert.equal(u.statusCode, 200);
  assert.equal((await teacherDones(h)).json().dones.length, 0);
});

test('um aluno não lê nem apaga as marcações de outro aluno', async () => {
  const h = mk();
  await vincula(h);
  await sync(h, ALU2, S_ALU2);
  await call(h, { action: 'link', code: PROF, secret: S_PROF, role: 'teacher', other: ALU2, name: 'B' });
  await markDone(h);
  await call(h, { action: 'done', code: ALU2, secret: S_ALU2, other: PROF, lesson: 'aula0001', task: 'k1', done: false });
  assert.equal((await teacherDones(h)).json().dones.length, 1, 'a marcação do aluno A continua');
});

test('rev: consulta barata devolve só os contadores e muda quando há novidade', async () => {
  const h = mk();
  await vincula(h);
  const a = (await call(h, { action: 'rev', code: ALU, secret: S_ALU })).json();
  assert.deepEqual(Object.keys(a).sort(), ['dr', 'kr', 'lr', 'ok', 'sr', 'vr']);
  assert.ok(a.kr > 0, 'o vínculo mudou os contadores de vínculos');
  await publish(h, lessonOf('aula0001'));
  const b = (await call(h, { action: 'rev', code: ALU, secret: S_ALU })).json();
  assert.ok(b.lr > a.lr, 'aula nova muda lr');
  assert.equal(b.kr, a.kr, 'sem mudança de vínculo, kr igual');
  const t1 = (await call(h, { action: 'rev', code: PROF, secret: S_PROF })).json();
  await markDone(h);
  const t2 = (await call(h, { action: 'rev', code: PROF, secret: S_PROF })).json();
  assert.ok(t2.dr > t1.dr, 'marcação do aluno muda dr do professor');
});

test('rev exige o segredo do perfil (não vaza contadores de outro código)', async () => {
  const h = mk();
  await vincula(h);
  const r = await call(h, { action: 'rev', code: ALU, secret: S_PROF });
  assert.equal(r.statusCode, 403);
});

test('compatível com app antigo: sync ganha dr e kr sem perder nada do que já devolvia', async () => {
  const h = mk();
  await vincula(h);
  const j = await sync(h, ALU, S_ALU);
  for (const k of ['ok', 'asTeacher', 'asStudent', 'lr']) assert.ok(k in j);
  assert.equal(typeof j.dr, 'number');
  assert.equal(typeof j.kr, 'number');
});

// ---- Decisão oficial do professor (validar / devolver) e o que o aluno vê ----
const decide = (h, verdict, task = 'k1', lesson = 'aula0001', student = ALU, who = [PROF, S_PROF]) =>
  call(h, { action: 'verdict', code: who[0], secret: who[1], other: student, lesson, task, verdict });
const studentVerdicts = (h, c = ALU, s = S_ALU) => call(h, { action: 'verdicts', code: c, secret: s });

test('professor valida: o aluno vê a decisão e a revisão vr muda', async () => {
  const h = mk();
  await vincula(h);
  assert.equal((await sync(h, ALU, S_ALU)).vr, 0);
  assert.equal((await decide(h, 'ok')).statusCode, 200);
  assert.ok((await sync(h, ALU, S_ALU)).vr > 0);
  const j = (await studentVerdicts(h)).json();
  assert.equal(j.verdicts.length, 1);
  assert.deepEqual({ te: j.verdicts[0].te, l: j.verdicts[0].l, k: j.verdicts[0].k, v: j.verdicts[0].v }, { te: PROF, l: 'aula0001', k: 'k1', v: 'ok' });
});

test('devolver troca a decisão (não duplica) e vazio apaga', async () => {
  const h = mk();
  await vincula(h);
  await decide(h, 'ok');
  await decide(h, 'back');
  let j = (await studentVerdicts(h)).json();
  assert.equal(j.verdicts.length, 1);
  assert.equal(j.verdicts[0].v, 'back');
  await decide(h, '');
  j = (await studentVerdicts(h)).json();
  assert.equal(j.verdicts.length, 0);
});

test('só o professor vinculado decide; entradas inválidas são recusadas', async () => {
  const h = mk();
  await vincula(h);
  const intruso = code(88888);
  assert.equal((await decide(h, 'ok', 'k1', 'aula0001', ALU, [intruso, secret(9)])).statusCode, 403); // perfil novo (anônimo) sem vínculo
  await sync(h, ALU2, S_ALU2);
  assert.equal((await decide(h, 'ok', 'k1', 'aula0001', ALU2)).statusCode, 403, 'aluno não vinculado a este professor');
  assert.equal((await decide(h, 'talvez')).statusCode, 400);
  assert.equal((await decide(h, 'ok', 'k 1')).statusCode, 400);
  assert.equal((await decide(h, 'ok', 'k1', 'AULA 1')).statusCode, 400);
  assert.equal((await decide(h, 'ok', 'k1', 'aula0001', PROF)).statusCode, 400, 'não decide sobre si mesmo');
  assert.equal((await studentVerdicts(h)).json().verdicts.length, 0);
});

test('um aluno não lê as decisões de outro; aluno não consegue decidir', async () => {
  const h = mk();
  await vincula(h);
  await sync(h, ALU2, S_ALU2);
  await decide(h, 'ok');
  assert.equal((await studentVerdicts(h, ALU2, S_ALU2)).json().verdicts.length, 0);
  // o aluno tentando "decidir" como se fosse professor: não está vinculado como professor de ninguém
  const r = await call(h, { action: 'verdict', code: ALU, secret: S_ALU, other: PROF, lesson: 'aula0001', task: 'k1', verdict: 'ok' });
  assert.equal(r.statusCode, 403);
});

test('desvincular apaga as decisões; decisão de vínculo antigo não aparece', async () => {
  const h = mk();
  await vincula(h);
  await decide(h, 'ok');
  await call(h, { action: 'unlink', code: ALU, secret: S_ALU, role: 'student', other: PROF });
  assert.equal((await studentVerdicts(h)).json().verdicts.length, 0);
});

test('compatibilidade: app antigo ignora vr e as ações antigas continuam iguais', async () => {
  const h = mk();
  await vincula(h);
  const s = await sync(h, ALU, S_ALU);
  for (const k of ['lr', 'dr', 'kr', 'sr']) assert.equal(typeof s[k], 'number');
  assert.equal((await markDone(h)).statusCode, 200);
  assert.equal((await teacherDones(h)).json().dones.length, 1);
});

test('devolver tira a marcação "fiz" do aluno (não volta a pedir validação); validar mantém', async () => {
  const h = mk();
  await vincula(h);
  await markDone(h);
  await markDone(h, 'k2');
  await decide(h, 'back', 'k1');
  await decide(h, 'ok', 'k2');
  const ks = (await teacherDones(h)).json().dones.map((d) => d.k);
  assert.deepEqual(ks, ['k2']);
});
