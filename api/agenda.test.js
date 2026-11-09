// Testes da agenda e dos lembretes, sem rede: `node --test api/agenda.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const link = require('./link');
const remind = require('./remind');
const { config } = require('./_lib/config');
const { hashes, memory } = require('./_lib/store');
const wp = require('./_lib/webpush');
const ag = require('./_lib/agenda');

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
const PROF = code(11111), ALU = code(22222), ALU2 = code(33333);
const secret = (c) => crypto.createHash('sha256').update('s' + c).digest('hex');
const S = { [PROF]: secret(PROF), [ALU]: secret(ALU), [ALU2]: secret(ALU2) };

const VAPID = wp.generateVapidKeys();
const ENV = {
  QSTASH_TOKEN: 'qtok', QSTASH_CURRENT_SIGNING_KEY: 'cur', QSTASH_NEXT_SIGNING_KEY: 'nxt',
  VAPID_PUBLIC_KEY: VAPID.publicKey, VAPID_PRIVATE_KEY: VAPID.privateKey,
};

let NOW = 1_800_000_000_000; // relógio fixo dos testes
let ipN = 0;
const calls = []; // tudo que o servidor tentou chamar fora (QStash e servidores de push)
let pushStatus = 201;

function fakeFetch(url, init) {
  calls.push({ url: String(url), init });
  if (String(url).startsWith('https://qstash.upstash.io')) return Promise.resolve({ status: 200 });
  return Promise.resolve({ status: pushStatus });
}
function mkHandlers(env = ENV) {
  hashes.clear();
  memory.clear();
  calls.length = 0;
  pushStatus = 201;
  const deps = { config: () => config(env), allowMemory: true, fetch: fakeFetch, now: () => NOW };
  return { l: link.makeHandler(deps), r: remind.makeHandler(deps) };
}
function fakeRes() {
  const r = { headers: {}, statusCode: 0, body: '' };
  r.setHeader = (k, v) => { r.headers[k] = v; };
  r.end = (b) => { r.body = b; };
  r.json = () => JSON.parse(r.body);
  return r;
}
async function post(h, body, headers = {}) {
  const res = fakeRes();
  await h({ method: 'POST', headers: { 'x-forwarded-for': '9.9.9.' + ++ipN, ...headers }, body, socket: {} }, res);
  return res;
}
const callL = (H, who, body) => post(H.l, { code: who, secret: S[who], ...body });

async function vincula(H) {
  await callL(H, ALU, { action: 'sync' }); // o aluno reivindica o próprio código
  const r = await callL(H, PROF, { action: 'link', role: 'teacher', other: ALU, name: 'Profa. Ana' });
  assert.equal(r.statusCode, 200);
}
function slotOf(id, extra = {}) {
  return { id, s: NOW + 3 * 86400000, d: 60, u: NOW, ...extra };
}
const put = (H, slot, other = ALU) => callL(H, PROF, { action: 'sched_put', other, slot });
const qstashCalls = () => calls.filter((c) => c.url.startsWith('https://qstash.upstash.io'));

function subscription(host = 'push.example.com', n = 1) {
  const ua = crypto.createECDH('prime256v1');
  ua.generateKeys();
  return {
    endpoint: `https://${host}/send/${'x'.repeat(30)}${n}`,
    keys: { p256dh: wp.b64u(ua.getPublicKey()), auth: wp.b64u(crypto.randomBytes(16)) },
  };
}

test('marcar aula exige aluno vinculado e que ele já tenha aberto o app', async () => {
  const H = mkHandlers();
  assert.equal((await put(H, slotOf('aula1'))).statusCode, 403, 'sem vínculo');
  await callL(H, PROF, { action: 'link', role: 'teacher', other: ALU2, name: 'x' }); // aluno que nunca abriu o app
  const r = await put(H, slotOf('aula1'), ALU2);
  assert.equal(r.statusCode, 409);
  assert.equal(r.json().error, 'student_not_ready');
});

test('professor marca, o aluno busca; o contador sr avisa o aluno', async () => {
  const H = mkHandlers();
  await vincula(H);
  const before = (await callL(H, ALU, { action: 'rev' })).json();
  assert.equal(before.sr, 0);
  const r = await put(H, slotOf('aula1', { w: 1, n: 'Trazer o arco' }));
  assert.equal(r.statusCode, 200);
  const after = (await callL(H, ALU, { action: 'rev' })).json();
  assert.ok(after.sr > 0);
  const j = (await callL(H, ALU, { action: 'sched' })).json();
  assert.equal(j.slots.length, 1);
  assert.equal(j.slots[0].id, 'aula1');
  assert.equal(j.slots[0].by, PROF);
  assert.equal(j.slots[0].tn, 'Profa. Ana');
  assert.equal(j.slots[0].w, 1);
  assert.equal(j.slots[0].n, 'Trazer o arco');
  assert.equal('sc' in j.slots[0], false, 'o aluno não recebe campos do professor');
});

test('um aluno só vê as aulas marcadas para ele, e só de professor ainda vinculado', async () => {
  const H = mkHandlers();
  await vincula(H);
  await callL(H, ALU2, { action: 'sync' });
  await callL(H, PROF, { action: 'link', role: 'teacher', other: ALU2, name: 'y' });
  await put(H, slotOf('paraalu'), ALU);
  await put(H, slotOf('paraalu2'), ALU2);
  assert.deepEqual((await callL(H, ALU, { action: 'sched' })).json().slots.map((s) => s.id), ['paraalu']);
  assert.deepEqual((await callL(H, ALU2, { action: 'sched' })).json().slots.map((s) => s.id), ['paraalu2']);
  await callL(H, ALU, { action: 'unlink', role: 'student', other: PROF });
  assert.equal((await callL(H, ALU, { action: 'sched' })).json().slots.length, 0, 'vínculo desfeito: some');
});

test('lembrete é agendado no QStash 15 min antes, com assinatura e destino certos', async () => {
  const H = mkHandlers();
  await vincula(H);
  const slot = slotOf('aula1');
  const r = await put(H, slot);
  assert.equal(r.json().reminder, 'scheduled');
  const q = qstashCalls();
  assert.equal(q.length, 1);
  assert.equal(q[0].url, 'https://qstash.upstash.io/v2/publish/https://notemusicmap.vercel.app/api/remind');
  assert.equal(q[0].init.headers.Authorization, 'Bearer qtok');
  assert.equal(q[0].init.headers['Upstash-Not-Before'], String(Math.floor((slot.s - 15 * 60000) / 1000)));
  const body = JSON.parse(q[0].init.body);
  assert.deepEqual({ t: body.t, sc: body.sc, id: body.id, o: body.o, k: body.k }, { t: PROF, sc: ALU, id: 'aula1', o: slot.s, k: 'rem' });
  assert.equal(ag.validRemindSig(config(ENV), body), true);
});

test('sem QStash ou sem chaves VAPID o lembrete fica desligado, mas a agenda funciona', async () => {
  const H = mkHandlers({});
  await vincula(H);
  const r = await put(H, slotOf('aula1'));
  assert.equal(r.statusCode, 200);
  assert.equal(r.json().reminder, 'off');
  assert.equal(qstashCalls().length, 0);
  assert.equal((await callL(H, ALU, { action: 'push_key' })).json().enabled, false);
  assert.equal((await callL(H, ALU, { action: 'push_key' })).json().key, '');
});

test('aula daqui a mais de 6 dias: agenda um "acordar" e não passa do limite de atraso do QStash', async () => {
  const H = mkHandlers();
  await vincula(H);
  const slot = slotOf('longe', { s: NOW + 20 * 86400000 });
  await put(H, slot);
  const q = qstashCalls()[0];
  const body = JSON.parse(q.init.body);
  assert.equal(body.k, 'wake');
  const delay = Number(q.init.headers['Upstash-Not-Before']) * 1000 - NOW;
  assert.ok(delay <= 6 * 86400000 + 1000);
});

test('versão mais antiga não desfaz a mais nova; cancelar vira marca para o aluno e não agenda nada', async () => {
  const H = mkHandlers();
  await vincula(H);
  await put(H, slotOf('aula1', { u: NOW, n: 'nova' }));
  const velho = await put(H, slotOf('aula1', { u: NOW - 5000, n: 'velha' }));
  assert.equal(velho.json().stale, true);
  assert.equal((await callL(H, ALU, { action: 'sched' })).json().slots[0].n, 'nova');
  calls.length = 0;
  await put(H, slotOf('aula1', { u: NOW + 10, c: 1 }));
  const s = (await callL(H, ALU, { action: 'sched' })).json().slots[0];
  assert.equal(s.c, 1);
  assert.equal(qstashCalls().length, 0, 'aula cancelada não agenda lembrete');
});

test('entrada inválida ou exagerada é limpa ou recusada', async () => {
  const H = mkHandlers();
  await vincula(H);
  assert.equal((await put(H, { id: 'A B', s: NOW + 1000, u: NOW })).statusCode, 400);
  assert.equal((await put(H, { id: 'ok1', s: 5, u: NOW })).statusCode, 400);
  assert.equal((await put(H, { id: 'ok1', s: NOW + 1000, u: NOW + 10 * 86400000 })).statusCode, 400, 'versão no futuro');
  assert.equal((await put(H, 'lixo')).statusCode, 400);
  const r = await put(H, slotOf('ok2', { d: 99999, n: 'a'.repeat(500) + '‮', x: Array.from({ length: 80 }, (_, i) => i) }));
  assert.equal(r.statusCode, 200);
  const s = (await callL(H, ALU, { action: 'sched' })).json().slots[0];
  assert.equal(s.d, 240);
  assert.equal(s.n.length, 200);
  assert.equal(s.n.includes('‮'), false);
  assert.equal(s.x.length, 30);
});

test('notificações: inscrição válida, limite de 4 aparelhos e cancelar', async () => {
  const H = mkHandlers();
  await vincula(H);
  assert.equal((await callL(H, ALU, { action: 'push_sub', sub: { endpoint: 'http://ruim', keys: {} } })).statusCode, 400);
  for (let i = 1; i <= 5; i++) {
    NOW += 1000;
    assert.equal((await callL(H, ALU, { action: 'push_sub', sub: subscription('push.example.com', i) })).statusCode, 200);
  }
  assert.equal(hashes.get(`ps:${ALU}`).size, 4, 'só os 4 aparelhos mais novos');
  const s = subscription('push.example.com', 5);
  await callL(H, ALU, { action: 'push_unsub', endpoint: s.endpoint });
  assert.equal(hashes.get(`ps:${ALU}`).size, 3);
  assert.equal((await callL(H, ALU, { action: 'push_key' })).json().key, VAPID.publicKey);
});

// ---- O disparo do QStash ----
function remindMsg(overrides = {}) {
  const m = { t: PROF, sc: ALU, id: 'aula1', o: NOW + 15 * 60000, u: NOW, k: 'rem', ...overrides };
  m.sig = ag.remindSig(config(ENV), m);
  return m;
}
function qjwt(key = 'cur', claims = {}) {
  const h = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url');
  const c = Buffer.from(JSON.stringify({ iss: 'Upstash', exp: Math.floor(NOW / 1000) + 300, ...claims })).toString('base64url');
  const sig = crypto.createHmac('sha256', key).update(`${h}.${c}`).digest('base64url');
  return `${h}.${c}.${sig}`;
}
async function setupRemind(extra = {}) {
  const H = mkHandlers();
  await vincula(H);
  await callL(H, PROF, { action: 'push_sub', sub: subscription('push.teacher.example', 1) });
  await callL(H, ALU, { action: 'push_sub', sub: subscription('push.student.example', 1) });
  await put(H, slotOf('aula1', { s: NOW + 15 * 60000, w: 1, ...extra }));
  calls.length = 0;
  return H;
}
const fire = (H, m, jwt = qjwt()) => post(H.r, m, { 'upstash-signature': jwt });

test('disparo: avisa professor e aluno e agenda o lembrete da semana seguinte', async () => {
  const H = await setupRemind();
  const r = await fire(H, remindMsg());
  assert.equal(r.statusCode, 200);
  assert.equal(r.json().sent, 2);
  const pushes = calls.filter((c) => !c.url.startsWith('https://qstash'));
  assert.deepEqual(pushes.map((p) => new URL(p.url).host).sort(), ['push.student.example', 'push.teacher.example']);
  assert.equal(pushes[0].init.headers['Content-Encoding'], 'aes128gcm');
  assert.equal(pushes[0].init.headers.Urgency, 'high');
  assert.ok(pushes[0].init.headers.Authorization.startsWith('vapid t='));
  const q = qstashCalls();
  assert.equal(q.length, 1, 'agenda a próxima semana');
  assert.equal(JSON.parse(q[0].init.body).o, NOW + 15 * 60000 + 7 * 86400000);
});

test('disparo: mensagem falsificada, JWT errado ou vencido são recusados', async () => {
  const H = await setupRemind();
  assert.equal((await fire(H, { ...remindMsg(), sig: 'ff'.repeat(32) })).statusCode, 401);
  assert.equal((await fire(H, remindMsg(), qjwt('chave-errada'))).statusCode, 401);
  assert.equal((await fire(H, remindMsg(), qjwt('cur', { exp: 1 }))).statusCode, 401);
  assert.equal((await fire(H, { ...remindMsg(), o: NOW + 99 }, qjwt())).statusCode, 401, 'alterar um campo invalida a assinatura');
  assert.equal(calls.filter((c) => !c.url.startsWith('https://qstash')).length, 0, 'nada foi enviado');
  assert.equal((await fire(H, remindMsg(), qjwt('nxt'))).statusCode, 200, 'a chave seguinte também vale');
});

test('disparo repetido (QStash tentando de novo) não manda duas notificações', async () => {
  const H = await setupRemind();
  assert.equal((await fire(H, remindMsg())).json().sent, 2);
  const again = await fire(H, remindMsg());
  assert.equal(again.json().ignored, 'duplicada');
});

test('disparo velho é ignorado: aula mudada, dia cancelado, aula cancelada ou vínculo desfeito', async () => {
  let H = await setupRemind();
  assert.equal((await fire(H, remindMsg({ u: NOW - 1 }))).json().ignored, 'aula mudou');

  H = await setupRemind({ x: [NOW + 15 * 60000] });
  assert.equal((await fire(H, remindMsg())).json().ignored, 'dia cancelado');

  H = await setupRemind();
  await put(H, slotOf('aula1', { s: NOW + 15 * 60000, u: NOW + 5, c: 1 }));
  assert.equal((await fire(H, remindMsg({ u: NOW + 5 }))).json().ignored, 'aula mudou');

  H = await setupRemind();
  await callL(H, ALU, { action: 'unlink', role: 'student', other: PROF });
  assert.equal((await fire(H, remindMsg({ id: 'aula1' }))).json().ignored, 'vínculo desfeito');
  assert.equal(calls.filter((c) => !c.url.startsWith('https://qstash')).length, 0);
});

test('disparo atrasado (a aula já começou há mais de 5 min): não incomoda, mas agenda a próxima', async () => {
  const H = await setupRemind();
  const msg = remindMsg();
  NOW += 15 * 60000 + 10 * 60000; // 10 min depois do início
  const r = await fire(H, msg, qjwt('cur', { exp: Math.floor(NOW / 1000) + 300 }));
  assert.equal(r.json().sent, 0);
  assert.equal(qstashCalls().length, 1);
  NOW -= 25 * 60000;
});

test('inscrição que o navegador apagou (410) é limpa do servidor', async () => {
  const H = await setupRemind();
  pushStatus = 410;
  const r = await fire(H, remindMsg());
  assert.equal(r.json().sent, 0);
  assert.equal(hashes.get(`ps:${PROF}`).size, 0);
  assert.equal(hashes.get(`ps:${ALU}`).size, 0);
});

test('"acordar": reagenda mais perto da data sem enviar notificação', async () => {
  const H = mkHandlers();
  await vincula(H);
  await put(H, slotOf('longe', { s: NOW + 20 * 86400000 }));
  const wake = JSON.parse(qstashCalls()[0].init.body);
  calls.length = 0;
  NOW += 6 * 86400000;
  const r = await fire(H, wake, qjwt('cur', { exp: Math.floor(NOW / 1000) + 300 }));
  assert.equal(r.json().rescheduled, 'scheduled');
  assert.equal(calls.filter((c) => !c.url.startsWith('https://qstash')).length, 0);
  NOW -= 6 * 86400000;
});

test('sem QStash configurado, /api/remind responde 503 e não faz nada', async () => {
  const H = mkHandlers({});
  const r = await post(H.r, remindMsg());
  assert.equal(r.statusCode, 503);
});
