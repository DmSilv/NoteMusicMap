// POST /api/errors: relatório de erro do app (anônimo e sem dados pessoais).
//
// O app manda o que aconteceu (código, tela, detalhe já higienizado, versão, aparelho, trilha de
// telas). O servidor higieniza DE NOVO (nunca confia no app), agrupa o mesmo bug por impressão
// digital e guarda contadores, aparelhos afetados (distintos), tendência e as últimas ocorrências.
// Ninguém lê isto sem a chave de admin (painel `/api/admin`, ações `bugs`).
//
// Proteções: tamanho máximo, limite por aparelho/hora, teto global por dia, chave de desligar
// (ERRORS_DISABLED=1) e modo "leve" para bug que já se repetiu demais.
// Custo no Redis (medido nos testes): ~23 comandos por evento (3 chamadas em lote); modo leve ~16.
'use strict';

const crypto = require('node:crypto');
const { config } = require('./_lib/config');
const { createCmd } = require('./_lib/store_cmd');
const { cleanReport, day, hour, K } = require('./_lib/errors_lib');

const MAX_BODY = 4096;
const PER_DEVICE_HOUR = 10;
const LIGHT_AFTER = 200; // depois de tantas repetições, só os contadores

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
    const d = day(now);
    try {
      // 1) Limites: por aparelho (por hora) e global (por dia).
      const hk = K.rateDevice(crypto.createHash('sha256').update(r.id).digest('hex').slice(0, 16), Math.floor(now / 3600000));
      const gk = K.rateGlobal(d);
      const [dev, , glob] = await m.pipeline([['INCR', hk], ['EXPIRE', hk, '3600', 'NX'], ['INCR', gk], ['EXPIRE', gk, '90000', 'NX']]);
      if (Number(dev) > PER_DEVICE_HOUR) return send(429, { error: 'Muitos relatórios deste aparelho. Tente mais tarde.' });
      if (Number(glob) > (cfg.errorsDailyCap || 150)) return send(200, { ok: true, dropped: true }); // teto do dia

      // 2) Estado atual do bug (status, quantas vezes já veio, se foi resolvido e quando).
      // A versão (build) é registrada antes, para a "primeira vez vista" valer já neste evento.
      const [cur, resolvedRaw, , firstSeenRaw] = await m.pipeline([
        ['HMGET', K.bug(r.fp), 'st', 'n'], ['HGET', K.resolved, r.fp],
        ['HSETNX', K.builds, r.v, String(now)], ['HGET', K.builds, r.v],
      ]);
      const [status, nRaw] = cur || [];
      const n = Number(nRaw) || 0;
      const light = n >= LIGHT_AFTER;

      // Reabre se estava resolvido e veio de uma versão publicada DEPOIS da correção.
      let nextStatus = status || 'new';
      if (status === 'resolved') {
        let at = 0;
        try { at = Number(JSON.parse(resolvedRaw || '{}').at) || 0; } catch (_) { /* ruim */ }
        const firstSeen = Number(firstSeenRaw) || 0;
        if (firstSeen && at && firstSeen > at) nextStatus = 'reopened';
      }

      // 3) Grava (em lote).
      const list = [
        ['HINCRBY', K.bug(r.fp), 'n', '1'],
        ['HINCRBY', K.daily(d), 'total', '1'],
        ['HINCRBY', K.daily(d), r.s, '1'],
        ['HINCRBY', K.daily(d), `h${hour(now)}`, '1'],
        ['HINCRBY', K.trend(r.fp), d, '1'],
        ['ZADD', K.idx, String(now), r.fp],
      ];
      if (!light) {
        list.push(
          ['HSETNX', K.bug(r.fp), 'first', String(now)],
          ['HSET', K.bug(r.fp), 'last', String(now), 'c', r.c, 's', r.s, 'w', r.w, 'msg', r.d],
          ['HINCRBY', K.bug(r.fp), `v:${r.v}`, '1'],
          ['HINCRBY', K.bug(r.fp), `p:${r.pl}`, '1'],
          ['HINCRBY', K.bug(r.fp), `i:${r.in}`, '1'],
          ['PFADD', K.devices(r.fp), r.id],
          ['LPUSH', K.recent(r.fp), JSON.stringify({
            t: now, v: r.v, pl: r.pl, in: r.in, lk: r.lk, vw: r.vw, bc: r.bc,
            dv: crypto.createHash('sha256').update(r.id).digest('hex').slice(0, 8),
          })],
          ['LTRIM', K.recent(r.fp), '0', '9'],
        );
      }
      if (nextStatus !== status) list.push(['HSET', K.bug(r.fp), 'st', nextStatus]);
      await m.pipeline(list);
      return send(200, { ok: true, fp: r.fp, status: nextStatus });
    } catch (e) {
      if (String(e.message) === 'no-redis') return send(503, { error: 'sync_unavailable' });
      console.error('errors error', e && e.message);
      return send(200, { ok: false }); // relatório de erro nunca atrapalha o app
    }
  };
}

module.exports = makeHandler();
module.exports.makeHandler = makeHandler;
