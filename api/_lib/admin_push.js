// Aviso (Web Push) para o administrador quando aparece um bug GRAVE novo (ou um grave reaberto).
// As inscrições do navegador do admin ficam em `adm:ps` (feitas no painel, com a chave de admin).
// Custo: zero quando não há bug grave novo; num bug grave novo, ~3 comandos + 1 envio por aparelho.
// Falhar aqui nunca pode atrapalhar quem reportou o erro: tudo é silencioso.
'use strict';

const crypto = require('node:crypto');
const { sendPush, validSubscription } = require('./webpush');

const KEY = 'adm:ps'; // hash: campo (hash do endereço) -> JSON da inscrição (+ t)
const MAX_DEVICES = 5;
const MAX_PER_HOUR = 6; // no máximo 6 avisos de bug por hora (um bug em loop não vira spam)

const fieldOf = (endpoint) => crypto.createHash('sha256').update(String(endpoint)).digest('hex').slice(0, 24);
const enabled = (cfg) => !!(cfg && cfg.vapid && cfg.vapid.publicKey && cfg.vapid.privateKey);

/** Lê as inscrições [campo, inscrição] do hash (lista plana do Redis). */
function parseSubs(flat) {
  const out = [];
  for (let i = 0; i + 1 < (flat || []).length; i += 2) {
    let sub = null;
    try { sub = validSubscription(JSON.parse(flat[i + 1])); } catch (_) { /* ruim */ }
    out.push([String(flat[i]), sub]);
  }
  return out;
}

/** Envia [payload] a todos os aparelhos do admin; apaga inscrições que não existem mais. Devolve quantos receberam. */
async function broadcast(cfg, fetchImpl, cmd, payload, now) {
  const subs = parseSubs(await cmd.cmd(['HGETALL', KEY]));
  let sent = 0;
  for (const [field, sub] of subs) {
    if (!sub) { await cmd.cmd(['HDEL', KEY, field]); continue; }
    const r = await sendPush(sub, payload, cfg.vapid, fetchImpl, Math.floor(now / 1000));
    if (r.ok) sent++;
    else if (r.gone) await cmd.cmd(['HDEL', KEY, field]);
  }
  return sent;
}

/**
 * Bug grave novo ou reaberto: avisa o admin. [bug] = { fp, c, w, reopened }.
 * Limite: MAX_PER_HOUR avisos por hora no total.
 */
async function notifyCritical(cfg, fetchImpl, cmd, now, bug) {
  try {
    if (!enabled(cfg)) return 0;
    const hk = `adm:pn:${Math.floor(now / 3600000)}`;
    const [n] = await cmd.pipeline([['INCR', hk], ['EXPIRE', hk, '3600', 'NX']]);
    if (Number(n) > MAX_PER_HOUR) return 0;
    const where = String(bug.w || '').slice(0, 80);
    return await broadcast(cfg, fetchImpl, cmd, {
      kind: 'admin',
      body: `${bug.reopened ? 'Bug grave reaberto' : 'Bug grave novo'}: ${bug.c}${where ? ' · ' + where : ''}`,
      tag: bug.fp,
    }, now);
  } catch (_) { return 0; }
}

module.exports = { KEY, MAX_DEVICES, MAX_PER_HOUR, fieldOf, enabled, broadcast, notifyCritical };
