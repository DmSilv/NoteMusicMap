// Boletim do app: o painel escreve, publica, oculta e exclui; o app só lê o que está publicado.
// `node --test api/news.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const admin = require('./admin');
const pub = require('./news');
const news = require('./_lib/news');
const { config } = require('./_lib/config');
const { hashes, memory } = require('./_lib/store');
const { resetMem } = require('./_lib/store_cmd');

const KEY = 'chave-de-admin-de-teste';
let NOW = 1_800_000_000_000;
let ipN = 0;
const fakeRes = () => {
  const r = { headers: {}, statusCode: 0, body: '' };
  r.setHeader = (k, v) => { r.headers[k] = v; };
  r.end = (b) => { r.body = b; };
  r.json = () => JSON.parse(r.body);
  return r;
};
function mk() {
  hashes.clear();
  memory.clear();
  resetMem();
  NOW = 1_800_000_000_000;
  const deps = { config: () => config({ ADMIN_KEY: KEY }), allowMemory: true, fetch: async () => ({ status: 200 }), now: () => NOW };
  return { a: admin.makeHandler(deps), p: pub.makeHandler(deps) };
}
async function adm(H, body, key = KEY) {
  const res = fakeRes();
  await H.a({ method: 'POST', headers: { 'x-forwarded-for': '7.8.7.' + ++ipN, authorization: 'Bearer ' + key }, body, socket: {} }, res);
  return res;
}
async function get(H, method = 'GET') {
  const res = fakeRes();
  await H.p({ method, headers: {}, socket: {} }, res);
  return res;
}

test('texto: exige título e texto, corta o tamanho e limpa controle', () => {
  assert.ok(news.validate({ t: '', b: 'x' }).error);
  assert.ok(news.validate({ t: 'x', b: '  ' }).error);
  const v = news.validate({ t: 'a'.repeat(200), b: 'b\u0000c\n\n\n\nd'.padEnd(900, 'x'), te: 'T', be: 'B' }).v;
  assert.equal(v.t.length, news.MAX_TITLE);
  assert.equal(v.b.length, news.MAX_BODY);
  assert.ok(!v.b.includes('\u0000'));
  assert.ok(!v.b.includes('\n\n\n'));
});

test('nada nasce publicado: rascunho não aparece para o app', async () => {
  const H = mk();
  const r = await adm(H, { action: 'news_save', t: 'Olá', b: 'Texto' });
  assert.equal(r.statusCode, 200);
  assert.equal(r.json().item.st, 'draft');
  const g = await get(H);
  assert.equal(g.statusCode, 200);
  assert.deepEqual(g.json().items, []);
});

test('publicar, ocultar, voltar e excluir', async () => {
  const H = mk();
  const id = (await adm(H, { action: 'news_save', t: 'Primeira', b: 'Corpo', te: 'First', be: 'Body' })).json().id;
  NOW += 1000;
  assert.equal((await adm(H, { action: 'news_state', id, st: 'live' })).json().item.p, NOW);
  let items = (await get(H)).json().items;
  assert.equal(items.length, 1);
  assert.equal(items[0].t, 'Primeira');
  assert.equal(items[0].te, 'First');
  assert.ok(!('st' in items[0]) && !('c' in items[0]) && !('k' in items[0]), 'sem dado interno');
  await adm(H, { action: 'news_state', id, st: 'off' });
  assert.deepEqual((await get(H)).json().items, []);
  const list = (await adm(H, { action: 'news_list' })).json();
  assert.equal(list.items.length, 1, 'continua no histórico');
  assert.equal(list.items[0].st, 'off');
  assert.ok(list.items[0].p > 0, 'sabe que já foi publicado');
  await adm(H, { action: 'news_delete', id });
  assert.equal((await adm(H, { action: 'news_list' })).json().items.length, 0);
});

test('mais novo primeiro (pela hora da publicação) e no máximo 10', async () => {
  const H = mk();
  const ids = [];
  for (let i = 0; i < 12; i++) ids.push((await adm(H, { action: 'news_save', t: 'N' + i, b: 'x' })).json().id);
  for (const id of ids) { NOW += 1000; await adm(H, { action: 'news_state', id, st: 'live' }); }
  const items = (await get(H)).json().items;
  assert.equal(items.length, news.MAX_LIVE);
  assert.equal(items[0].t, 'N11');
});

test('editar mantém o estado; sugestão usada some da lista de sugestões', async () => {
  const H = mk();
  let l = (await adm(H, { action: 'news_list' })).json();
  const first = l.suggestions[0];
  assert.equal(first.k, 'boas-vindas');
  const id = (await adm(H, { action: 'news_save', t: first.t, b: first.b, k: first.k })).json().id;
  l = (await adm(H, { action: 'news_list' })).json();
  assert.ok(!l.suggestions.some((s) => s.k === 'boas-vindas'));
  await adm(H, { action: 'news_state', id, st: 'live' });
  await adm(H, { action: 'news_save', id, t: 'Novo título', b: 'Novo texto' });
  const it = (await get(H)).json().items[0];
  assert.equal(it.t, 'Novo título');
});

test('só o administrador mexe; id estranho é recusado; o app só usa GET', async () => {
  const H = mk();
  assert.equal((await adm(H, { action: 'news_list' }, 'chave-errada')).statusCode, 401);
  assert.equal((await adm(H, { action: 'news_state', id: '../x', st: 'live' })).statusCode, 400);
  assert.equal((await adm(H, { action: 'news_state', id: 'aaaaaaaaaa', st: 'live' })).statusCode, 400, 'inexistente');
  assert.equal((await adm(H, { action: 'news_state', id: 'aaaaaaaaaa', st: 'zzz' })).statusCode, 400);
  const p = await get(H, 'POST');
  assert.equal(p.statusCode, 405);
});

test('resposta pública é cacheável e sem erro de banco ela não é', async () => {
  const H = mk();
  const g = await get(H);
  assert.match(g.headers['Cache-Control'], /s-maxage=300/);
  const bad = pub.makeHandler({ config: () => { throw new Error('sem banco'); } });
  const res = fakeRes();
  await bad({ method: 'GET', headers: {}, socket: {} }, res);
  assert.equal(res.statusCode, 503);
  assert.equal(res.headers['Cache-Control'], 'no-store');
});

test('limite de publicações guardadas', async () => {
  const H = mk();
  for (let i = 0; i < news.MAX_ITEMS; i++) await adm(H, { action: 'news_save', t: 'x' + i, b: 'y' });
  const r = await adm(H, { action: 'news_save', t: 'a mais', b: 'y' });
  assert.equal(r.statusCode, 400);
});

test('destaque: só vai ao app quando marcado; sem a chave, o painel antigo não muda', async () => {
  const H = mk();
  const a = (await adm(H, { action: 'news_save', t: 'Com destaque', b: 'x', hl: 1 })).json().id;
  const b = (await adm(H, { action: 'news_save', t: 'Sem destaque', b: 'y' })).json().id;
  for (const id of [a, b]) await adm(H, { action: 'news_state', id, st: 'live' });
  const items = (await get(H)).json().items;
  assert.equal(items.find((i) => i.id === a).hl, 1);
  assert.ok(!('hl' in items.find((i) => i.id === b)));
  // editar sem mandar hl não apaga o destaque (painel antigo)
  await adm(H, { action: 'news_save', id: a, t: 'Com destaque 2', b: 'x' });
  assert.equal((await get(H)).json().items.find((i) => i.id === a).hl, 1);
  await adm(H, { action: 'news_save', id: a, t: 'Com destaque 2', b: 'x', hl: 0 });
  assert.ok(!('hl' in (await get(H)).json().items.find((i) => i.id === a)));
});
