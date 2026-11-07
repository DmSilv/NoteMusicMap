// Testes da função /api/coach sem rede e sem chave real: `node --test api/`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { makeHandler, _internal } = require('./coach');

const SUMMARY = 'Escala de Ré maior, 2 oitavas. Média de desvio: +6 cents. Notas mais agudas: F# (+14).';

function fakeRes() {
  const r = { headers: {}, statusCode: 0, body: '' };
  r.setHeader = (k, v) => { r.headers[k] = v; };
  r.end = (b) => { r.body = b; };
  r.json = () => JSON.parse(r.body);
  return r;
}
function fakeReq(over = {}) {
  return {
    method: 'POST',
    headers: { 'x-device-id': 'aparelho1', 'x-forwarded-for': '1.2.3.4' },
    body: { summary: SUMMARY },
    socket: {},
    ...over,
  };
}
function geminiOk(text = '1. Respire.') {
  return async () => ({
    ok: true, status: 200,
    json: async () => ({ candidates: [{ content: { parts: [{ text }] } }] }),
  });
}
function mk(extra = {}, fetchImpl = geminiOk()) {
  _internal.memory.clear();
  const cfg = { key: 'chave-de-teste', models: ['m1'], userDaily: 3, cooldownS: 20, rpm: 100, rpd: 100, redisUrl: '', redisToken: '', ...extra };
  return makeHandler({ fetch: fetchImpl, config: () => cfg });
}
async function call(h, req = fakeReq()) {
  const res = fakeRes();
  await h(req, res);
  return res;
}

test('só aceita POST', async () => {
  const res = await call(mk(), fakeReq({ method: 'GET' }));
  assert.equal(res.statusCode, 405);
});

test('sem chave configurada responde 503 (e não vaza nada)', async () => {
  const res = await call(mk({ key: '' }));
  assert.equal(res.statusCode, 503);
  assert.ok(!res.body.includes('chave-de-teste'));
});

test('valida o corpo', async () => {
  const h = mk();
  assert.equal((await call(h, fakeReq({ body: {} }))).statusCode, 400);
  assert.equal((await call(h, fakeReq({ body: { summary: 'curto' } }))).statusCode, 400);
  assert.equal((await call(h, fakeReq({ body: { summary: 'x'.repeat(4001) } }))).statusCode, 400);
});

test('caminho feliz devolve o texto do Gemini', async () => {
  const res = await call(mk());
  assert.equal(res.statusCode, 200);
  assert.equal(res.json().text, '1. Respire.');
  assert.equal(res.json().remainingToday, 2);
});

test('a chave vai no cabeçalho, nunca na URL', async () => {
  let seen;
  const h = mk({}, async (url, opts) => { seen = { url, opts }; return geminiOk()(); });
  await call(h);
  assert.ok(!String(seen.url).includes('chave-de-teste'));
  assert.equal(seen.opts.headers['x-goog-api-key'], 'chave-de-teste');
});

test('intervalo mínimo: segundo pedido seguido leva 429 com retryAfterMs', async () => {
  const h = mk();
  assert.equal((await call(h)).statusCode, 200);
  const r2 = await call(h);
  assert.equal(r2.statusCode, 429);
  assert.equal(r2.json().error, 'cooldown');
  assert.ok(r2.json().retryAfterMs > 0);
});

test('limite diário por pessoa', async () => {
  const h = mk({ cooldownS: 0.001 });
  for (let i = 0; i < 3; i++) {
    assert.equal((await call(h)).statusCode, 200);
    _internal.memory.delete(`cd:${[..._internal.memory.keys()].find((k) => k.startsWith('cd:')).slice(3)}`);
  }
  const r = await call(h);
  assert.equal(r.statusCode, 429);
  assert.equal(r.json().error, 'user_daily');
});

test('limite global por minuto protege o plano gratuito (fila no app)', async () => {
  const h = mk({ rpm: 1 });
  assert.equal((await call(h, fakeReq({ headers: { 'x-device-id': 'a', 'x-forwarded-for': '1.1.1.1' } }))).statusCode, 200);
  const r = await call(h, fakeReq({ headers: { 'x-device-id': 'b', 'x-forwarded-for': '2.2.2.2' } }));
  assert.equal(r.statusCode, 429);
  assert.equal(r.json().error, 'busy');
  assert.ok(r.json().retryAfterMs > 0 && r.json().retryAfterMs <= 63000);
});

test('429 do Gemini vira "busy" para o app esperar na fila', async () => {
  const h = mk({}, async () => ({ ok: false, status: 429, json: async () => ({}) }));
  const r = await call(h);
  assert.equal(r.statusCode, 429);
  assert.equal(r.json().error, 'busy');
});

test('chave recusada pelo Gemini gera mensagem clara', async () => {
  const h = mk({}, async () => ({ ok: false, status: 403, json: async () => ({}) }));
  const r = await call(h);
  assert.equal(r.statusCode, 502);
  assert.match(r.json().error, /Chave/);
});

test('modelo inexistente: tenta o próximo', async () => {
  let n = 0;
  const h = mk({ models: ['ruim', 'bom'] }, async () => (++n === 1 ? { ok: false, status: 404, json: async () => ({}) } : geminiOk('ok')()));
  const r = await call(h);
  assert.equal(r.statusCode, 200);
  assert.equal(n, 2);
});

test('remove caracteres de controle do resumo', () => {
  assert.equal(_internal.cleanSummary('a\u0000b\u0007c\nd'), 'abc\nd');
});

test('config lê geminiAPI da Vercel', () => {
  assert.equal(_internal.config({ geminiAPI: 'k' }).key, 'k');
  assert.equal(_internal.config({ GEMINI_API_KEY: 'z' }).key, 'z');
  assert.equal(_internal.config({}).key, '');
});
