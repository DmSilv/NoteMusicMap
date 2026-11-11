// Gravação dos relatórios de erro no Redis (usada pelo endpoint do app e pelos erros do próprio
// servidor). Limites, agrupamento por impressão digital, reabertura e modo leve num só lugar.
'use strict';

const crypto = require('node:crypto');
const { createCmd } = require('./store_cmd');
const { cleanReport, day, hour, K, sanitize } = require('./errors_lib');
const { notifyCritical } = require('./admin_push');

const PER_DEVICE_HOUR = 10;
const LIGHT_AFTER = 200; // depois de tantas repetições, só os contadores
const SERVER_ID = 'servidor00000000'; // "aparelho" dos erros do próprio servidor

/** Limites: por aparelho (por hora) e global (por dia). Devolve { ok, status, dropped }. */
async function checkLimits(m, cfg, now, deviceId) {
  const hk = K.rateDevice(crypto.createHash('sha256').update(deviceId).digest('hex').slice(0, 16), Math.floor(now / 3600000));
  const gk = K.rateGlobal(day(now));
  const [dev, , glob] = await m.pipeline([['INCR', hk], ['EXPIRE', hk, '3600', 'NX'], ['INCR', gk], ['EXPIRE', gk, '90000', 'NX']]);
  if (Number(dev) > PER_DEVICE_HOUR) return { ok: false, status: 429 };
  if (Number(glob) > (cfg.errorsDailyCap || 150)) return { ok: false, status: 200, dropped: true };
  return { ok: true };
}

/**
 * Grava o relatório [r] (já limpo por `cleanReport`). Devolve o status do bug.
 * [onCritical] (opcional) é chamado quando um bug GRAVE aparece pela primeira vez ou é reaberto.
 */
async function storeReport(m, now, r, onCritical) {
  const d = day(now);
  // A versão (build) é registrada antes, para a "primeira vez vista" valer já neste evento.
  const [cur, resolvedRaw, , firstSeenRaw] = await m.pipeline([
    ['HMGET', K.bug(r.fp), 'st', 'n'], ['HGET', K.resolved, r.fp],
    ['HSETNX', K.builds, r.v, String(now)], ['HGET', K.builds, r.v],
  ]);
  const [status, nRaw] = cur || [];
  const light = (Number(nRaw) || 0) >= LIGHT_AFTER;

  // Reabre se estava resolvido e veio de uma versão publicada DEPOIS da correção.
  let nextStatus = status || 'new';
  if (status === 'resolved') {
    let at = 0;
    try { at = Number(JSON.parse(resolvedRaw || '{}').at) || 0; } catch (_) { /* ruim */ }
    const firstSeen = Number(firstSeenRaw) || 0;
    if (firstSeen && at && firstSeen > at) nextStatus = 'reopened';
  }

  const list = [
    ['HINCRBY', K.bug(r.fp), 'n', '1'],
    ['HINCRBY', K.daily(d), 'total', '1'],
    ['HINCRBY', K.daily(d), r.s, '1'],
    ['HINCRBY', K.daily(d), `h${hour(now)}`, '1'],
    ['HINCRBY', K.trend(r.fp), d, '1'],
    ['ZADD', K.idx, String(now), r.fp],
  ];
  if (r.pl === 'server') list.push(['HINCRBY', K.daily(d), 'srv', '1']);
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
  if (onCritical && r.s === 'critical' && (!status || (nextStatus === 'reopened' && status !== 'reopened'))) {
    await onCritical({ fp: r.fp, c: r.c, w: r.w, reopened: nextStatus === 'reopened' });
  }
  return nextStatus;
}

/**
 * Um erro do PRÓPRIO servidor (falha no vínculo, no painel...) entra no mesmo painel de bugs, como
 * plataforma "server". Nunca lança: registrar erro não pode causar outro.
 */
async function serverError(deps, endpoint, error) {
  try {
    const cfg = deps.cfg;
    if (cfg.errorsEnabled === false) return;
    const m = createCmd(cfg, deps.fetchImpl, { allowMemory: !!deps.allowMemory });
    if (!m.durable) return;
    const r = cleanReport({
      id: SERVER_ID, c: 'API-05', s: 'action', w: `API ${endpoint}`,
      d: sanitize(`${(error && error.name) || 'Error'}: ${(error && error.message) || ''}`),
      v: 'server', pl: 'server', in: 'app',
    });
    if (!r) return;
    const now = deps.clock();
    const lim = await checkLimits(m, cfg, now, SERVER_ID);
    if (!lim.ok) return;
    await storeReport(m, now, r, (bug) => notifyCritical(cfg, deps.fetchImpl, m, now, bug));
  } catch (_) { /* silencioso */ }
}

module.exports = { checkLimits, storeReport, serverError, SERVER_ID };
