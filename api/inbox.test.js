// Testes da conversa particular admin x usuário e do rótulo de feedback no boletim, sem rede:
// `node --test api/inbox.test.js`
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
const PROF = code(11111), ALU = code(22222), OUTRO = code(44444);
const secret = (c, extra = '') => crypto.createHash('sha256').update('s' + c + extra).digest('hex');
const KEY = 'chave-de-admin-de-teste';
const HOUR = 3600000;

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
async function as(H, who, body, sec = secret(who)) {
  const res = fakeRes();
  await H.l({ method: 'POST', headers: { 'x-forwarded-for': '6.6.6.' + ++ipN }, body: { code: who, secret: sec, ...body }, socket: {} }, res);
  return res;
}
async function adm(H, body) {
  const res = fakeRes();
  await H.a({ method: 'POST', headers: { 'x-forwarded-for': '5.5.5.' + ++ipN, authorization: 'Bearer ' + KEY }, body, socket: {} }, res);
  return res;
}

const sync = async (H, c) => (await as(H, c, { action: 'sync', name: 'Ana' })).json();

test('mensagem do admin chega só ao destinatário, com a flag cr (sem comando extra)', async () => {
  const H = mk();
  await sync(H, ALU); await sync(H, OUTRO);
  assert.equal((await sync(H, ALU)).cr, undefined);
  const r = await adm(H, { action: 'inbox_send', code: ALU, x: 'Oi! Vi a sua sugestão.\x00' });
  assert.equal(r.statusCode, 200);
  NOW += 1000;
  assert.equal((await sync(H, ALU)).cr, NOW - 1000);
  assert.equal((await sync(H, OUTRO)).cr, undefined);
  const mine = (await as(H, ALU, { action: 'msg_get' })).json();
  assert.equal(mine.m.length, 1);
  assert.equal(mine.m[0].f, 'a');
  assert.equal(mine.m[0].x.includes('\x00'), false);
  assert.deepEqual((await as(H, OUTRO, { action: 'msg_get' })).json().m, []);
});

test('usuário só responde depois do admin, com limite de sequência e por hora', async () => {
  const H = mk();
  await sync(H, ALU);
  assert.equal((await as(H, ALU, { action: 'msg_put', x: 'oi' })).statusCode, 409); // não inicia conversa
  await adm(H, { action: 'inbox_send', code: ALU, x: 'Olá' });
  for (let i = 0; i < 3; i++) assert.equal((await as(H, ALU, { action: 'msg_put', x: 'resp ' + i })).statusCode, 200);
  assert.equal((await as(H, ALU, { action: 'msg_put', x: 'mais uma' })).statusCode, 409); // 3 seguidas
  const long = (await adm(H, { action: 'inbox_send', code: ALU, x: 'x'.repeat(900) })).json();
  assert.equal(long.m[long.m.length - 1].x.length, 600);
  const r = (await as(H, ALU, { action: 'msg_put', x: 'y'.repeat(500) })).json();
  assert.equal(r.m[r.m.length - 1].x.length, 280);
});

test('caixa de entrada: não lidas primeiro, histórico, resolver e apagar', async () => {
  const H = mk();
  await sync(H, ALU); await sync(H, OUTRO);
  await adm(H, { action: 'inbox_send', code: OUTRO, x: 'Para o outro' });
  NOW += 1000;
  await adm(H, { action: 'inbox_send', code: ALU, x: 'Para a Ana', ref: 'Queria mais escalas' });
  await as(H, OUTRO, { action: 'msg_put', x: 'Obrigado!' });
  let l = (await adm(H, { action: 'inbox_list' })).json();
  assert.equal(l.unread, 1);
  assert.equal(l.items[0].code, OUTRO);
  assert.equal(l.items[0].name, 'Ana');
  const t = (await adm(H, { action: 'inbox_thread', code: OUTRO })).json();
  assert.equal(t.m.length, 2);
  l = (await adm(H, { action: 'inbox_list' })).json();
  assert.equal(l.unread, 0);
  assert.equal((await adm(H, { action: 'inbox_resolve', code: OUTRO })).statusCode, 200);
  l = (await adm(H, { action: 'inbox_list' })).json();
  assert.equal(l.items.find((x) => x.code === OUTRO).s, 'done');
  assert.equal((await adm(H, { action: 'inbox_delete', code: OUTRO })).statusCode, 200);
  assert.equal((await adm(H, { action: 'inbox_list' })).json().items.length, 1);
  assert.equal((await adm(H, { action: 'inbox_send', code: code(99999), x: 'oi' })).statusCode, 404);
});

test('limite diário de mensagens do admin para o mesmo perfil', async () => {
  const H = mk();
  await sync(H, ALU);
  for (let i = 0; i < 10; i++) assert.equal((await adm(H, { action: 'inbox_send', code: ALU, x: 'm' + i })).statusCode, 200);
  assert.equal((await adm(H, { action: 'inbox_send', code: ALU, x: 'm' })).statusCode, 429);
});

test('crédito no boletim só com aceite; sem aceite não sai o apelido', async () => {
  const H = mk();
  await sync(H, ALU);
  const n = (await adm(H, { action: 'news_save', t: 'Mais escalas', b: 'Veio de uma sugestão.', fb: 'idea' })).json();
  assert.equal(n.item.fb, 'idea');
  assert.equal((await adm(H, { action: 'news_save', id: n.id, t: 'Mais escalas', b: 'Veio de uma sugestão.', fb: 'idea', fbc: ALU })).statusCode, 409);
  await adm(H, { action: 'inbox_send', code: ALU, x: 'Posso citar seu apelido?', ask: true });
  assert.equal((await as(H, ALU, { action: 'msg_get' })).json().askOpen, true);
  assert.equal((await as(H, ALU, { action: 'msg_ok', yes: true })).json().askOpen, false);
  const ok = await adm(H, { action: 'news_save', id: n.id, t: 'Mais escalas', b: 'Veio de uma sugestão.', fb: 'idea', fbc: ALU });
  assert.equal(ok.statusCode, 200);
  assert.equal(ok.json().item.fn, 'Ana');
  await adm(H, { action: 'news_state', id: n.id, st: 'live' });
  const pub = require('./_lib/news').publicItems((await adm(H, { action: 'news_list' })).json().items);
  assert.equal(pub[0].fb, 'idea');
  assert.equal(pub[0].fn, 'Ana');
  // recusa: tirar o crédito volta a "um usuário"
  const off = await adm(H, { action: 'news_save', id: n.id, t: 'Mais escalas', b: 'Veio de uma sugestão.', fb: 'idea', fbc: '' });
  assert.equal(off.json().item.fn, '');
  // painel antigo (sem fb) não apaga o rótulo
  const old = await adm(H, { action: 'news_save', id: n.id, t: 'Mais escalas 2', b: 'Texto.' });
  assert.equal(old.json().item.fb, 'idea');
});

test('recusar o crédito (msg_ok no) impede o apelido', async () => {
  const H = mk();
  await sync(H, ALU);
  const n = (await adm(H, { action: 'news_save', t: 'Correção', b: 'Texto.', fb: 'fix' })).json();
  await adm(H, { action: 'inbox_send', code: ALU, x: 'Posso citar?', ask: true });
  await as(H, ALU, { action: 'msg_ok', yes: false });
  assert.equal((await adm(H, { action: 'news_save', id: n.id, t: 'Correção', b: 'Texto.', fb: 'fix', fbc: ALU })).statusCode, 409);
});

test('apagar o perfil apaga a conversa', async () => {
  const H = mk();
  await sync(H, ALU);
  await adm(H, { action: 'inbox_send', code: ALU, x: 'oi' });
  assert.equal((await adm(H, { action: 'delete', code: ALU, confirm: ALU })).statusCode, 200);
  assert.equal((await adm(H, { action: 'inbox_list' })).json().items.length, 0);
});

test('pedido de suporte: o usuário envia, o admin vê e decide abrir conversa ou fechar', async () => {
  const H = mk();
  await sync(H, ALU); await sync(H, OUTRO);
  assert.equal((await as(H, ALU, { action: 'rq_put', x: 'ab' })).statusCode, 409, 'curto demais');
  const ok = await as(H, ALU, { action: 'rq_put', x: 'A agenda não abre depois de trocar de celular', v: 'abc1234', p: 'android' });
  assert.equal(ok.statusCode, 200);
  await as(H, OUTRO, { action: 'rq_put', x: 'Não consigo entrar com a chave' });
  let l = (await adm(H, { action: 'rq_list' })).json();
  assert.equal(l.total, 2);
  assert.equal(l.items.find((i) => i.code === ALU).v, 'abc1234');
  // não virou conversa: o usuário ainda não pode responder
  assert.equal((await as(H, ALU, { action: 'msg_put', x: 'oi' })).statusCode, 409);
  assert.equal((await adm(H, { action: 'inbox_list' })).json().total, 0);
  // fechar tira da fila sem criar conversa
  assert.equal((await adm(H, { action: 'rq_close', code: OUTRO })).statusCode, 200);
  assert.equal((await adm(H, { action: 'rq_list' })).json().total, 1);
  assert.equal((await adm(H, { action: 'inbox_list' })).json().total, 0);
  // abrir conversa escreve primeiro e tira o pedido
  assert.equal((await adm(H, { action: 'rq_open', code: ALU, x: 'Vou olhar. Qual celular?' })).statusCode, 200);
  assert.equal((await adm(H, { action: 'rq_list' })).json().total, 0);
  const th = (await adm(H, { action: 'inbox_thread', code: ALU })).json();
  assert.equal(th.m[0].f, 'a');
  assert.match(th.m[0].ref, /agenda não abre/);
  assert.equal((await as(H, ALU, { action: 'msg_put', x: 'Samsung' })).statusCode, 200);
});

test('pedido de suporte: limite por dia e só admin lê', async () => {
  const H = mk();
  await sync(H, ALU);
  for (let i = 0; i < 3; i++) assert.equal((await as(H, ALU, { action: 'rq_put', x: 'Relato número ' + i + ' do problema' })).statusCode, 200);
  assert.equal((await as(H, ALU, { action: 'rq_put', x: 'Relato número 4 do problema' })).statusCode, 429);
  assert.equal((await adm(H, { action: 'rq_list' })).json().total, 1, 'o mais novo substitui o anterior');
  const sem = fakeRes();
  await H.a({ method: 'POST', headers: { 'x-forwarded-for': '9.9.9.9', authorization: 'Bearer errada' }, body: { action: 'rq_list' }, socket: {} }, sem);
  assert.equal(sem.statusCode, 401);
});
