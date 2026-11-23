// Livro dos pagamentos do Pix: cada Pix é um hash `pay:<id>` (c = perfil, p = plano, a = valor, t = criado, s = status do Mercado Pago,
// g = quando o Pro foi liberado, n = o que você recebeu líquido, f = a taxa, r = quando foi reembolsado). Os índices são listas:
// `pay:log` (todos, do mais antigo ao mais novo) e `pay:u:<perfil>` (os de cada professor).
//
// Regras que valem em todo lugar (aviso do Mercado Pago, tela do app e painel do admin):
//  - LIBERAR e REEMBOLSAR são idempotentes (HSETNX): o mesmo pagamento nunca soma nem tira dias duas vezes;
//  - o reembolso devolve o Pix inteiro e tira do "Pro até" só os dias DESSE pagamento;
//  - o próprio professor só reembolsa dentro de 7 dias da liberação (direito de arrependimento); o admin, a qualquer hora.
'use strict';

const pay = require('./pay');

const U = (code) => `u:${code}`;
const REC = (id) => `pay:${id}`;
const LOG = 'pay:log';
const MINE = (code) => `pay:u:${code}`;

/** Contador do dia (para o painel mostrar se o pagamento está saudável). Nunca derruba o pagamento se falhar. */
const STATS = ['new_ok', 'new_fail', 'hook_ok', 'hook_bad', 'refund_ok', 'refund_fail', 'grant'];
const dayKey = (nowMs) => new Date(nowMs - 3 * 3600000).toISOString().slice(0, 10).replace(/-/g, '');
async function stat(store, name, nowMs) {
  // um hash por dia (só informativo; uma leitura e uma escrita). Perder uma contagem em disputa não importa.
  try {
    const k = `pay:s:${dayKey(nowMs)}`;
    const n = (Number(await store.hget(k, name)) || 0) + 1;
    await store.hset(k, name, String(n));
    return n;
  } catch (_) { return 0; }
}
async function readStats(store, nowMs) {
  const out = {};
  for (const n of STATS) {
    try { out[n] = Number(await store.hget(`pay:s:${dayKey(nowMs)}`, n)) || 0; } catch (_) { out[n] = 0; }
  }
  try { out.lastHook = Number(await store.get('pay:lasthook')) || 0; } catch (_) { out.lastHook = 0; }
  return out;
}
async function touchHook(store, nowMs) {
  try { await store.set('pay:lasthook', String(nowMs), 30 * 86400); } catch (_) { /* só informativo */ }
}

/** Registra um Pix recém-criado e o põe nos índices. */
async function create(store, { id, code, plan, nowMs, status }) {
  const k = REC(id);
  await store.hset(k, 'c', code);
  await store.hset(k, 'p', plan.id);
  await store.hset(k, 'a', String(plan.amount));
  await store.hset(k, 't', String(nowMs));
  await store.hset(k, 's', status || 'pending');
  await store.push(LOG, id, 5000);
  await store.push(MINE(code), id, 50);
}

/**
 * Libera o Pro por um pagamento aprovado (só na primeira vez). Devolve true se liberou agora.
 * [got] é o que o Mercado Pago respondeu (valor, líquido e taxa).
 */
async function grant(store, id, code, plan, got, nowMs) {
  const k = REC(id);
  if (!(await store.hsetnx(k, 'g', String(nowMs)))) return false;
  await stat(store, 'grant', nowMs);
  if (got) {
    if (got.net != null) await store.hset(k, 'n', String(got.net));
    if (got.fee != null) await store.hset(k, 'f', String(got.fee));
  }
  const cur = await store.hget(U(code), 'pro');
  await store.hset(U(code), 'pro', String(pay.extendUntil(cur, plan, nowMs)));
  return true;
}

/** Marca o reembolso (só na primeira vez) e tira os dias deste pagamento. Devolve true se tirou agora. */
async function markRefunded(store, id, code, plan, nowMs) {
  const k = REC(id);
  if (!(await store.hsetnx(k, 'r', String(nowMs)))) return false;
  if (await store.hget(k, 'g')) {
    const cur = await store.hget(U(code), 'pro');
    await store.hset(U(code), 'pro', String(pay.revokeUntil(cur, plan, nowMs)));
  }
  return true;
}

/**
 * Reembolsa um pagamento pelo Mercado Pago. [admin] true ignora o prazo de 7 dias.
 * Devolve { ok } ou { error: 'not_found'|'not_paid'|'already'|'too_late'|'failed' }.
 */
async function refund(store, fetchImpl, cfg, id, { code, admin, nowMs }) {
  const rec = await store.hgetall(REC(id));
  if (!rec.c || (!admin && rec.c !== code)) return { error: 'not_found' };
  const plan = pay.planOf(rec.p);
  if (!plan || !rec.g) return { error: 'not_paid' };
  if (rec.r) return { error: 'already' };
  if (!admin && !pay.refundWindowOk(Number(rec.g), nowMs)) return { error: 'too_late' };
  // trava: dois pedidos ao mesmo tempo (clique duplo, ataque) nunca chamam o Mercado Pago duas vezes
  if (!(await store.hsetnx(REC(id), 'rl', String(nowMs)))) return { error: 'already' };
  try {
    await pay.refundPayment(fetchImpl, cfg, id, `refund-${id}`);
  } catch (e) {
    // o Mercado Pago pode já ter reembolsado antes (pelo painel dele): trata como feito
    if (!(e && e.status === 400 && /refund|reembols|already|status/i.test(String(e.detail || '')))) {
      await store.hdel(REC(id), 'rl'); // falhou: libera para tentar de novo
      await stat(store, 'refund_fail', nowMs);
      return { error: 'failed', detail: e && e.detail };
    }
  }
  await stat(store, 'refund_ok', nowMs);
  await store.hset(REC(id), 's', 'refunded');
  await markRefunded(store, id, rec.c, plan, nowMs);
  return { ok: true, code: rec.c };
}

/** A visão de um pagamento para mostrar (sem nada sensível). */
function view(id, rec, nowMs) {
  const plan = pay.planOf(rec.p);
  const g = Number(rec.g) || 0;
  const refunded = !!rec.r;
  return {
    id,
    plan: rec.p,
    name: plan ? plan.name : rec.p,
    amount: Number(rec.a) || 0,
    status: refunded ? 'refunded' : (rec.s || 'pending'),
    created: Number(rec.t) || 0,
    paid: g,
    net: rec.n != null && rec.n !== '' ? Number(rec.n) : null,
    fee: rec.f != null && rec.f !== '' ? Number(rec.f) : null,
    refunded: Number(rec.r) || 0,
    refundable: !!g && !refunded && pay.refundWindowOk(g, nowMs),
    code: rec.c,
  };
}

async function listMine(store, code, nowMs, n = 20) {
  const ids = [...new Set((await store.recent(MINE(code), n)).reverse())];
  const out = [];
  for (const id of ids) {
    const rec = await store.hgetall(REC(id));
    if (rec.c === code && (rec.g || rec.r)) out.push(view(id, rec, nowMs)); // só o que chegou a ser pago
  }
  return out;
}

async function listAll(store, nowMs, n = 100) {
  const ids = [...new Set((await store.recent(LOG, n)).reverse())];
  const out = [];
  for (const id of ids) {
    const rec = await store.hgetall(REC(id));
    if (rec.c) out.push(view(id, rec, nowMs)); // ignora o que sumiu
  }
  return out;
}

/** Soma de receita bruta, taxa e líquido dos pagamentos liberados (o reembolsado sai da conta). */
function summarize(list, nowMs, days = 30) {
  const since = nowMs - days * pay.DAY;
  const z = () => ({ count: 0, gross: 0, fee: 0, net: 0 });
  const all = z(), recent = z();
  let refundedCount = 0, refundedAmount = 0, pending = 0;
  const round = (n) => Math.round(n * 100) / 100;
  for (const p of list) {
    if (p.status === 'refunded' && p.paid) { refundedCount++; refundedAmount += p.amount; continue; }
    if (!p.paid) { if (p.status === 'pending') pending++; continue; }
    const fee = p.fee != null ? p.fee : p.amount * 0.0099;
    const net = p.net != null ? p.net : p.amount - fee;
    for (const t of [all, ...(p.paid >= since ? [recent] : [])]) { t.count++; t.gross += p.amount; t.fee += fee; t.net += net; }
  }
  const r = (t) => ({ count: t.count, gross: round(t.gross), fee: round(t.fee), net: round(t.net) });
  return { all: r(all), recent: r(recent), days, refundedCount, refundedAmount: round(refundedAmount), pending };
}

module.exports = { stat, readStats, touchHook, create, grant, markRefunded, refund, view, listMine, listAll, summarize, REC };
