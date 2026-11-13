// GET /api/fingering: dedilhados do violino que o administrador corrigiu ou incluiu (ver _lib/fingering.js).
// Público e sem dado pessoal. O app busca uma vez por abertura; a CDN guarda a resposta por 5 minutos, então o Redis
// quase não é tocado (no máximo 1 comando a cada 5 minutos por região). O que vem daqui vale no lugar da tabela do app.
'use strict';

const { config } = require('./_lib/config');
const { createStore } = require('./_lib/store');
const fing = require('./_lib/fingering');

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
    try {
      const store = createStore(getCfg(), fetchImpl, deps.now, { allowMemory: !!deps.allowMemory });
      items = (await fing.listOverrides(store)).map(({ pc, alt, type, oct, marks, ottava }) => ({ pc, alt, type, oct, marks, ottava }));
    } catch (_) {
      items = [];
    }
    // Sem banco (ou com erro) responde lista vazia: o app segue com a tabela que já tem. Só cacheia resposta boa.
    res.setHeader('Cache-Control', 'public, max-age=60, s-maxage=300, stale-while-revalidate=3600');
    res.statusCode = 200;
    res.end(JSON.stringify({ v: 1, items }));
  };
}

module.exports = makeHandler();
module.exports.makeHandler = makeHandler;
