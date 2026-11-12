// Testes do lembrete escolhido pelo professor (chave `lembrete_escolha`): `node --test api/remind_choice.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const link = require('./link');
const admin = require('./admin');
const features = require('./_lib/features');
const ag = require('./_lib/agenda');
const wp = require('./_lib/webpush');
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
const PROF = code(41), ALU = code(42);
const secret = (c) => crypto.createHash('sha256').update('s' + c).digest('hex');
const KEY = 'chave-admin-de-teste';
const V = wp.generateVapidKeys();
const ENV = { ADMIN_KEY: KEY, QSTASH_TOKEN: 'qtok', QSTASH_CURRENT_SIGNING_KEY: 'cur', QSTASH_NEXT_SIGNING_KEY: 'nxt', VAPID_PUBLIC_KEY: V.publicKey, VAPID_PRIVATE_KEY: V.privateKey };
const NOW = 1_800_000_000_000;
const MIN = 60000;
const DAY = 86400000;
let ipN = 0;
const calls = [];
const fakeFetch = (url, init) => { calls.push({ url: String(url), init }); return Promise.resolve({ status: 200 }); };
const q = () => calls.filter((c) => c.url.startsWith('https://qstash.upstash.io'));
const lastAt = () => Number(q().at(-1).init.headers['Upstash-Not-Before']) * 1000;

function fakeRes() {
  const r = { headers: {}, statusCode: 0, body: '' };
  r.setHeader = (k, v) => { r.headers[k] = v; };
  r.end = (b) => { r.body = b; };
  r.json = () => JSON.parse(r.body);
  return r;
}
async function setup({ ligado }) {
  hashes.clear(); memory.clear(); resetMem(); features.resetCache(); calls.length = 0;
  const deps = { config: () => config(ENV), allowMemory: true, fetch: fakeFetch, now: () => NOW };
  const H = { l: link.makeHandler(deps), a: admin.makeHandler(deps) };
  const as = async (who, body) => {
    const res = fakeRes();
    await H.l({ method: 'POST', headers: { 'x-forwarded-for': '6.6.6.' + ++ipN }, body: { code: who, secret: secret(who), ...body }, socket: {} }, res);
    return res;
  };
  const adm = async (body) => {
    const res = fakeRes();
    await H.a({ method: 'POST', headers: { 'x-forwarded-for': '7.7.7.' + ++ipN, authorization: 'Bearer ' + KEY }, body, socket: {} }, res);
    return res;
  };
  await as(ALU, { action: 'sync', name: 'Ana' });
  await as(PROF, { action: 'sync', name: 'Prof' });
  await as(PROF, { action: 'link', role: 'teacher', other: ALU });
  if (ligado) assert.equal((await adm({ action: 'feature_grant', id: 'lembrete_escolha', code: PROF })).statusCode, 200);
  calls.length = 0;
  return { as, adm };
}
const slot = (id, extra = {}) => ({ id, s: NOW + 3 * DAY, d: 60, u: NOW, ...extra });
const put = (H, s) => H.as(PROF, { action: 'sched_put', other: ALU, slot: s });
const mineAlu = async (H) => (await H.as(ALU, { action: 'sched' })).json().slots;

test('o filtro: só as antecedências permitidas passam', () => {
  const ok = (r) => ag.cleanSlot({ id: 'aaaa', s: NOW, d: 60, u: NOW, r }, NOW);
  for (const r of [0, 5, 10, 15, 30, 60, 120, 1440]) assert.equal(ok(r).r, r);
  for (const r of [7, -5, 1441, 'abc', NaN, 1e9]) assert.equal(ok(r).r, undefined, `r=${r}`);
  assert.equal(ok(undefined).r, undefined);
  assert.equal(ok(null).r, undefined);
  assert.equal(ok('30').r, 30);
});

test('sem a chave: o r enviado é ignorado e o aviso continua 15 min antes', async () => {
  const H = await setup({ ligado: false });
  const s = slot('aula1', { r: 60 });
  assert.equal((await put(H, s)).json().reminder, 'scheduled');
  assert.equal(lastAt(), s.s - 15 * MIN);
  assert.equal((await mineAlu(H))[0].r, undefined);
});

test('app antigo (sem o campo r): continua 15 min antes', async () => {
  const H = await setup({ ligado: true });
  const s = slot('aula1');
  await put(H, s);
  assert.equal(lastAt(), s.s - 15 * MIN);
});

test('com a chave: o professor escolhe e o aluno recebe a escolha', async () => {
  const H = await setup({ ligado: true });
  for (const [r, id] of [[5, 'aaa5'], [30, 'aa30'], [60, 'aa60'], [120, 'aa120'], [1440, 'aa1440']]) {
    const s = slot(id, { r });
    assert.equal((await put(H, s)).json().reminder, 'scheduled');
    assert.equal(lastAt(), s.s - r * MIN, `r=${r}`);
  }
  assert.equal((await mineAlu(H)).find((x) => x.id === 'aa30').r, 30);
});

test('sem lembrete (r=0): nada é agendado no QStash', async () => {
  const H = await setup({ ligado: true });
  const res = await put(H, slot('aula1', { r: 0 }));
  assert.equal(res.statusCode, 200);
  assert.equal(res.json().reminder, 'none');
  assert.equal(q().length, 0);
  assert.equal((await mineAlu(H))[0].r, 0);
});

test('valor inválido é ignorado: vale o padrão de 15 min', async () => {
  const H = await setup({ ligado: true });
  const s = slot('aula1', { r: 7 });
  await put(H, s);
  assert.equal(lastAt(), s.s - 15 * MIN);
  assert.equal((await mineAlu(H))[0].r, undefined);
});

test('editar a aula troca o horário do aviso; voltar para 15 apaga a escolha antiga', async () => {
  const H = await setup({ ligado: true });
  const s = slot('aula1', { r: 60 });
  await put(H, s);
  assert.equal(lastAt(), s.s - 60 * MIN);
  await put(H, { ...s, r: 15, u: NOW + 1 });
  assert.equal(lastAt(), s.s - 15 * MIN, 'r=15 explícito não ressuscita o 60 antigo');
  assert.equal((await mineAlu(H))[0].r, 15);
});

test('app antigo editando uma aula com escolha: o servidor mantém a escolha', async () => {
  const H = await setup({ ligado: true });
  const s = slot('aula1', { r: 30 });
  await put(H, s);
  const { r: _ignorado, ...semR } = s;
  await put(H, { ...semR, d: 45, u: NOW + 1 }); // o app antigo não manda r
  const a = (await mineAlu(H))[0];
  assert.equal(a.d, 45);
  assert.equal(a.r, 30);
  assert.equal(lastAt(), s.s - 30 * MIN);
});

test('chave desligada depois: edições novas não mudam a escolha já guardada', async () => {
  const H = await setup({ ligado: true });
  const s = slot('aula1', { r: 30 });
  await put(H, s);
  assert.equal((await H.adm({ action: 'feature_set', id: 'lembrete_escolha', mode: 'off' })).statusCode, 200);
  features.resetCache();
  await put(H, { ...s, r: 5, u: NOW + 1 });
  assert.equal((await mineAlu(H))[0].r, 30);
});

test('horário livre: a escolha vai para a aula que o aluno pega', async () => {
  const H = await setup({ ligado: true });
  const open = slot('livre1', { r: 120, s: NOW + 4 * DAY });
  assert.equal((await H.as(PROF, { action: 'avail_put', slot: open })).statusCode, 200);
  assert.equal((await H.as(ALU, { action: 'avail_take', other: PROF, slot: 'livre1' })).statusCode, 200);
  const cls = (await mineAlu(H))[0];
  assert.equal(cls.r, 120);
  assert.equal(lastAt(), open.s - 120 * MIN);
});

test('aula daqui a poucas horas com aviso de 1 dia: o aviso sai logo (não no passado)', async () => {
  const H = await setup({ ligado: true });
  const s = slot('aula1', { r: 1440, s: NOW + 3 * 3600000 });
  assert.equal((await put(H, s)).json().reminder, 'scheduled');
  assert.equal(lastAt(), NOW + 5000);
});

test('aviso de 1 dia numa aula daqui a 20 dias: acorda em até 6 dias e agenda de novo', async () => {
  const H = await setup({ ligado: true });
  const s = slot('aula1', { r: 1440, s: NOW + 20 * DAY });
  await put(H, s);
  assert.equal(JSON.parse(q()[0].init.body).k, 'wake');
  assert.ok(lastAt() - NOW <= 6 * DAY);
});

test('texto da notificação (web/sw.js) diz o tempo que realmente falta', () => {
  const src = require('node:fs').readFileSync(require('node:path').join(__dirname, '..', 'web', 'sw.js'), 'utf8');
  const fn = src.match(/function lessonTitle[\s\S]*?\n}\n/)[0];
  const lessonTitle = new Function(`${fn}; return lessonTitle;`)();
  const t = (mins) => lessonTitle(NOW + mins * MIN, NOW);
  assert.equal(t(15), 'Aula em 15 minutos');
  assert.equal(t(5), 'Aula em 5 minutos');
  assert.equal(t(45), 'Aula em 45 minutos');
  assert.equal(t(60), 'Aula em 1 hora');
  assert.equal(t(120), 'Aula em 2 horas');
  assert.equal(t(1440), 'Aula amanhã');
  assert.equal(t(1), 'Aula começando agora');
  assert.equal(t(-3), 'Aula começando agora');
});

test('as opções do servidor e do app (kRemindOptions) são as mesmas', () => {
  const src = require('node:fs').readFileSync(require('node:path').join(__dirname, '..', 'packages', 'afina_core', 'lib', 'agenda.dart'), 'utf8');
  const m = src.match(/kRemindOptions\s*=\s*\[([^\]]*)\]/);
  assert.ok(m, 'kRemindOptions não encontrada no núcleo');
  assert.deepEqual(m[1].split(',').map((x) => Number(x.trim())), ag.REMIND_OPTIONS);
});
