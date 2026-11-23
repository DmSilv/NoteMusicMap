// Testes do plano Pro por Pix (Mercado Pago simulado, sem rede nem credenciais): `node --test api/pay.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const account = require('./account');
const link = require('./link');
const pay = require('./_lib/pay');
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
const P1 = code(11111), P2 = code(22222);
const S1 = 'a'.repeat(64), S2 = 'b'.repeat(64);
const SECRET = 'segredo-de-teste';
const ON = { enabled: true, token: 'APP_USR-teste', secret: SECRET, publicUrl: 'https://exemplo.test' };

let NOW = Date.UTC(2026, 10, 24, 15, 0, 0);
let ipN = 0;
let mpPay; // pagamento simulado no "Mercado Pago"
let mpCalls;
let mpSeq = 0;
let refundFail = false; // simula o Mercado Pago recusando o reembolso

function mk(pcfg = ON) {
  hashes.clear();
  memory.clear();
  resetMem();
  NOW = Date.UTC(2026, 10, 24, 15, 0, 0);
  mpCalls = [];
  mpSeq = 0;
  refundFail = false;
  mpPay = { id: 987654321, status: 'pending', transaction_amount: 14.9, external_reference: '', payment_method_id: 'pix' };
  const fetch = async (url, init) => {
    mpCalls.push({ url: String(url), method: init && init.method, headers: init && init.headers, body: init && init.body ? JSON.parse(init.body) : null });
    if (String(url).endsWith('/v1/payments') && init.method === 'POST') {
      const body = JSON.parse(init.body);
      mpPay = { id: 987654321 + mpSeq++, status: 'pending', transaction_amount: body.transaction_amount, external_reference: body.external_reference, payment_method_id: 'pix', transaction_details: { net_received_amount: Math.round(body.transaction_amount * 0.9901 * 100) / 100 } };
      return { ok: true, json: async () => ({ ...mpPay, date_of_expiration: body.date_of_expiration, point_of_interaction: { transaction_data: { qr_code: '000201PIXCOPIAECOLA', qr_code_base64: 'QUJD', ticket_url: 'https://mp.test/t' } } }) };
    }
    if (String(url).endsWith('/refunds')) {
      if (refundFail) return { ok: false, status: 500, json: async () => ({ message: 'erro' }) };
      return { ok: true, json: async () => ({ id: 1, status: 'approved' }) };
    }
    if (String(url).includes('/v1/payments/')) return { ok: true, json: async () => ({ ...mpPay }) };
    throw new Error('sem rede');
  };
  const deps = { config: () => config({}), allowMemory: true, fetch, now: () => NOW, pay: pcfg };
  return { a: account.makeHandler(deps), l: link.makeHandler(deps) };
}
function fakeRes() {
  const r = { headers: {}, statusCode: 0, body: '' };
  r.setHeader = (k, v) => { r.headers[k] = v; };
  r.end = (b) => { r.body = b; };
  r.json = () => JSON.parse(r.body);
  return r;
}
async function call(h, body, extra = {}) {
  const res = fakeRes();
  await h({ method: 'POST', headers: { 'x-forwarded-for': '9.9.9.' + ++ipN, ...(extra.headers || {}) }, body, query: extra.query, socket: {} }, res);
  return res;
}
const born = (H, c, s) => call(H.l, { action: 'sync', code: c, secret: s });
const sig = (dataId, requestId, ts = '1700000000', secret = SECRET) => {
  const manifest = `id:${dataId};request-id:${requestId};ts:${ts};`;
  return `ts=${ts},v1=${crypto.createHmac('sha256', secret).update(manifest).digest('hex')}`;
};
const hook = (H, dataId, { sign = true, requestId = 'req-1', secret } = {}) =>
  call(H.a, {}, { query: { mp: 'hook', 'data.id': String(dataId) }, headers: sign ? { 'x-signature': sig(dataId, requestId, '1700000000', secret), 'x-request-id': requestId } : {} });

test('regras: planos, período e "Pro até" somam sem perder dias', () => {
  assert.equal(pay.PLANS.m.amount, 14.9);
  assert.equal(pay.PLANS.y.amount, 149);
  assert.equal(pay.FREE_STUDENTS, 3);
  const d = Date.UTC(2026, 10, 24);
  assert.equal(pay.extendUntil(0, pay.PLANS.m, d), d + 30 * pay.DAY);
  assert.equal(pay.extendUntil(d + 10 * pay.DAY, pay.PLANS.y, d), d + 375 * pay.DAY, 'renovar antes de vencer soma ao que sobrou');
  assert.equal(pay.extendUntil(d - 5 * pay.DAY, pay.PLANS.m, d), d + 30 * pay.DAY, 'vencido: conta a partir de hoje');
  assert.deepEqual(pay.statusOf(d + 3 * pay.DAY, d), { pro: true, until: d + 3 * pay.DAY, daysLeft: 3 });
  assert.equal(pay.statusOf(d - 1, d).pro, false);
});

test('assinatura do aviso: confere HMAC, rejeita a errada e a de outro segredo', () => {
  const ok = { signature: sig('123456', 'r1'), requestId: 'r1', dataId: '123456', secret: SECRET };
  assert.equal(pay.verifySignature(ok), true);
  assert.equal(pay.verifySignature({ ...ok, dataId: '123457' }), false, 'id trocado');
  assert.equal(pay.verifySignature({ ...ok, requestId: 'r2' }), false, 'request-id trocado');
  assert.equal(pay.verifySignature({ ...ok, secret: 'outro' }), false);
  assert.equal(pay.verifySignature({ ...ok, signature: undefined }), false);
  assert.equal(pay.verifySignature({ ...ok, signature: 'ts=1,v1=zz' }), false);
  assert.equal(pay.verifySignature({ ...ok, secret: '' }), false, 'sem segredo nunca vale');
});

test('desligado: o plano diz enabled false e criar Pix dá 503 sem falar com o Mercado Pago', async () => {
  const H = mk({ enabled: false, token: '', secret: '', publicUrl: '' });
  await born(H, P1, S1);
  const st = (await call(H.a, { action: 'plan', code: P1, secret: S1 })).json();
  assert.equal(st.ok, true);
  assert.equal(st.enabled, false);
  assert.equal(st.pro, false);
  assert.equal(st.free, 3);
  assert.equal((await call(H.a, { action: 'pay_new', code: P1, secret: S1, period: 'm' })).statusCode, 503);
  assert.equal(mpCalls.length, 0);
});

test('ligado sem credenciais: continua desligado', async () => {
  const H = mk({ enabled: true, token: '', secret: SECRET, publicUrl: '' });
  await born(H, P1, S1);
  assert.equal((await call(H.a, { action: 'plan', code: P1, secret: S1 })).json().enabled, false);
  assert.equal((await call(H.a, { action: 'pay_new', code: P1, secret: S1, period: 'm' })).statusCode, 503);
});

test('pay_new: gera o Pix com o valor certo, referência do perfil e chave de idempotência', async () => {
  const H = mk();
  await born(H, P1, S1);
  const r = await call(H.a, { action: 'pay_new', code: P1, secret: S1, period: 'y' });
  assert.equal(r.statusCode, 200);
  const j = r.json();
  assert.equal(j.ok, true);
  assert.equal(j.amount, 149);
  assert.equal(j.qr, '000201PIXCOPIAECOLA');
  const c = mpCalls.find((x) => x.method === 'POST');
  assert.equal(c.body.transaction_amount, 149);
  assert.equal(c.body.payment_method_id, 'pix');
  assert.equal(c.body.external_reference, `${P1}|y`);
  assert.equal(c.body.notification_url, 'https://exemplo.test/api/account?mp=hook');
  assert.match(c.headers['X-Idempotency-Key'], /^[0-9a-f]{40}$/);
  assert.match(c.headers.Authorization, /^Bearer /);
  assert.equal((await call(H.a, { action: 'pay_new', code: P1, secret: S1, period: 'x' })).statusCode, 400, 'plano que não existe');
});

test('plano de teste (R$ 1): escondido da lista e só vale para os perfis de PAY_TEST_CODES', async () => {
  const H = mk({ ...ON, testCodes: [P1] });
  await born(H, P1, S1);
  await born(H, P2, S2);
  const st = (await call(H.a, { action: 'plan', code: P1, secret: S1 })).json();
  assert.deepEqual(st.plans.map((p) => p.id), ['m', 'y'], 'o plano de teste nunca aparece na lista');
  assert.equal(st.test, true, 'o servidor diz que este perfil pode testar');
  assert.equal((await call(H.a, { action: 'plan', code: P2, secret: S2 })).json().test, false, 'o outro não');
  assert.equal((await call(H.a, { action: 'pay_new', code: P2, secret: S2, period: 't' })).statusCode, 400, 'outro perfil não compra o teste');
  const r = await call(H.a, { action: 'pay_new', code: P1, secret: S1, period: 't' });
  assert.equal(r.statusCode, 200);
  assert.equal(r.json().amount, 1);
  mpPay.status = 'approved';
  await hook(H, r.json().id);
  const a = (await call(H.a, { action: 'plan', code: P1, secret: S1 })).json();
  assert.equal(a.until, NOW + pay.DAY, 'o teste soma 1 dia');
  const none = mk({ ...ON, testCodes: [] });
  await born(none, P1, S1);
  assert.equal((await call(none.a, { action: 'pay_new', code: P1, secret: S1, period: 't' })).statusCode, 400, 'sem PAY_TEST_CODES ninguém compra o teste');
});

test('pay_new exige o dono do perfil (segredo certo)', async () => {
  const H = mk();
  await born(H, P1, S1);
  assert.notEqual((await call(H.a, { action: 'pay_new', code: P1, secret: S2, period: 'm' })).statusCode, 200);
  assert.equal(mpCalls.length, 0);
});

test('aviso aprovado soma o período UMA vez, mesmo repetido', async () => {
  const H = mk();
  await born(H, P1, S1);
  const j = (await call(H.a, { action: 'pay_new', code: P1, secret: S1, period: 'm' })).json();
  mpPay.status = 'approved';
  assert.equal((await hook(H, j.id)).statusCode, 200);
  const a = (await call(H.a, { action: 'plan', code: P1, secret: S1 })).json();
  assert.equal(a.pro, true);
  assert.equal(a.until, NOW + 30 * pay.DAY);
  assert.equal(a.daysLeft, 30);
  await hook(H, j.id);
  await hook(H, j.id, { requestId: 'req-2' });
  assert.equal((await call(H.a, { action: 'plan', code: P1, secret: S1 })).json().until, NOW + 30 * pay.DAY, 'avisos repetidos não somam de novo');
});

test('aviso sem assinatura, com assinatura de outro segredo ou ligado ao Pix errado: não libera nada', async () => {
  const H = mk();
  await born(H, P1, S1);
  const j = (await call(H.a, { action: 'pay_new', code: P1, secret: S1, period: 'm' })).json();
  mpPay.status = 'approved';
  assert.equal((await hook(H, j.id, { sign: false })).statusCode, 401);
  assert.equal((await hook(H, j.id, { secret: 'outro-segredo' })).statusCode, 401);
  assert.equal((await call(H.a, { action: 'plan', code: P1, secret: S1 })).json().pro, false);
  // pagamento aprovado, mas de valor diferente do plano: não libera
  mpPay.transaction_amount = 1;
  await hook(H, j.id);
  assert.equal((await call(H.a, { action: 'plan', code: P1, secret: S1 })).json().pro, false);
});

test('aviso pendente ou rejeitado não libera', async () => {
  const H = mk();
  await born(H, P1, S1);
  const j = (await call(H.a, { action: 'pay_new', code: P1, secret: S1, period: 'm' })).json();
  for (const s of ['pending', 'rejected', 'cancelled']) {
    mpPay.status = s;
    await hook(H, j.id);
    assert.equal((await call(H.a, { action: 'plan', code: P1, secret: S1 })).json().pro, false, s);
  }
});

test('renovar antes de vencer soma ao que sobrou', async () => {
  const H = mk();
  await born(H, P1, S1);
  const j1 = (await call(H.a, { action: 'pay_new', code: P1, secret: S1, period: 'm' })).json();
  mpPay.status = 'approved';
  await hook(H, j1.id);
  NOW += 10 * pay.DAY;
  const j2 = (await call(H.a, { action: 'pay_new', code: P1, secret: S1, period: 'y' })).json();
  mpPay.status = 'approved';
  await hook(H, j2.id);
  const a = (await call(H.a, { action: 'plan', code: P1, secret: S1 })).json();
  assert.equal(a.until, Date.UTC(2026, 10, 24, 15, 0, 0) + 30 * pay.DAY + 365 * pay.DAY);
});

test('pay_check: só o dono vê; confere pendente no Mercado Pago e libera quando aprovado', async () => {
  const H = mk();
  await born(H, P1, S1);
  await born(H, P2, S2);
  const j = (await call(H.a, { action: 'pay_new', code: P1, secret: S1, period: 'm' })).json();
  assert.equal((await call(H.a, { action: 'pay_check', code: P2, secret: S2, id: j.id })).statusCode, 404, 'outro perfil não vê');
  let c = (await call(H.a, { action: 'pay_check', code: P1, secret: S1, id: j.id })).json();
  assert.equal(c.status, 'pending');
  assert.equal(c.pro, false);
  mpPay.status = 'approved';
  c = (await call(H.a, { action: 'pay_check', code: P1, secret: S1, id: j.id })).json();
  assert.equal(c.status, 'approved');
  assert.equal(c.pro, true);
  const again = (await call(H.a, { action: 'pay_check', code: P1, secret: S1, id: j.id })).json();
  assert.equal(again.until, c.until, 'conferir de novo não soma');
});

test('pagamento que não é Pix nosso (sem referência) é ignorado com 200', async () => {
  const H = mk();
  await born(H, P1, S1);
  mpPay = { id: 777000333, status: 'approved', transaction_amount: 14.9, external_reference: `${P1}|m`, payment_method_id: 'pix' };
  assert.equal((await hook(H, 777000333)).statusCode, 200);
  assert.equal((await call(H.a, { action: 'plan', code: P1, secret: S1 })).json().pro, false);
});

test('livro: guarda o líquido e a taxa quando o Mercado Pago informa', async () => {
  const H = mk();
  await born(H, P1, S1);
  const j = (await call(H.a, { action: 'pay_new', code: P1, secret: S1, period: 'm' })).json();
  mpPay.status = 'approved';
  await hook(H, j.id);
  const h = (await call(H.a, { action: 'pay_hist', code: P1, secret: S1 })).json();
  assert.equal(h.items.length, 1);
  assert.equal(h.items[0].amount, 14.9);
  assert.equal(h.items[0].net, 14.75);
  assert.equal(h.items[0].fee, 0.15);
  assert.equal(h.items[0].refundable, true);
  assert.equal(h.refundDays, 7);
});

test('reembolso: dentro de 7 dias devolve, tira os dias e não repete', async () => {
  const H = mk();
  await born(H, P1, S1);
  const j = (await call(H.a, { action: 'pay_new', code: P1, secret: S1, period: 'm' })).json();
  mpPay.status = 'approved';
  await hook(H, j.id);
  assert.equal((await call(H.a, { action: 'plan', code: P1, secret: S1 })).json().pro, true);
  NOW += 3 * pay.DAY;
  const r = await call(H.a, { action: 'pay_refund', code: P1, secret: S1, id: j.id });
  assert.equal(r.statusCode, 200);
  assert.equal(r.json().pro, false, 'sem o pagamento, não há mais Pro');
  assert.equal(mpCalls.filter((c) => /refunds$/.test(c.url)).length, 1);
  assert.equal((await call(H.a, { action: 'pay_refund', code: P1, secret: S1, id: j.id })).statusCode, 409, 'segundo pedido não reembolsa de novo');
  assert.equal(mpCalls.filter((c) => /refunds$/.test(c.url)).length, 1);
  const h = (await call(H.a, { action: 'pay_hist', code: P1, secret: S1 })).json();
  assert.equal(h.items[0].status, 'refunded');
  assert.equal(h.items[0].refundable, false);
});

test('reembolso: depois de 7 dias o professor não pede (too_late) e outro perfil não vê', async () => {
  const H = mk();
  await born(H, P1, S1);
  await born(H, P2, S2);
  const j = (await call(H.a, { action: 'pay_new', code: P1, secret: S1, period: 'm' })).json();
  mpPay.status = 'approved';
  await hook(H, j.id);
  assert.equal((await call(H.a, { action: 'pay_refund', code: P2, secret: S2, id: j.id })).statusCode, 404);
  NOW += 8 * pay.DAY;
  const r = await call(H.a, { action: 'pay_refund', code: P1, secret: S1, id: j.id });
  assert.equal(r.statusCode, 409);
  assert.equal(r.json().error, 'too_late');
  assert.equal(mpCalls.filter((c) => /refunds$/.test(c.url)).length, 0);
});

test('reembolso de um pagamento tira só os dias dele (o outro continua)', async () => {
  const H = mk();
  await born(H, P1, S1);
  const a = (await call(H.a, { action: 'pay_new', code: P1, secret: S1, period: 'm' })).json();
  mpPay.status = 'approved';
  await hook(H, a.id);
  NOW += 1 * pay.DAY;
  const b = (await call(H.a, { action: 'pay_new', code: P1, secret: S1, period: 'y' })).json();
  mpPay.status = 'approved';
  await hook(H, b.id);
  const before = (await call(H.a, { action: 'plan', code: P1, secret: S1 })).json().until;
  await call(H.a, { action: 'pay_refund', code: P1, secret: S1, id: b.id });
  const after = (await call(H.a, { action: 'plan', code: P1, secret: S1 })).json();
  assert.equal(after.until, before - 365 * pay.DAY);
  assert.equal(after.pro, true);
});

test('reembolso: se o Mercado Pago recusar, nada muda (o Pro continua)', async () => {
  const H = mk();
  await born(H, P1, S1);
  const j = (await call(H.a, { action: 'pay_new', code: P1, secret: S1, period: 'm' })).json();
  mpPay.status = 'approved';
  await hook(H, j.id);
  refundFail = true;
  assert.equal((await call(H.a, { action: 'pay_refund', code: P1, secret: S1, id: j.id })).statusCode, 502);
  assert.equal((await call(H.a, { action: 'plan', code: P1, secret: S1 })).json().pro, true);
});

test('reembolso feito pelo painel do Mercado Pago (aviso refunded) também tira o Pro, uma vez', async () => {
  const H = mk();
  await born(H, P1, S1);
  const j = (await call(H.a, { action: 'pay_new', code: P1, secret: S1, period: 'm' })).json();
  mpPay.status = 'approved';
  await hook(H, j.id);
  mpPay.status = 'refunded';
  await hook(H, j.id);
  await hook(H, j.id, { requestId: 'req-9' });
  assert.equal((await call(H.a, { action: 'plan', code: P1, secret: S1 })).json().pro, false);
});

test('resumo: soma bruto, taxa e líquido e tira o reembolsado', () => {
  const ledger = require('./_lib/pay_ledger');
  const now = Date.UTC(2026, 10, 24);
  const list = [
    { id: '1', amount: 14.9, net: 14.75, fee: 0.15, paid: now - pay.DAY, status: 'approved' },
    { id: '2', amount: 149, net: 147.52, fee: 1.48, paid: now - 2 * pay.DAY, status: 'approved' },
    { id: '3', amount: 14.9, net: 14.75, fee: 0.15, paid: now - 3 * pay.DAY, status: 'refunded', refunded: now },
    { id: '4', amount: 14.9, paid: 0, status: 'pending' },
  ];
  const sm = ledger.summarize(list, now);
  assert.deepEqual(sm.all, { count: 2, gross: 163.9, fee: 1.63, net: 162.27 });
  assert.equal(sm.refundedCount, 1);
  assert.equal(sm.pending, 1);
});
