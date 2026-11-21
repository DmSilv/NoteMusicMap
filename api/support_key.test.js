// Chave de suporte: abre só o atendimento; excluir/publicar/custos ficam só no admin.
// `node --test api/support_key.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const admin = require('./admin');
const { config } = require('./_lib/config');
const { resetMem } = require('./_lib/store_cmd');

const KEY = 'chave-admin-teste', SUP = 'chave-suporte-teste';
let ipN = 0;
function mk(env = { SUPPORT_KEY: SUP }) {
  resetMem();
  const deps = { config: () => config({ ADMIN_KEY: KEY, ...env }), allowMemory: true, fetch: async () => ({ status: 200 }), now: () => 1_800_000_000_000 };
  return admin.makeHandler(deps);
}
async function call(h, key, body) {
  const res = { headers: {}, statusCode: 0, body: '', setHeader() {}, end(b) { this.body = b; } };
  await h({ method: 'POST', headers: { 'x-forwarded-for': '9.9.9.' + ++ipN, authorization: 'Bearer ' + key }, body, socket: {} }, res);
  return { status: res.statusCode, json: JSON.parse(res.body) };
}

test('whoami diz o papel de cada chave', async () => {
  const h = mk();
  assert.equal((await call(h, KEY, { action: 'whoami' })).json.role, 'admin');
  assert.equal((await call(h, SUP, { action: 'whoami' })).json.role, 'support');
});

test('suporte atende (lista, conversa, pedidos) mas não exclui nem vê custos/sistema/publicações', async () => {
  const h = mk();
  for (const a of ['list', 'inbox_list', 'rq_list', 'bugs']) assert.equal((await call(h, SUP, { action: a })).status, 200, a);
  for (const a of ['delete', 'inbox_delete', 'costs', 'system', 'push', 'news_save', 'feature_grant', 'unlink', 'sweep', 'kpis', 'log'])
    assert.equal((await call(h, SUP, { action: a, code: 'AAAA-AAAA' })).status, 403, a);
});

test('admin continua podendo tudo; chave errada dá 401', async () => {
  const h = mk();
  assert.equal((await call(h, KEY, { action: 'kpis' })).status, 200);
  assert.equal((await call(h, 'errada', { action: 'whoami' })).status, 401);
});

test('sem SUPPORT_KEY a chave de suporte não existe; igual à do admin é ignorada', async () => {
  assert.equal((await call(mk({}), SUP, { action: 'whoami' })).status, 401);
  assert.equal((await call(mk({ SUPPORT_KEY: KEY }), KEY, { action: 'whoami' })).json.role, 'admin');
});
