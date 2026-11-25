// Lembrete de estudo automático, sem rede: `node --test api/nudge.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const link = require('./link');
const remind = require('./remind');
const admin = require('./admin');
const nudge = require('./_lib/nudge');
const features = require('./_lib/features');
const wp = require('./_lib/webpush');
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
const PROF = code(11111), ALU = code(22222);
const secret = (c) => crypto.createHash('sha256').update('s' + c).digest('hex');
const VAPID = wp.generateVapidKeys();
// sem chaves de assinatura do QStash: nos testes vale a assinatura própria do servidor
const ENV = { QSTASH_TOKEN: 'qtok', VAPID_PUBLIC_KEY: VAPID.publicKey, VAPID_PRIVATE_KEY: VAPID.privateKey, ADMIN_KEY: 'adm' };
const HOUR = 3600000, DAY = 24 * HOUR;
const T0 = Date.UTC(2026, 10, 25, 15, 0, 0); // quarta, 12:00 em Brasília

let NOW = T0;
let ipN = 0;
let pushStatus = 201;
const calls = [];
const fakeFetch = (url, init) => {
  calls.push({ url: String(url), init });
  return Promise.resolve({ status: String(url).startsWith('https://qstash.upstash.io') ? 200 : pushStatus });
};
const qstash = () => calls.filter((c) => c.url.startsWith('https://qstash.upstash.io')).map((c) => ({ msg: JSON.parse(c.init.body), at: Number(c.init.headers['Upstash-Not-Before']) * 1000 }));
const nudges = () => qstash().filter((q) => q.msg.k === 'nudge');
const pushes = () => calls.filter((c) => c.url.startsWith('https://push.'));

function fakeRes() {
  const r = { headers: {}, statusCode: 0, body: '' };
  r.setHeader = (k, v) => { r.headers[k] = v; };
  r.end = (b) => { r.body = b; };
  r.json = () => JSON.parse(r.body);
  return r;
}
async function post(h, body, headers = {}) {
  const res = fakeRes();
  await h({ method: 'POST', headers: { 'x-forwarded-for': '9.1.' + Math.floor(ipN / 250) + '.' + (ipN++ % 250), ...headers }, body, socket: {} }, res);
  return res;
}
function mk() {
  hashes.clear(); memory.clear(); resetMem(); features.resetCache();
  calls.length = 0; pushStatus = 201; NOW = T0;
  const deps = { config: () => config(ENV), allowMemory: true, fetch: fakeFetch, now: () => NOW };
  return { l: link.makeHandler(deps), r: remind.makeHandler(deps), a: admin.makeHandler(deps) };
}
const as = (H, who, body) => post(H.l, { code: who, secret: secret(who), ...body });
async function setFeature(H, mode) {
  const r = await post(H.a, { action: 'feature_set', id: 'lembrete_estudo', mode }, { authorization: 'Bearer adm' });
  assert.equal(r.statusCode, 200);
  features.resetCache();
}
function subscription(n = 1) {
  const ua = crypto.createECDH('prime256v1');
  ua.generateKeys();
  return { endpoint: `https://push.example.com/send/${'x'.repeat(30)}${n}`, keys: { p256dh: wp.b64u(ua.getPublicKey()), auth: wp.b64u(crypto.randomBytes(16)) } };
}
/** Professor + aluno vinculados, aluno com notificação ligada e o recurso ligado para todos. */
async function cenario({ feature = 'all' } = {}) {
  const H = mk();
  await as(H, ALU, { action: 'sync', name: 'Ana' });
  await as(H, PROF, { action: 'link', role: 'teacher', other: ALU, name: 'Prof. Bia' });
  await setFeature(H, feature);
  assert.equal((await as(H, ALU, { action: 'push_sub', sub: subscription(), tz: -180 })).statusCode, 200);
  return H;
}
/** Entrega a mensagem agendada mais recente, na hora marcada. */
async function entrega(H) {
  const last = nudges().at(-1);
  NOW = last.at;
  calls.length = 0;
  const r = await post(H.r, last.msg);
  assert.equal(r.statusCode, 200, r.body);
  return r.json();
}
const prof = () => hashes.get(`u:${ALU}`);
const field = (k) => (prof() instanceof Map ? prof().get(k) : (prof() || {})[k]);

test('quando conferir: 2 dias à frente, às 18h no fuso da pessoa', () => {
  const at = nudge.nextCheckAt(T0, -180, 2);
  assert.equal(new Date(at).toISOString(), '2026-11-27T21:00:00.000Z', '18h em Brasília');
  assert.equal(new Date(nudge.nextCheckAt(T0, 60, 2)).toISOString(), '2026-11-27T17:00:00.000Z', '18h em UTC+1');
  assert.ok(nudge.nextCheckAt(T0, -180, 0) >= T0 + 12 * HOUR);
  assert.equal(nudge.cleanTz(99999), -180);
});

test('a decisão: parada recebe; quem usa bastante, quem usou há pouco e quem ignorou não recebem', () => {
  const now = T0;
  const day = (d) => new Date(now - d * DAY).toISOString().slice(0, 10);
  const parada = { pa: String(now - 4 * DAY), uh: `${day(4)}:10:1` };
  assert.equal(nudge.decide(parada, now).send, true);
  assert.equal(nudge.decide({ pa: String(now - 20 * HOUR) }, now).send, false, 'usou há pouco');
  const frequente = { pa: String(now - 3 * DAY), uh: [3, 4, 5].map((d) => `${day(d)}:20:1`).join(';') };
  const f = nudge.decide(frequente, now);
  assert.equal(f.send, false);
  assert.equal(f.why, 'usa bastante');
  const ignorou = { ...parada, ngn: '3', ngl: String(now - 1 * DAY) };
  assert.deepEqual([nudge.decide(ignorou, now).send, nudge.decide(ignorou, now).again], [false, 0], 'para de vez');
  const semana = { ...parada, ngn: '2', ngl: `${now - 5 * DAY},${now - 2 * DAY}`, pa: String(now - 8 * DAY) };
  assert.equal(nudge.decide(semana, now).why, 'limite da semana');
  const voltou = { ...parada, ngn: '3', ngl: String(now - 6 * DAY) };
  assert.equal(nudge.decide(voltou, now).send, true, 'voltou depois do último aviso: zera a conta');
  assert.equal(nudge.decide({}, now).send, false, 'sem uso registrado');
});

test('ligar a notificação marca UMA conferência; abrir o app de novo não marca outra', async () => {
  const H = await cenario();
  assert.equal(nudges().length, 1);
  assert.equal(new Date(nudges()[0].at).getUTCHours(), 21, '18h em Brasília');
  for (let i = 0; i < 5; i++) { NOW += 11 * 60000; await as(H, ALU, { action: 'sync' }); }
  assert.equal(nudges().length, 1);
});

test('recurso desligado: nada é agendado; ligado só para o aluno por código também funciona', async () => {
  const H = await cenario({ feature: 'off' });
  assert.equal(nudges().length, 0);
  await setFeature(H, 'list');
  await as(H, ALU, { action: 'sync' });
  assert.equal(nudges().length, 0, 'ainda sem o aluno na lista');
  await post(H.a, { action: 'feature_grant', id: 'lembrete_estudo', code: ALU }, { authorization: 'Bearer adm' });
  features.resetCache();
  await as(H, ALU, { action: 'sync' });
  assert.equal(nudges().length, 1);
});

test('aluno parado há 2 dias recebe o lembrete e a próxima conferência fica para 3 dias depois', async () => {
  const H = await cenario();
  const out = await entrega(H);
  assert.equal(out.sent, 1);
  assert.equal(pushes().length, 1);
  assert.equal(nudges().length, 1, 'marcou a próxima');
  assert.ok(nudges()[0].at - NOW >= 2.5 * DAY);
  assert.equal(String(field('ngn')), '1');
});

test('aluno que abriu o app há pouco não recebe nada, mas continua sendo conferido', async () => {
  const H = await cenario();
  NOW = nudges()[0].at - 5 * HOUR;
  await as(H, ALU, { action: 'sync' }); // abriu o app 5 h antes da conferência
  const out = await entrega(H);
  assert.equal(out.sent, 0);
  assert.equal(pushes().length, 0);
  assert.equal(nudges().length, 1);
});

test('ignorou 3 seguidos: para; quando volta a abrir o app, recomeça do zero', async () => {
  const H = await cenario();
  let enviados = 0;
  for (let i = 0; i < 12 && nudges().length; i++) {
    const out = await entrega(H);
    enviados += out.sent || 0;
    if (out.stopped) break;
  }
  assert.equal(enviados, nudge.MAX_UNANSWERED);
  assert.equal(nudges().length, 0, 'parou de agendar');
  assert.equal(String(field('ngx')), '0');
  NOW += 5 * DAY;
  calls.length = 0;
  await as(H, ALU, { action: 'sync' });
  assert.equal(nudges().length, 1, 'voltou: recomeça');
  assert.equal(String(field('ngn')), '0');
});

test('nunca passa de 2 lembretes em 7 dias', async () => {
  const H = await cenario();
  const horas = [];
  for (let i = 0; i < 8 && nudges().length; i++) {
    const out = await entrega(H);
    if (out.sent) horas.push(NOW);
  }
  for (const t of horas) assert.ok(horas.filter((x) => x >= t && x - t < 7 * DAY).length <= nudge.MAX_PER_WEEK);
});

test('a pessoa desliga o lembrete: a mensagem que estava marcada não envia; ligar de novo volta', async () => {
  const H = await cenario();
  assert.equal((await as(H, ALU, { action: 'nudge_set', on: false })).statusCode, 200);
  assert.equal((await as(H, ALU, { action: 'sync' })).json().nz, 1);
  const out = await entrega(H);
  assert.equal(out.ignored, 'desligado');
  assert.equal(pushes().length, 0);
  calls.length = 0;
  await as(H, ALU, { action: 'nudge_set', on: true });
  assert.equal(nudges().length, 1);
});

test('mensagem antiga, repetida ou com assinatura falsa não faz nada', async () => {
  const H = await cenario();
  const m = nudges()[0].msg;
  NOW = nudges()[0].at;
  assert.equal((await post(H.r, { ...m, sc: PROF })).statusCode, 401, 'trocou o aluno: assinatura não bate');
  assert.equal((await post(H.r, { ...m, sig: 'f'.repeat(64) })).statusCode, 401);
  calls.length = 0;
  await post(H.r, m);
  assert.equal(pushes().length, 1);
  assert.equal((await post(H.r, m)).json().ignored, 'duplicada');
  assert.equal(pushes().length, 1);
});

test('quem só ensina não recebe cobrança de estudo', async () => {
  const H = mk();
  await as(H, ALU, { action: 'sync' });
  await as(H, PROF, { action: 'link', role: 'teacher', other: ALU, name: 'Prof' });
  await setFeature(H, 'all');
  await as(H, PROF, { action: 'push_sub', sub: subscription(2), tz: -180 });
  const out = await entrega(H);
  assert.equal(out.ignored, 'professor');
  assert.equal(pushes().length, 0);
});

test('aparelho que não recebe mais (410): limpa e para', async () => {
  const H = await cenario();
  pushStatus = 410;
  const out = await entrega(H);
  assert.equal(out.ignored, 'sem aparelho');
  assert.equal(nudges().length, 0);
  assert.equal(field('ngp'), undefined);
});

test('o professor não vê nada do lembrete do aluno', async () => {
  const H = await cenario();
  await entrega(H);
  const s = (await as(H, PROF, { action: 'sync' })).body;
  assert.ok(!/ngl|ngn|ngx|ngz|"nz"/.test(s), s);
  assert.equal((await as(H, PROF, { action: 'nudge_set', on: false })).statusCode, 200);
  assert.notEqual(String(field('ngz')), '1', 'o professor desliga só o dele');
});
