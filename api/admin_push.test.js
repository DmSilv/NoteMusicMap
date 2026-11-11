// Aviso de bug grave ao admin (Web Push), precisão dos bugs e busca por nome, sem rede:
// `node --test api/admin_push.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const errors = require('./errors');
const admin = require('./admin');
const link = require('./link');
const { config } = require('./_lib/config');
const { hashes, memory } = require('./_lib/store');
const { resetMem } = require('./_lib/store_cmd');
const { fingerprint } = require('./_lib/errors_lib');
const { generateVapidKeys } = require('./_lib/webpush');

const KEY = 'chave-de-admin-de-teste';
const HOUR = 3600000;
let NOW = 1_800_000_000_000;
let ipN = 0;
const VAPID = generateVapidKeys();
const sent = []; // envios de push capturados
let pushStatus = 201;

function fakeRes() {
  const r = { headers: {}, statusCode: 0, body: '' };
  r.setHeader = (k, v) => { r.headers[k] = v; };
  r.end = (b) => { r.body = b; };
  r.json = () => JSON.parse(r.body);
  return r;
}
function mk(env = {}) {
  hashes.clear();
  memory.clear();
  resetMem();
  sent.length = 0;
  pushStatus = 201;
  NOW = 1_800_000_000_000;
  const fetch = async (url) => { sent.push(url); return { status: pushStatus }; };
  const deps = {
    config: () => config({ ADMIN_KEY: KEY, VAPID_PUBLIC_KEY: VAPID.publicKey, VAPID_PRIVATE_KEY: VAPID.privateKey, ...env }),
    allowMemory: true, fetch, now: () => NOW,
  };
  return { e: errors.makeHandler(deps), a: admin.makeHandler(deps), l: link.makeHandler(deps) };
}
async function post(h, body, headers = {}) {
  const res = fakeRes();
  await h({ method: 'POST', headers: { 'x-forwarded-for': '4.4.4.' + ++ipN, ...headers }, body, socket: {} }, res);
  return res;
}
const dev = (n) => `dispositivo${String(n).padStart(8, '0')}`;
const report = (over = {}) => ({
  id: dev(1), c: 'APP-00', s: 'critical', w: 'Agenda › Marcar aula', d: 'StateError: quebrou\n#0 f',
  v: 'abc1234', pl: 'android-chrome', in: 'pwa', lk: 'online', vw: 'teacher', bc: ['Agenda'], ...over,
});
const rep = (H, over) => post(H.e, report(over));
const adm = (H, body) => post(H.a, body, { authorization: 'Bearer ' + KEY });

/** Inscrição de navegador de mentira, com chaves válidas. */
function fakeSub(n) {
  const ecdh = crypto.createECDH('prime256v1');
  ecdh.generateKeys();
  return {
    endpoint: `https://push.exemplo.test/envio/${n}-${'x'.repeat(20)}`,
    keys: { p256dh: ecdh.getPublicKey().toString('base64url'), auth: crypto.randomBytes(16).toString('base64url') },
  };
}
const subscribe = async (H, n = 1) => (await adm(H, { action: 'push', op: 'sub', sub: fakeSub(n) })).statusCode;

test('sem chaves VAPID o aviso fica indisponível e dizem o que falta', async () => {
  const H = mk({ VAPID_PUBLIC_KEY: '', VAPID_PRIVATE_KEY: '' });
  const st = (await adm(H, { action: 'push', op: 'status' })).json();
  assert.equal(st.enabled, false);
  assert.equal(st.key, '');
  const r = await adm(H, { action: 'push', op: 'sub', sub: fakeSub(1) });
  assert.equal(r.statusCode, 503);
  assert.match(r.json().message, /VAPID/);
  assert.equal((await rep(H)).statusCode, 200); // o relatório do app nunca é afetado
});

test('inscrever, listar, remover e limite de 5 aparelhos', async () => {
  const H = mk();
  assert.equal((await adm(H, { action: 'push', op: 'status' })).json().key, VAPID.publicKey);
  assert.equal((await adm(H, { action: 'push', op: 'sub', sub: { endpoint: 'http://inseguro', keys: {} } })).statusCode, 400);
  for (let i = 1; i <= 6; i++) { NOW += 1000; assert.equal(await subscribe(H, i), 200); }
  assert.equal((await adm(H, { action: 'push', op: 'status' })).json().devices, 5); // o mais antigo saiu
  const s7 = fakeSub(7);
  await adm(H, { action: 'push', op: 'sub', sub: s7 });
  assert.equal((await adm(H, { action: 'push', op: 'unsub', endpoint: s7.endpoint })).statusCode, 200);
  assert.equal((await adm(H, { action: 'push', op: 'status' })).json().devices, 4); // o 7º entrou (tirando o mais antigo) e saiu
});

test('bug grave NOVO avisa o admin; repetição e bug comum não avisam', async () => {
  const H = mk();
  await subscribe(H, 1);
  await subscribe(H, 2);
  await rep(H, { s: 'action', d: 'StateError: comum' });
  assert.equal(sent.length, 0); // gravidade comum: silêncio
  await rep(H);
  assert.equal(sent.length, 2); // 1 por aparelho do admin
  await rep(H); // o mesmo bug de novo
  await rep(H, { id: dev(2) });
  assert.equal(sent.length, 2);
  await rep(H, { d: 'StateError: outro erro grave' }); // outro bug grave
  assert.equal(sent.length, 4);
});

test('bug grave resolvido que volta numa versão nova avisa como reaberto', async () => {
  const H = mk();
  await subscribe(H, 1);
  const first = await rep(H);
  const fp = (await adm(H, { action: 'bugs' })).json().items[0].fp;
  assert.equal(first.statusCode, 200);
  await adm(H, { action: 'bug_status', fp, status: 'resolved' });
  sent.length = 0;
  NOW += 3 * HOUR;
  await rep(H, { v: 'novaversao1' }); // versão publicada depois da correção
  assert.equal(sent.length, 1);
});

test('no máximo 6 avisos por hora e inscrição morta (410) é apagada', async () => {
  const H = mk();
  await subscribe(H, 1);
  for (let i = 0; i < 9; i++) await rep(H, { d: `Erro grave diferente ${String.fromCharCode(97 + i)}${'z'.repeat(i + 1)}` });
  assert.equal(sent.length, 6);
  NOW += 2 * HOUR; // outra hora: volta a avisar
  pushStatus = 410;
  await rep(H, { d: 'Erro grave de outra hora' });
  assert.equal((await adm(H, { action: 'push', op: 'status' })).json().devices, 0); // o servidor de push disse "não existe mais"
});

test('falha no envio nunca derruba o relatório do app', async () => {
  const H = mk();
  await subscribe(H, 1);
  pushStatus = 500;
  const r = await rep(H);
  assert.equal(r.statusCode, 200);
  assert.equal(r.json().status, 'new');
});

test('envio de teste respeita o limite', async () => {
  const H = mk();
  await subscribe(H, 1);
  const t = (await adm(H, { action: 'push', op: 'test' })).json();
  assert.equal(t.sent, 1);
  for (let i = 0; i < 4; i++) await adm(H, { action: 'push', op: 'test' });
  assert.equal((await adm(H, { action: 'push', op: 'test' })).statusCode, 429);
});

test('só o admin mexe nos avisos', async () => {
  const H = mk();
  const res = await post(H.a, { action: 'push', op: 'status' }, { authorization: 'Bearer errada' });
  assert.equal(res.statusCode, 401);
});

test('o mesmo bug com números diferentes na mensagem tem a mesma impressão digital', () => {
  assert.equal(fingerprint('APP-00', 'Agenda', 'RangeError: índice 3 fora de 10'), fingerprint('APP-00', 'Agenda', 'RangeError: índice 4 fora de 12'));
  assert.equal(fingerprint('APP-00', 'Agenda', 'Erro em 0x7ffd1234 no objeto'), fingerprint('APP-00', 'Agenda', 'Erro em 0x1a2b no objeto'));
  assert.notEqual(fingerprint('APP-00', 'Agenda', 'RangeError: índice'), fingerprint('APP-00', 'Agenda', 'StateError: índice'));
  assert.notEqual(fingerprint('APP-00', 'Agenda', 'x'), fingerprint('APP-01', 'Agenda', 'x'));
});

test('bugs: sabe quais ainda acontecem na versão publicada agora e filtra por ela', async () => {
  const H = mk({ VERCEL_GIT_COMMIT_SHA: 'abc1234deadbeef' });
  await rep(H, { s: 'action', d: 'Erro só na versão velha', v: 'velha00' });
  await rep(H, { s: 'action', d: 'Erro que continua', v: 'abc1234' });
  const all = (await adm(H, { action: 'bugs' })).json();
  assert.equal(all.current, 'abc1234');
  assert.equal(all.items.length, 2);
  assert.deepEqual(all.items.map((x) => x.onCurrent).sort(), [false, true]);
  const cur = (await adm(H, { action: 'bugs', cur: true })).json();
  assert.equal(cur.items.length, 1);
  assert.match(cur.items[0].msg, /continua/);
});

test('busca de perfis pelo apelido, só entre os 100 mais recentes', async () => {
  const H = mk();
  const A = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  const code = (seed) => { let p = ''; let x = seed; for (let i = 0; i < 7; i++) { p += A[x % 32]; x = Math.floor(x / 32) + 7 + i; } let s = 0; for (let i = 0; i < 7; i++) s += A.indexOf(p[i]) * (2 * i + 1); const c = p + A[s % 32]; return `${c.slice(0, 4)}-${c.slice(4)}`; };
  const sec = (c) => crypto.createHash('sha256').update('s' + c).digest('hex');
  for (const [seed, nome] of [[11111, 'Maria Souza'], [22222, 'João Lima'], [33333, 'Mariana']]) {
    await post(H.l, { code: code(seed), secret: sec(code(seed)), action: 'sync', name: nome });
  }
  const r = (await adm(H, { action: 'list', q: 'mari', by: 'name' })).json();
  assert.equal(r.total, 2);
  assert.equal(r.scanned, 100);
  assert.deepEqual(r.items.map((x) => x.name).sort(), ['Maria Souza', 'Mariana']);
  assert.equal((await adm(H, { action: 'list', q: 'zzzz', by: 'name' })).json().total, 0);
  assert.equal((await adm(H, { action: 'list', q: 'JOÃO', by: 'name' })).json().total, 1); // maiúsculas e acento do JS
});
