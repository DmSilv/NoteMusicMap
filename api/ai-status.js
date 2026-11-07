// GET /api/ai-status: quais serviços de IA estão ativos e quanto se espera na fila.
// Nunca devolve chaves; só o necessário para o app mostrar o estado.
'use strict';

const { config, PROVIDER_KEYS, LABELS } = require('./_lib/config');
const { createStore } = require('./_lib/store');
const { KINDS, isOpen } = require('./_lib/router');
const { estimateWait } = require('./_lib/queue');

function makeHandler(deps = {}) {
  const fetchImpl = deps.fetch || globalThis.fetch;
  const getCfg = deps.config || (() => config());
  return async function handler(req, res) {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.setHeader('Cache-Control', 'no-store');
    if (req.method !== 'GET') {
      res.statusCode = 405;
      return res.end(JSON.stringify({ error: 'Use GET.' }));
    }
    const cfg = getCfg();
    const store = createStore(cfg, fetchImpl);
    const now = Date.now();
    const providers = [];
    for (const id of Object.keys(PROVIDER_KEYS)) {
      const enabled = !!cfg.keys[id] && (!cfg.allow || cfg.allow.includes(id));
      providers.push({
        id,
        label: LABELS[id],
        enabled,
        healthy: enabled ? !(await isOpen(store, id)) : false,
        waitMs: enabled ? await estimateWait(store, cfg, id, now) : 0,
      });
    }
    res.statusCode = 200;
    res.end(JSON.stringify({ providers, kinds: Object.keys(KINDS), shared: store.redis }));
  };
}

module.exports = makeHandler();
module.exports.makeHandler = makeHandler;
