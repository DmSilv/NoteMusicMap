// Testes da nota do app e das pesquisas rápidas, sem rede: `node --test api/feedback.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { makeHandler, _internal } = require('./feedback');
const { config } = require('./_lib/config');
const { lists, memory } = require('./_lib/store');

function fakeRes() {
  const r = { headers: {}, statusCode: 0, body: '' };
  r.setHeader = (k, v) => { r.headers[k] = v; };
  r.end = (b) => { r.body = b; };
  r.json = () => JSON.parse(r.body);
  return r;
}
let n = 0;
function post(body, dev = 'aparelho' + ++n, ip = '9.9.9.' + n) {
  return { method: 'POST', headers: { 'x-device-id': dev, 'x-forwarded-for': ip }, body, socket: {} };
}
function mk(env = {}, now = () => 1_800_000_000_000) {
  lists.clear();
  memory.clear();
  return makeHandler({ config: () => config(env), now, fetch: async () => { throw new Error('sem rede'); } });
}
async function call(h, r) {
  const res = fakeRes();
  await h(r, res);
  return res;
}
const get = (key) => ({ method: 'GET', headers: key ? { authorization: 'Bearer ' + key } : {}, socket: {} });

test('nota de 1 a 5 é aceita; fora disso, recusada', async () => {
  const h = mk();
  assert.equal((await call(h, post({ kind: 'rating', rating: 5, version: 'abc' }))).statusCode, 200);
  assert.equal((await call(h, post({ kind: 'rating', rating: 0 }))).statusCode, 400);
  assert.equal((await call(h, post({ kind: 'rating', rating: 6 }))).statusCode, 400);
  assert.equal((await call(h, post({ kind: 'rating', rating: 3.5 }))).statusCode, 400);
  assert.equal((await call(h, post({ kind: 'rating' }))).statusCode, 400);
});

test('pesquisa: exige pergunta válida e resposta', async () => {
  const h = mk();
  assert.equal((await call(h, post({ kind: 'survey', qid: 'o_que_mais', answer: 'Grade' }))).statusCode, 200);
  assert.equal((await call(h, post({ kind: 'survey', qid: 'Pergunta ruim!', answer: 'x' }))).statusCode, 400);
  assert.equal((await call(h, post({ kind: 'survey', qid: 'ok', answer: '   ' }))).statusCode, 400);
  assert.equal((await call(h, post({ kind: 'outro' }))).statusCode, 400);
  assert.equal((await call(h, post(null))).statusCode, 400);
});

test('sem aparelho identificado, recusa; só aceita POST/GET', async () => {
  const h = mk();
  const r = post({ kind: 'rating', rating: 4 });
  delete r.headers['x-device-id'];
  assert.equal((await call(h, r)).statusCode, 400);
  assert.equal((await call(h, { method: 'PUT', headers: {}, socket: {} })).statusCode, 405);
});

test('não guarda o código do aparelho nem o IP; limpa controle e corta texto', async () => {
  const h = mk();
  await call(h, post({ kind: 'rating', rating: 4, comment: 'bom\u0000\n app ' + 'x'.repeat(900) }, 'meu-aparelho-secreto', '5.5.5.5'));
  const raw = [...lists.values()][0][0];
  assert.ok(!raw.includes('meu-aparelho-secreto'));
  assert.ok(!raw.includes('5.5.5.5'));
  const rec = JSON.parse(raw);
  assert.equal(rec.d.length, 16);
  assert.ok(rec.c.length <= 500);
  assert.ok(!/[\u0000-\u001f]/.test(rec.c));
});

test('limite diário por aparelho', async () => {
  const h = mk();
  const r = () => post({ kind: 'rating', rating: 5 }, 'mesmo', '1.1.1.1');
  let last;
  for (let i = 0; i < 31; i++) last = await call(h, r());
  assert.equal(last.statusCode, 429);
});

test('leitura: desligada sem chave, protegida com chave', async () => {
  const off = mk();
  assert.equal((await call(off, get('qualquer'))).statusCode, 404);
  const h = mk({ FEEDBACK_ADMIN_KEY: 'segredo-do-dono' });
  assert.equal((await call(h, get())).statusCode, 401);
  assert.equal((await call(h, get('errada'))).statusCode, 401);
  const ok = await call(h, get('segredo-do-dono'));
  assert.equal(ok.statusCode, 200);
  assert.equal(ok.json().rating.count, 0);
});

test('resumo: média usa a última nota de cada aparelho; pesquisa conta uma resposta por aparelho', async () => {
  const h = mk({ FEEDBACK_ADMIN_KEY: 'k' });
  await call(h, post({ kind: 'rating', rating: 2, comment: 'meh' }, 'a'));
  await call(h, post({ kind: 'rating', rating: 5, comment: 'adorei' }, 'a')); // mudou de ideia
  await call(h, post({ kind: 'rating', rating: 3 }, 'b'));
  await call(h, post({ kind: 'survey', qid: 'mais_usa', answer: 'Grade' }, 'a'));
  await call(h, post({ kind: 'survey', qid: 'mais_usa', answer: 'Grade' }, 'a')); // repetida
  await call(h, post({ kind: 'survey', qid: 'mais_usa', answer: 'Escalas' }, 'b'));
  const s = (await call(h, get('k'))).json();
  assert.equal(s.rating.count, 2);
  assert.equal(s.rating.average, 4); // (5 + 3) / 2
  assert.deepEqual(s.rating.histogram, { 1: 0, 2: 0, 3: 1, 4: 0, 5: 1 });
  assert.equal(s.comments.length, 1);
  assert.equal(s.comments[0].c, 'adorei');
  assert.equal(s.surveys.mais_usa.total, 2);
  assert.deepEqual(s.surveys.mais_usa.answers, { Grade: 1, Escalas: 1 });
  assert.ok(!JSON.stringify(s).includes('"d"')); // nenhum código de aparelho na resposta
});

test('summarize lida com lista vazia', () => {
  const s = _internal.summarize([]);
  assert.equal(s.rating.average, null);
  assert.equal(s.rating.count, 0);
});
