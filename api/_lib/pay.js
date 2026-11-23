// Pagamento do plano Pro do professor por Pix (Mercado Pago, Checkout API). TUDO DESLIGADO por padrão: sem PAY_ENABLED=1 nada responde.
//
// Modelo: Pix avulso por período (sem renovação automática). O professor paga 30 dias (mensal) ou 365 dias (anual); o servidor soma
// o período a "Pro até" na conta quando o Mercado Pago avisa que o Pix foi aprovado. O mesmo pagamento NUNCA conta duas vezes.
//
// Este arquivo é a regra de negócio: sem rede própria (o fetch entra por parâmetro) e testável sem credenciais.
// Variáveis (só na Vercel, nunca no código nem no chat): PAY_ENABLED, MP_ACCESS_TOKEN, MP_WEBHOOK_SECRET, PAY_PUBLIC_URL (opcional).
'use strict';

const crypto = require('node:crypto');

const DAY = 86400000;

/** Planos à venda. Valores em reais; [days] é quanto soma a "Pro até". */
const PLANS = {
  m: { id: 'm', name: 'Pro Professor · mensal', amount: 14.9, days: 30 },
  y: { id: 'y', name: 'Pro Professor · anual', amount: 149, days: 365 },
};

/** O professor usa de graça até este número de alunos; o Pro tira o limite. */
const FREE_STUDENTS = 3;

/** Quanto o Pix fica aberto para pagar (minutos). */
const PIX_MINUTES = 30;

const MP_API = 'https://api.mercadopago.com';

function payConfig(env = process.env) {
  const t = (v) => String(v || '').trim();
  return {
    enabled: t(env.PAY_ENABLED) === '1',
    token: t(env.MP_ACCESS_TOKEN),
    secret: t(env.MP_WEBHOOK_SECRET),
    publicUrl: t(env.PAY_PUBLIC_URL) || 'https://notemusicmap.vercel.app',
  };
}

/** Pode vender? Ligado por chave E com as duas credenciais. */
const ready = (c) => !!(c && c.enabled && c.token && c.secret);

const planOf = (id) => (Object.prototype.hasOwnProperty.call(PLANS, id) ? PLANS[id] : null);

/** Nova data de "Pro até": soma o período ao que sobrou (renovar antes de vencer não perde dias). */
function extendUntil(currentUntilMs, plan, nowMs) {
  const base = Math.max(Number(currentUntilMs) || 0, nowMs);
  return base + plan.days * DAY;
}

/** O plano da conta agora: { pro, until, daysLeft }. */
function statusOf(untilMs, nowMs) {
  const until = Number(untilMs) || 0;
  const pro = until > nowMs;
  return { pro, until: pro ? until : 0, daysLeft: pro ? Math.ceil((until - nowMs) / DAY) : 0 };
}

/**
 * Confere a assinatura do aviso (webhook) do Mercado Pago. Cabeçalho x-signature: "ts=...,v1=...".
 * Texto assinado: "id:<data.id>;request-id:<x-request-id>;ts:<ts>;" (parte ausente fica de fora; o id alfanumérico vai em minúsculas).
 * Devolve true só se o HMAC-SHA256 com o segredo bater, em tempo constante.
 */
function verifySignature({ signature, requestId, dataId, secret }) {
  if (!secret || typeof signature !== 'string' || signature.length > 400) return false;
  let ts = '', v1 = '';
  for (const part of signature.split(',')) {
    const i = part.indexOf('=');
    if (i < 0) continue;
    const k = part.slice(0, i).trim();
    const v = part.slice(i + 1).trim();
    if (k === 'ts') ts = v;
    else if (k === 'v1') v1 = v;
  }
  if (!ts || !/^[0-9a-f]{64}$/i.test(v1)) return false;
  let manifest = '';
  if (dataId != null && String(dataId) !== '') {
    const id = String(dataId);
    manifest += `id:${/^[A-Za-z0-9]+$/.test(id) ? id.toLowerCase() : id};`;
  }
  if (requestId) manifest += `request-id:${requestId};`;
  manifest += `ts:${ts};`;
  const want = crypto.createHmac('sha256', secret).update(manifest).digest('hex');
  const a = Buffer.from(want, 'hex');
  const b = Buffer.from(v1.toLowerCase(), 'hex');
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

/** external_reference: liga o pagamento ao perfil e ao plano ("CODIGO|m"). */
const refOf = (code, planId) => `${code}|${planId}`;
function parseRef(ref) {
  const [code, planId] = String(ref || '').split('|');
  const plan = planOf(planId);
  return code && plan ? { code, plan } : null;
}

const iso = (ms) => {
  // Mercado Pago pede data com fuso (-03:00 no Brasil).
  const d = new Date(ms - 3 * 3600000);
  return d.toISOString().replace('Z', '-03:00');
};

async function mp(fetchImpl, cfg, method, path, body, extraHeaders = {}) {
  const r = await fetchImpl(MP_API + path, {
    method,
    headers: { Authorization: `Bearer ${cfg.token}`, 'Content-Type': 'application/json', ...extraHeaders },
    body: body ? JSON.stringify(body) : undefined,
  });
  let j = null;
  try { j = await r.json(); } catch (_) { j = null; }
  if (!r.ok) {
    const err = new Error('mp ' + r.status);
    err.status = r.status;
    err.detail = j && (j.message || j.error) ? String(j.message || j.error).slice(0, 200) : '';
    throw err;
  }
  return j;
}

/**
 * Cria o Pix. [idem] é a chave de idempotência (a mesma tentativa nunca gera dois Pix).
 * Devolve { id, status, qr, qrBase64, expires, ticketUrl }.
 */
async function createPix(fetchImpl, cfg, { code, plan, idem, nowMs, payerEmail }) {
  const j = await mp(fetchImpl, cfg, 'POST', '/v1/payments', {
    transaction_amount: plan.amount,
    description: plan.name,
    payment_method_id: 'pix',
    external_reference: refOf(code, plan.id),
    notification_url: `${cfg.publicUrl}/api/account?mp=hook`,
    date_of_expiration: iso(nowMs + PIX_MINUTES * 60000),
    payer: { email: payerEmail },
  }, { 'X-Idempotency-Key': idem });
  const td = (j.point_of_interaction && j.point_of_interaction.transaction_data) || {};
  return { id: String(j.id), status: String(j.status || 'pending'), qr: td.qr_code || '', qrBase64: td.qr_code_base64 || '', ticketUrl: td.ticket_url || '', expires: j.date_of_expiration || '' };
}

/** Consulta um pagamento (para o aviso e para a tela conferir). */
async function getPayment(fetchImpl, cfg, id) {
  const j = await mp(fetchImpl, cfg, 'GET', `/v1/payments/${encodeURIComponent(String(id))}`);
  return {
    id: String(j.id),
    status: String(j.status || ''),
    amount: Number(j.transaction_amount) || 0,
    ref: String(j.external_reference || ''),
    method: String(j.payment_method_id || ''),
  };
}

module.exports = { PLANS, FREE_STUDENTS, PIX_MINUTES, DAY, payConfig, ready, planOf, extendUntil, statusOf, verifySignature, refOf, parseRef, createPix, getPayment };
