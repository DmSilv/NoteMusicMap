// POST /api/errors: relatório de erro do app (anônimo e sem dados pessoais).
//
// O app manda o que aconteceu (código, tela, detalhe já higienizado, versão, aparelho, trilha de
// telas). O servidor higieniza DE NOVO (nunca confia no app), agrupa o mesmo bug por impressão
// digital e guarda contadores, aparelhos afetados (distintos), tendência e as últimas ocorrências.
// Ninguém lê isto sem a chave de admin (painel `/api/admin`, ações `bugs`).
//
// Proteções: tamanho máximo, limite por aparelho/hora, teto global por dia, chave de desligar
// (ERRORS_DISABLED=1) e modo "leve" para bug que já se repetiu demais (ver `_lib/error_store.js`).
// Custo no Redis (medido nos testes): ~23 comandos por evento (3 chamadas em lote); modo leve ~16.
'use strict';

const { config } = require('./_lib/config');
const { createCmd } = require('./_lib/store_cmd');
const { cleanReport } = require('./_lib/errors_lib');
const { checkLimits, storeReport } = require('./_lib/error_store');
const { notifyCritical } = require('./_lib/admin_push');

const MAX_BODY = 4096;

function makeHandler(deps = {}) {
  const fetchImpl = deps.fetch || globalThis.fetch;
  const getCfg = deps.config || (() => config());
  const clock = deps.now || Date.now;
  return async function handler(req, res) {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    const send = (code, obj) => { res.statusCode = code; res.end(JSON.stringify(obj)); };
    if (req.method !== 'POST') return send(405, { error: 'Use POST.' });

    const cfg = getCfg();
    if (cfg.errorsEnabled === false) return send(200, { ok: true, off: true }); // chave de desligar
    const m = createCmd(cfg, fetchImpl, { allowMemory: !!deps.allowMemory });
    if (!m.durable) return send(503, { error: 'sync_unavailable' });

    let b = req.body;
    if (typeof b === 'string') {
      if (b.length > MAX_BODY) return send(400, { error: 'Corpo grande demais.' });
      try { b = JSON.parse(b); } catch (_) { b = null; }
    }
    if (!b || typeof b !== 'object' || JSON.stringify(b).length > MAX_BODY) return send(400, { error: 'Corpo inválido.' });
    const r = cleanReport(b);
    if (!r) return send(400, { error: 'Relatório inválido.' });

    const now = clock();
    try {
      const lim = await checkLimits(m, cfg, now, r.id);
      if (!lim.ok) {
        return lim.dropped ? send(200, { ok: true, dropped: true }) : send(429, { error: 'Muitos relatórios deste aparelho. Tente mais tarde.' });
      }
      const status = await storeReport(m, now, r, (bug) => notifyCritical(cfg, fetchImpl, m, now, bug));
      return send(200, { ok: true, fp: r.fp, status });
    } catch (e) {
      if (String(e.message) === 'no-redis') return send(503, { error: 'sync_unavailable' });
      console.error('errors error', e && e.message);
      return send(200, { ok: false }); // relatório de erro nunca atrapalha o app
    }
  };
}

module.exports = makeHandler();
module.exports.makeHandler = makeHandler;
