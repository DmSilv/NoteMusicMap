'use strict';
// FILA JUSTA entre aparelhos: cada serviço de IA tem um limite de pedidos por
// minuto; cada pedido RESERVA o próximo horário livre ("slot"), na ordem de
// chegada. Se o horário está perto, o servidor espera e atende; se está longe,
// devolve um BILHETE assinado ("volte neste horário") e o aparelho mantém o lugar
// na fila em vez de tentar de novo às cegas. Funciona entre instâncias quando o
// Redis está configurado.

const crypto = require('node:crypto');

const qKey = (provider) => `q:${provider}`;
const intervalOf = (cfg, provider) => Math.ceil(60000 / (cfg.rpm[provider] || 10));

/** Quanto tempo (ms) um pedido novo esperaria agora neste serviço. */
async function estimateWait(store, cfg, provider, now) {
  const last = await store.lastSlot(qKey(provider));
  return Math.max(0, last + intervalOf(cfg, provider) - now);
}

/** Reserva o próximo horário do serviço e devolve {slot, waitMs}. */
async function claim(store, cfg, provider, now) {
  const slot = await store.claimSlot(qKey(provider), now, intervalOf(cfg, provider));
  return { slot, waitMs: Math.max(0, slot - now) };
}

function sign(cfg, who, provider, slot) {
  return crypto.createHmac('sha256', cfg.ticketSecret).update(`${who}|${provider}|${slot}`).digest('hex').slice(0, 16);
}

/** Bilhete: "serviço.horário.assinatura". */
function makeTicket(cfg, who, provider, slot) {
  return `${provider}.${slot}.${sign(cfg, who, provider, slot)}`;
}

/** Lê e confere um bilhete; null se inválido, de outra pessoa ou velho demais. */
function readTicket(cfg, who, ticket, now) {
  const m = /^([a-z]+)\.(\d{10,16})\.([0-9a-f]{16})$/.exec(String(ticket || ''));
  if (!m) return null;
  const [, provider, slotStr, sig] = m;
  const slot = Number(slotStr);
  if (sig !== sign(cfg, who, provider, slot)) return null;
  if (now - slot > 90000 || slot - now > 180000) return null; // venceu ou é do futuro distante
  return { provider, slot };
}

module.exports = { estimateWait, claim, makeTicket, readTicket, intervalOf };
