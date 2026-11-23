// Segurança do pagamento por Pix (tentativas de ataque e abuso), sem rede: `node --test api/pay_security.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const account = require('./account');
const link = require('./link');
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
const P1 = code(11111), P2 = code(22222);
const S1 = 'a'.repeat(64), S2 = 'b'.repeat(64);
const SECRET = 'segredo-do-webhook-de-teste';
const TOKEN = 'APP_USR-token-super-secreto-123';
const ON = { enabled: true, token: TOKEN, secret: SECRET, publicUrl: 'https://exemplo.test', testCodes: [] };
const ADMIN = 'chave-admin-xyz', SUPPORT = 'chave-suporte-xyz';

let NOW = Date.UTC(2026, 10, 24, 15, 0, 0);
let ipN = 0, mpSeq = 0, mpPay, mpCalls, refunds;

function mk(pcfg = ON) {
  hashes.clear(); memory.clear(); resetMem();
  NOW = Date.UTC(2026, 10, 24, 15, 0, 0);
  mpSeq = 0; mpCalls = 0; refunds = 0; mpPay = null;
  const fetch = async (url, init) => {
    mpCalls++;
    if (String(url).endsWith('/v1/payments') && init.method === 'POST') {
      const body = JSON.parse(init.body);
      mpPay = { id: 700000100 + mpSeq++, status: 'pending', currency_id: 'BRL', transaction_amount: body.transaction_amount, external_reference: body.external_reference, payment_method_id: 'pix', transaction_details: { net_received_amount: body.transaction_amount } };
      return { ok: true, json: async () => ({ ...mpPay, point_of_interaction: { transaction_data: { qr_code: 'x', qr_code_base64: 'QQ==' } } }) };
    }
    if (String(url).endsWith('/refunds')) { refunds++; return { ok: true, json: async () => ({ id: 1 }) }; }
    if (String(url).includes('/v1/payments/')) return { ok: true, json: async () => ({ ...(mpPay || { id: 1, status: 'pending' }) }) };
    throw new Error('sem rede');
  };
  const deps = { config: () => config({ ADMIN_KEY: ADMIN, SUPPORT_KEY: SUPPORT }), allowMemory: true, fetch, now: () => NOW, pay: pcfg };
  return { a: account.makeHandler(deps), l: link.makeHandler(deps), adm: admin.makeHandler(deps) };
}
function fakeRes() {
  const r = { headers: {}, statusCode: 0, body: '' };
  r.setHeader = (k, v) => { r.headers[k] = v; };
  r.end = (b) => { r.body = b; };
  r.json = () => JSON.parse(r.body);
  return r;
}
async function acc(H, body, o = {}) {
  const res = fakeRes();
  await H.a({ method: o.method || 'POST', headers: { 'x-forwarded-for': o.ip || '9.9.9.' + ++ipN, ...(o.headers || {}) }, body, query: o.query, socket: {} }, res);
  return res;
}
async function adm(H, body, key = ADMIN) {
  const res = fakeRes();
  await H.adm({ method: 'POST', headers: { 'x-forwarded-for': '5.5.5.' + ++ipN, ...(key ? { authorization: 'Bearer ' + key } : {}) }, body, socket: {} }, res);
  return res;
}
const born = (H, c, s) => H.l({ method: 'POST', headers: { 'x-forwarded-for': '2.2.2.' + ++ipN }, body: { action: 'sync', code: c, secret: s }, socket: {} }, fakeRes());
const sigOf = (dataId, requestId, ts = '1700000000', secret = SECRET) => `ts=${ts},v1=${crypto.createHmac('sha256', secret).update(`id:${dataId};request-id:${requestId};ts:${ts};`).digest('hex')}`;
const hook = (H, id, o = {}) => acc(H, {}, { ip: o.ip, query: { mp: 'hook', 'data.id': String(id) }, headers: o.noSig ? {} : { 'x-signature': o.signature || sigOf(id, 'r1'), 'x-request-id': 'r1' } });
async function buy(H, c = P1, s = S1, period = 'm') {
  const j = (await acc(H, { action: 'pay_new', code: c, secret: s, period })).json();
  mpPay.status = 'approved';
  await hook(H, j.id);
  return j.id;
}
const planOf = async (H, c = P1, s = S1) => (await acc(H, { action: 'plan', code: c, secret: s })).json();

test('aviso: só aceita POST', async () => {
  const H = mk();
  const r = await acc(H, {}, { method: 'GET', query: { mp: 'hook', 'data.id': '123456' } });
  assert.equal(r.statusCode, 405);
});

test('aviso falso (sem assinatura, assinatura de outro segredo, id trocado): 401, não fala com o Mercado Pago e não libera', async () => {
  const H = mk();
  await born(H, P1, S1);
  const j = (await acc(H, { action: 'pay_new', code: P1, secret: S1, period: 'm' })).json();
  mpPay.status = 'approved';
  const before = mpCalls;
  assert.equal((await hook(H, j.id, { noSig: true })).statusCode, 401);
  assert.equal((await hook(H, j.id, { signature: sigOf(j.id, 'r1', '1700000000', 'outro') })).statusCode, 401);
  assert.equal((await hook(H, j.id, { signature: sigOf('999999', 'r1') })).statusCode, 401, 'assinatura de outro pagamento');
  assert.equal(mpCalls, before, 'aviso falso nunca chega ao Mercado Pago');
  assert.equal((await planOf(H)).pro, false);
});

test('assinatura: cabeçalhos malformados, enormes ou com injeção de campos não passam', () => {
  const ok = { requestId: 'r1', dataId: '123456', secret: SECRET };
  const valid = sigOf('123456', 'r1');
  assert.equal(pay.verifySignature({ ...ok, signature: valid }), true);
  for (const bad of ['', 'v1=abc', 'ts=1', 'ts=1,v1=', `ts=1700000000,v1=${'0'.repeat(64)}`, valid + ',v1=' + '0'.repeat(64) + 'x', 'x'.repeat(10000), valid.replace('v1=', 'V1=')]) {
    assert.equal(pay.verifySignature({ ...ok, signature: bad }), false, bad.slice(0, 30));
  }
  // o v1 duplicado: vale o último, que aqui é inválido
  assert.equal(pay.verifySignature({ ...ok, signature: valid + ',v1=' + 'f'.repeat(64) }), false);
  assert.equal(pay.verifySignature({ ...ok, signature: valid, secret: undefined }), false);
  assert.equal(pay.verifySignature({ ...ok, signature: 12345 }), false);
  assert.equal(pay.verifySignature({ ...ok, signature: null }), false);
});

test('assinatura: injetar partes do texto assinado no id não forja outra', () => {
  // o atacante tem uma assinatura válida do pagamento 111 com request-id r1 e ts T; tenta passá-la por outro id "111;request-id:r1;ts:T"
  const T = '1700000000';
  const v = sigOf('111', 'r1', T);
  for (const forged of ['111;request-id:r1;ts:' + T, '111;', '1 11', '111\n', '']) {
    assert.equal(pay.verifySignature({ signature: v, requestId: 'r1', dataId: forged, secret: SECRET }), forged === '111' ? true : false, JSON.stringify(forged));
  }
});

test('aviso falso em massa: depois de 60 por hora a origem toma 429 e deixa de gastar o banco', async () => {
  const H = mk();
  const ip = '66.66.66.66';
  let last = 0;
  for (let i = 0; i < 70; i++) last = (await hook(H, '123456', { noSig: true, ip })).statusCode;
  assert.equal(last, 429);
  const other = await hook(H, '123456', { noSig: true, ip: '77.77.77.77' });
  assert.equal(other.statusCode, 401, 'outra origem continua sendo atendida normalmente');
});

test('aviso verdadeiro de um pagamento que NÃO é nosso (id que não criamos) não libera nada', async () => {
  const H = mk();
  await born(H, P1, S1);
  mpPay = { id: 424242424, status: 'approved', currency_id: 'BRL', transaction_amount: 14.9, external_reference: `${P1}|m`, payment_method_id: 'pix' };
  assert.equal((await hook(H, 424242424)).statusCode, 200);
  assert.equal((await planOf(H)).pro, false);
});

test('aviso aprovado cuja referência aponta para OUTRO perfil que o do nosso registro: ignora', async () => {
  const H = mk();
  await born(H, P1, S1);
  await born(H, P2, S2);
  const j = (await acc(H, { action: 'pay_new', code: P1, secret: S1, period: 'm' })).json();
  mpPay.status = 'approved';
  mpPay.external_reference = `${P2}|m`; // alguém tenta desviar o Pro para o perfil 2
  await hook(H, j.id);
  assert.equal((await planOf(H, P2, S2)).pro, false);
  assert.equal((await planOf(H, P1, S1)).pro, false);
  mpPay.external_reference = `${P1}|y`; // plano trocado
  await hook(H, j.id);
  assert.equal((await planOf(H)).pro, false);
});

test('moeda diferente de BRL não libera', async () => {
  const H = mk();
  await born(H, P1, S1);
  const j = (await acc(H, { action: 'pay_new', code: P1, secret: S1, period: 'm' })).json();
  mpPay.status = 'approved';
  mpPay.currency_id = 'USD';
  await hook(H, j.id);
  assert.equal((await planOf(H)).pro, false);
});

test('avisos repetidos e em paralelo liberam UMA vez só', async () => {
  const H = mk();
  await born(H, P1, S1);
  const j = (await acc(H, { action: 'pay_new', code: P1, secret: S1, period: 'm' })).json();
  mpPay.status = 'approved';
  await Promise.all(Array.from({ length: 12 }, () => hook(H, j.id)));
  const a = await planOf(H);
  assert.equal(a.until, NOW + 30 * pay.DAY);
});

test('reembolso em paralelo (clique duplo ou ataque) chama o Mercado Pago UMA vez e tira o Pro UMA vez', async () => {
  const H = mk();
  await born(H, P1, S1);
  await buy(H);
  const id = String(mpPay.id);
  await buy(H, P1, S1, 'y'); // outro pagamento do mesmo perfil, que não pode ser tocado
  const before = (await planOf(H)).until;
  const rs = await Promise.all(Array.from({ length: 8 }, () => acc(H, { action: 'pay_refund', code: P1, secret: S1, id })));
  assert.equal(rs.filter((r) => r.statusCode === 200).length, 1, 'só um pedido vence');
  assert.equal(refunds, 1, 'o Mercado Pago foi chamado uma vez');
  assert.equal((await planOf(H)).until, before - 30 * pay.DAY, 'só os 30 dias do mensal saíram; o anual continua');
});

test('reembolso: depois de feito, um aviso "approved" repetido não devolve o Pro', async () => {
  const H = mk();
  await born(H, P1, S1);
  const id = await buy(H);
  assert.equal((await acc(H, { action: 'pay_refund', code: P1, secret: S1, id })).statusCode, 200);
  assert.equal((await planOf(H)).pro, false);
  mpPay.status = 'approved'; // aviso velho reenviado
  await hook(H, id);
  assert.equal((await planOf(H)).pro, false, 'o mesmo pagamento nunca libera duas vezes');
});

test('IDOR: um perfil não vê, não confere nem reembolsa o pagamento de outro, e o histórico é só dele', async () => {
  const H = mk();
  await born(H, P1, S1);
  await born(H, P2, S2);
  const id = await buy(H);
  assert.equal((await acc(H, { action: 'pay_check', code: P2, secret: S2, id })).statusCode, 404);
  assert.equal((await acc(H, { action: 'pay_refund', code: P2, secret: S2, id })).statusCode, 404);
  assert.equal((await acc(H, { action: 'pay_hist', code: P2, secret: S2 })).json().items.length, 0);
  assert.equal((await acc(H, { action: 'pay_hist', code: P1, secret: S1 })).json().items.length, 1);
  // segredo errado do dono
  assert.notEqual((await acc(H, { action: 'pay_hist', code: P1, secret: S2 })).statusCode, 200);
});

test('entradas estranhas não causam erro 500 nem escapam: plano, id e tipos', async () => {
  const H = mk();
  await born(H, P1, S1);
  for (const period of ['__proto__', 'constructor', 'toString', 'M', 'm ', '', null, 1, {}, [], 'm"; DROP', 't']) {
    const r = await acc(H, { action: 'pay_new', code: P1, secret: S1, period });
    assert.ok([400, 429].includes(r.statusCode), `period ${JSON.stringify(period)} → ${r.statusCode}`);
  }
  for (const id of ['../x', '1;DROP', '99999999999999999999999', 'abc', '', null, 12, {}, '1 2', '%2e%2e']) {
    const c = await acc(H, { action: 'pay_check', code: P1, secret: S1, id });
    const rr = await acc(H, { action: 'pay_refund', code: P1, secret: S1, id });
    assert.ok([400, 404, 429].includes(c.statusCode) && [400, 404, 429].includes(rr.statusCode), `id ${JSON.stringify(id)} → ${c.statusCode}/${rr.statusCode}`);
  }
});

test('ninguém consegue pedir o plano de teste (R$ 1) sem estar em PAY_TEST_CODES, nem com minúsculas ou espaços', async () => {
  const H = mk({ ...ON, testCodes: [P2] });
  await born(H, P1, S1);
  const r = await acc(H, { action: 'pay_new', code: P1, secret: S1, period: 't' });
  assert.equal(r.statusCode, 400);
  assert.equal(pay.canBuy({ testCodes: [P2] }, pay.PLANS.t, P1.toLowerCase()), false);
  assert.equal(pay.payConfig({ PAY_TEST_CODES: ' abcd-efgh , ijkl-mnop ' }).testCodes[0], 'ABCD-EFGH');
  assert.equal(pay.payConfig({}).testCodes.length, 0, 'sem a variável, ninguém');
});

test('teto do dia: depois de 300 Pix novos no servidor todo, o 301º é recusado', async () => {
  const H = mk();
  let blocked = 0, made = 0;
  for (let u = 0; u < 35 && made < 305; u++) {
    const c = code(300000 + u), s = crypto.createHash('sha256').update('u' + u).digest('hex');
    await born(H, c, s);
    for (let k = 0; k < 9 && made < 305; k++) {
      const r = await acc(H, { action: 'pay_new', code: c, secret: s, period: 'm' }, { ip: '8.8.' + u + '.' + k });
      made++;
      if (r.statusCode === 429) blocked++;
    }
  }
  assert.ok(blocked >= 5, `esperava recusas depois de 300 (recusou ${blocked})`);
});

test('desligado ou sem chaves: nem o aviso assinado faz efeito', async () => {
  const H = mk({ enabled: false, token: '', secret: SECRET, publicUrl: '' });
  await born(H, P1, S1);
  assert.equal((await hook(H, '123456')).statusCode, 200);
  assert.equal(mpCalls, 0);
});

test('nenhuma resposta do app ou do painel contém o token do Mercado Pago nem o segredo do aviso', async () => {
  const H = mk({ ...ON, testCodes: [P1] });
  await born(H, P1, S1);
  const bodies = [];
  const id = await buy(H);
  bodies.push((await acc(H, { action: 'plan', code: P1, secret: S1 })).body);
  bodies.push((await acc(H, { action: 'pay_hist', code: P1, secret: S1 })).body);
  bodies.push((await acc(H, { action: 'pay_check', code: P1, secret: S1, id })).body);
  bodies.push((await acc(H, { action: 'pay_new', code: P1, secret: S1, period: 'y' })).body);
  bodies.push((await adm(H, { action: 'pay_overview' })).body);
  bodies.push((await hook(H, '1', { noSig: true })).body);
  for (const b of bodies) {
    assert.ok(!b.includes(TOKEN) && !b.includes('super-secreto') && !b.includes(SECRET) && !b.includes(S1), 'vazou segredo: ' + b.slice(0, 80));
  }
});

test('painel: sem chave 401, chave errada 401, suporte 403 em tudo de pagamento', async () => {
  const H = mk();
  for (const action of ['pay_overview', 'pay_refund', 'pay_import']) {
    assert.equal((await adm(H, { action, id: '123456' }, '')).statusCode, 401, action + ' sem chave');
    assert.equal((await adm(H, { action, id: '123456' }, 'errada')).statusCode, 401, action + ' chave errada');
    assert.equal((await adm(H, { action, id: '123456' }, SUPPORT)).statusCode, 403, action + ' suporte');
  }
});

test('painel: o número do pagamento só aceita dígitos (nada de caminho nem consulta)', async () => {
  const H = mk();
  for (const id of ['../../x', '123456/refunds', '1?x=1', 'abc', '12']) {
    const r = await adm(H, { action: 'pay_refund', id });
    assert.equal(r.statusCode, 400, id);
  }
  assert.equal(mpCalls, 0);
});

test('painel: a tabela de pagamentos usa textContent (nada de innerHTML com dados do servidor)', () => {
  const html = fs.readFileSync(path.join(__dirname, '..', 'web', 'admin.html'), 'utf8');
  const a = html.indexOf('function renderPay');
  const b = html.indexOf('$(\'payImpGo\')', a);
  const fn = html.slice(a, b);
  assert.ok(fn.length > 500);
  assert.ok(!/innerHTML|insertAdjacentHTML|document\.write/.test(fn), 'renderPay não pode escrever HTML');
});

test('o app não manda nem guarda dados de pagamento: só código e segredo do aparelho', () => {
  const svc = fs.readFileSync(path.join(__dirname, '..', 'lib', 'link', 'pay_service.dart'), 'utf8');
  assert.ok(!/cart[aã]o|card_number|cvv|cpf/i.test(svc), 'sem dados de cartão nem CPF');
  const plan = fs.readFileSync(path.join(__dirname, '..', 'lib', 'ui', 'plan_page.dart'), 'utf8');
  assert.ok(!/MP_ACCESS_TOKEN|APP_USR|TEST-/.test(plan), 'sem chave do Mercado Pago no app');
});

test('estado do pagamento no painel: tipo da chave, contagens do dia e último aviso (sem segredo)', async () => {
  const H = mk({ ...ON, token: 'TEST-abc', testCodes: [P1] });
  await born(H, P1, S1);
  await buy(H);
  await hook(H, '123456', { noSig: true });
  const r = (await adm(H, { action: 'pay_overview' })).json();
  assert.equal(r.health.mode, 'teste');
  assert.equal(r.health.testCodes, 1);
  assert.ok(r.health.today.new_ok >= 1);
  assert.ok(r.health.today.hook_ok >= 1);
  assert.ok(r.health.today.hook_bad >= 1);
  assert.ok(r.health.today.grant >= 1);
  assert.ok(r.health.today.lastHook > 0);
  assert.ok(!JSON.stringify(r.health).includes('abc'));
});
