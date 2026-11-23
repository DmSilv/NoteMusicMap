// Pagamentos no painel do administrador (receita, lista, reembolso, importar), sem rede: `node --test api/admin_pay.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const link = require('./link');
const account = require('./account');
const admin = require('./admin');
const pay = require('./_lib/pay');
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
const P1 = code(11111);
const S1 = 'a'.repeat(64);
const KEY = 'chave-de-admin-de-teste';
const SUPPORT = 'chave-de-suporte-de-teste';
const SECRET = 'segredo-mp';
const ON = { enabled: true, token: 'APP_USR-x', secret: SECRET, publicUrl: 'https://exemplo.test', testCodes: [], gate: false };
const DAY = pay.DAY;

let NOW = Date.UTC(2026, 10, 24, 15, 0, 0);
let ipN = 0;
let mpSeq = 0;
let mpPay;
let refunds;

function mk() {
  hashes.clear(); memory.clear(); resetMem();
  NOW = Date.UTC(2026, 10, 24, 15, 0, 0);
  mpSeq = 0; refunds = 0;
  mpPay = null;
  const fetch = async (url, init) => {
    if (String(url).endsWith('/v1/payments') && init.method === 'POST') {
      const body = JSON.parse(init.body);
      mpPay = { id: 800000100 + mpSeq++, status: 'pending', transaction_amount: body.transaction_amount, external_reference: body.external_reference, payment_method_id: 'pix', transaction_details: { net_received_amount: Math.round(body.transaction_amount * 0.9901 * 100) / 100 } };
      return { ok: true, json: async () => ({ ...mpPay, point_of_interaction: { transaction_data: { qr_code: 'x', qr_code_base64: 'QQ==' } } }) };
    }
    if (String(url).endsWith('/refunds')) { refunds++; return { ok: true, json: async () => ({ id: 1 }) }; }
    if (String(url).includes('/v1/payments/')) {
      const id = Number(String(url).split('/').pop());
      return { ok: true, json: async () => (mpPay && Number(mpPay.id) === id ? { ...mpPay } : { id, status: 'approved', transaction_amount: 14.9, external_reference: `${P1}|m`, payment_method_id: 'pix', transaction_details: { net_received_amount: 14.75 } }) };
    }
    throw new Error('sem rede');
  };
  const deps = { config: () => config({ ADMIN_KEY: KEY, SUPPORT_KEY: SUPPORT }), allowMemory: true, fetch, now: () => NOW, pay: ON };
  return { l: link.makeHandler(deps), a: account.makeHandler(deps), adm: admin.makeHandler(deps) };
}
function fakeRes() {
  const r = { headers: {}, statusCode: 0, body: '' };
  r.setHeader = (k, v) => { r.headers[k] = v; };
  r.end = (b) => { r.body = b; };
  r.json = () => JSON.parse(r.body);
  return r;
}
async function acc(H, body, extra = {}) {
  const res = fakeRes();
  await H.a({ method: 'POST', headers: { 'x-forwarded-for': '9.9.9.' + ++ipN, ...(extra.headers || {}) }, body, query: extra.query, socket: {} }, res);
  return res;
}
async function admin_(H, body, key = KEY) {
  const res = fakeRes();
  await H.adm({ method: 'POST', headers: { 'x-forwarded-for': '5.5.5.' + ++ipN, authorization: 'Bearer ' + key }, body, socket: {} }, res);
  return res;
}
const sig = (dataId, requestId) => {
  const ts = '1700000000';
  return `ts=${ts},v1=${crypto.createHmac('sha256', SECRET).update(`id:${dataId};request-id:${requestId};ts:${ts};`).digest('hex')}`;
};
const hook = (H, id) => acc(H, {}, { query: { mp: 'hook', 'data.id': String(id) }, headers: { 'x-signature': sig(id, 'r1'), 'x-request-id': 'r1' } });
async function buy(H, period = 'm') {
  const j = (await acc(H, { action: 'pay_new', code: P1, secret: S1, period })).json();
  mpPay.status = 'approved';
  await hook(H, j.id);
  return j.id;
}

test('painel: lista os pagamentos e soma bruto, taxa e líquido', async () => {
  const H = mk();
  await acc(H, { action: 'plan', code: P1, secret: S1 }); // o perfil precisa existir
  await H.l({ method: 'POST', headers: { 'x-forwarded-for': '1.1.1.1' }, body: { action: 'sync', code: P1, secret: S1 }, socket: {} }, fakeRes());
  await buy(H, 'm');
  NOW += DAY;
  await buy(H, 'y');
  const r = (await admin_(H, { action: 'pay_overview' })).json();
  assert.equal(r.ok, true);
  assert.equal(r.enabled, true);
  assert.equal(r.items.length, 2);
  assert.equal(r.summary.all.count, 2);
  assert.equal(r.summary.all.gross, 163.9);
  assert.equal(r.summary.all.net, 162.27);
  assert.equal(r.summary.all.fee, 1.63);
  assert.equal(r.items[0].plan, 'y', 'o mais novo primeiro');
});

test('painel: o plano de teste não entra na receita', async () => {
  const H = mk();
  await H.l({ method: 'POST', headers: { 'x-forwarded-for': '1.1.1.2' }, body: { action: 'sync', code: P1, secret: S1 }, socket: {} }, fakeRes());
  const T = { ...ON, testCodes: [P1] };
  const deps = { config: () => config({ ADMIN_KEY: KEY }), allowMemory: true, fetch: undefined, now: () => NOW, pay: T };
  assert.ok(deps);
  const ledger = require('./_lib/pay_ledger');
  const sm = ledger.summarize([{ id: '1', amount: 1, net: 0.99, fee: 0.01, paid: NOW, status: 'approved', plan: 't' }].filter((x) => x.plan !== 't'), NOW);
  assert.equal(sm.all.count, 0);
});

test('painel: reembolsa a qualquer hora e tira o Pro; a chave de suporte não pode', async () => {
  const H = mk();
  await H.l({ method: 'POST', headers: { 'x-forwarded-for': '1.1.1.3' }, body: { action: 'sync', code: P1, secret: S1 }, socket: {} }, fakeRes());
  const id = await buy(H, 'm');
  NOW += 30 * DAY; // fora dos 7 dias do professor
  assert.equal((await acc(H, { action: 'pay_refund', code: P1, secret: S1, id })).json().error, 'too_late');
  assert.equal((await admin_(H, { action: 'pay_refund', id }, SUPPORT)).statusCode, 403, 'suporte não reembolsa');
  assert.equal((await admin_(H, { action: 'pay_overview' }, SUPPORT)).statusCode, 403, 'suporte não vê a receita');
  const r = await admin_(H, { action: 'pay_refund', id });
  assert.equal(r.statusCode, 200);
  assert.equal(refunds, 1);
  assert.equal((await admin_(H, { action: 'pay_refund', id })).statusCode, 409, 'não reembolsa duas vezes');
  const ov = (await admin_(H, { action: 'pay_overview' })).json();
  assert.equal(ov.summary.refundedCount, 1);
  assert.equal(ov.summary.all.count, 0, 'reembolsado sai da receita');
});

test('painel: importar um pagamento antigo para o livro, sem somar o Pro de novo', async () => {
  const H = mk();
  await H.l({ method: 'POST', headers: { 'x-forwarded-for': '1.1.1.4' }, body: { action: 'sync', code: P1, secret: S1 }, socket: {} }, fakeRes());
  const r = await admin_(H, { action: 'pay_import', id: '190146930531' });
  assert.equal(r.statusCode, 200);
  assert.equal((await admin_(H, { action: 'pay_import', id: '190146930531' })).statusCode, 409, 'já está no livro');
  const ov = (await admin_(H, { action: 'pay_overview' })).json();
  assert.equal(ov.items.length, 1);
  assert.equal(ov.summary.all.count, 1);
  assert.equal((await acc(H, { action: 'plan', code: P1, secret: S1 })).json().pro, false, 'importar não libera o Pro');
});
