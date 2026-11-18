// GET /api/news: o boletim publicado (ver _lib/news.js). Público e sem dado pessoal.
// O app busca uma vez por abertura; a CDN guarda a resposta por 5 minutos, então o Redis quase não é tocado
// (no máximo 1 comando a cada 5 minutos por região). Ocultar ou excluir no painel chega aos aparelhos em até ~5 minutos.
'use strict';

const { config } = require('./_lib/config');
const { createStore } = require('./_lib/store');
const news = require('./_lib/news');

function makeHandler(deps = {}) {
  const fetchImpl = deps.fetch || globalThis.fetch;
  const getCfg = deps.config || (() => config());
  return async function handler(req, res) {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    if (req.method !== 'GET') {
      res.statusCode = 405;
      res.setHeader('Cache-Control', 'no-store');
      return res.end(JSON.stringify({ error: 'Use GET.' }));
    }
    let items = [];
    let ok = true;
    try {
      const store = createStore(getCfg(), fetchImpl, deps.now, { allowMemory: !!deps.allowMemory });
      items = news.publicItems(await news.listAll(store));
    } catch (_) {
      items = [];
      ok = false;
    }
    // Com erro responde lista vazia e NÃO deixa a CDN guardar (o app, ao ver erro, mantém o que já tem).
    res.setHeader('Cache-Control', ok ? 'public, max-age=60, s-maxage=300, stale-while-revalidate=3600' : 'no-store');
    res.statusCode = ok ? 200 : 503;
    res.end(JSON.stringify({ v: 1, items }));
  };
}

module.exports = makeHandler();
module.exports.makeHandler = makeHandler;
