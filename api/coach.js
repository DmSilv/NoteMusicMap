// Função da Vercel: POST /api/coach  (IA com vários serviços e fila)
//
// Recebe um RESUMO de números (nunca áudio) e um tipo de pedido, escolhe o serviço
// de IA certo (Gemini, OpenAI, Claude, Groq, Mistral, OpenRouter), respeita o limite
// de cada um com uma FILA JUSTA entre aparelhos e devolve o texto em português.
// As chaves ficam só nas variáveis de ambiente da Vercel; o app nunca as vê.
//
//   corpo:  { summary, kind?: session_summary|teacher_report|study_plan|question, ticket? }
//   200:    { text, provider, label, model, kind, remainingToday? }
//   429:    { error: queued|busy|cooldown|user_daily|daily_global, retryAfterMs, ticket?, position? }
//
// Regras (ver api/_lib/): router.js (quem atende cada tipo), queue.js (fila),
// store.js (contadores; Upstash Redis opcional), providers.js (adaptadores).
//
// Variáveis: geminiAPI, OPENAI_API_KEY, ANTHROPIC_API_KEY, GROQ_API_KEY,
// OPENROUTER_API_KEY, MISTRAL_API_KEY (as que existirem ficam ativas) e opcionais
// AI_PROVIDERS, AI_ROUTE_<TIPO>, AI_RPM_<SERVIÇO>, AI_USER_DAILY, AI_COOLDOWN_S,
// AI_RPD, AI_MAX_WAIT_MS, AI_TICKET_SECRET, MODEL_<SERVIÇO>_<FAST|SMART>.

'use strict';

const crypto = require('node:crypto');
const { config, LABELS } = require('./_lib/config');
const { createStore, memory } = require('./_lib/store');
const { callProvider, pickModels, finishText } = require('./_lib/providers');
const { PROMPTS } = require('./_lib/prompts');
const { KINDS, isKind, candidates, markBad } = require('./_lib/router');
const queue = require('./_lib/queue');

function clientIp(req) {
  const xf = String(req.headers['x-forwarded-for'] || '').split(',')[0].trim();
  return xf || (req.socket && req.socket.remoteAddress) || 'ip-desconhecido';
}

function who(req) {
  const dev = String(req.headers['x-device-id'] || '').replace(/[^A-Za-z0-9_-]/g, '').slice(0, 64);
  // Mistura o aparelho e o IP: trocar só o cabeçalho não zera o limite.
  return crypto.createHash('sha256').update(`${dev}|${clientIp(req)}`).digest('hex').slice(0, 24);
}

function readBody(req) {
  // Pedido grande demais nunca é do app: nem tenta ler.
  const len = Number(req.headers && req.headers['content-length']);
  if (Number.isFinite(len) && len > 20000) return null;
  if (typeof req.body === 'string' && req.body.length > 20000) return null;
  if (req.body && typeof req.body === 'object') return req.body;
  if (typeof req.body === 'string') {
    try { return JSON.parse(req.body); } catch (_) { return null; }
  }
  return null;
}

function cleanText(s) {
  return String(s)
    // eslint-disable-next-line no-control-regex
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, '')
    .trim();
}

function validate(body) {
  if (!body || typeof body.summary !== 'string') return { error: 'Corpo inválido: falta "summary".' };
  const summary = cleanText(body.summary);
  if (summary.length < 20) return { error: 'Resumo curto demais.' };
  if (summary.length > 8000) return { error: 'Resumo longo demais (máximo 8000 caracteres).' };
  const kind = body.kind == null ? 'session_summary' : String(body.kind);
  if (!isKind(kind)) return { error: 'Tipo de pedido desconhecido.' };
  const ticket = typeof body.ticket === 'string' ? body.ticket.slice(0, 120) : '';
  return { summary, kind, ticket };
}

function send(res, status, obj, extraHeaders = {}) {
  res.statusCode = status;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  for (const [k, v] of Object.entries(extraHeaders)) res.setHeader(k, v);
  res.end(JSON.stringify(obj));
}

const sleepReal = (ms) => new Promise((r) => setTimeout(r, ms));

function makeHandler(deps = {}) {
  const fetchImpl = deps.fetch || globalThis.fetch;
  const getCfg = deps.config || (() => config());
  const sleep = deps.sleep || sleepReal;
  const nowFn = deps.now || Date.now;

  return async function handler(req, res) {
    if (req.method !== 'POST') return send(res, 405, { error: 'Use POST.' }, { Allow: 'POST' });
    const cfg = getCfg();
    if (!Object.keys(cfg.keys).length) {
      return send(res, 503, { error: 'IA não configurada no servidor (falta a chave).' });
    }
    const v = validate(readBody(req));
    if (v.error) return send(res, 400, { error: v.error });

    const store = createStore(cfg, fetchImpl, nowFn);
    const id = who(req);
    const now = nowFn();
    const day = new Date(now).toISOString().slice(0, 10);

    const cand = await candidates(v.kind, cfg, store);
    if (!cand.ids.length) return send(res, 503, { error: 'Nenhum serviço de IA está ativo para este pedido.' });

    // ---- Admissão (só na primeira vez; quem volta com bilhete já foi admitido) ----
    const t = v.ticket ? queue.readTicket(cfg, id, v.ticket, now) : null;
    let remainingToday;
    if (!t) {
      const cd = await store.incr(`cd:${id}`, cfg.cooldownS);
      if (cd.n > 1) {
        return send(res, 429, { error: 'cooldown', retryAfterMs: cd.ttlMs }, { 'Retry-After': String(Math.ceil(cd.ttlMs / 1000)) });
      }
      const ud = await store.incr(`ud:${id}:${day}`, 86400);
      if (ud.n > cfg.userDaily) return send(res, 429, { error: 'user_daily', retryAfterMs: ud.ttlMs });
      const gd = await store.incr(`gd:${day}`, 86400);
      if (gd.n > cfg.rpd) return send(res, 429, { error: 'daily_global', retryAfterMs: gd.ttlMs });
      remainingToday = Math.max(0, cfg.userDaily - ud.n);
    }

    // ---- Fila: escolhe o serviço e o horário ----
    let order = cand.ids;
    let firstPaid = false; // o primeiro serviço já tem horário reservado
    if (t && cfg.keys[t.provider]) {
      const wait = t.slot - now;
      if (wait > 1500) {
        return send(res, 429, { error: 'queued', retryAfterMs: wait, ticket: v.ticket, provider: t.provider },
          { 'Retry-After': String(Math.ceil(wait / 1000)) });
      }
      order = [t.provider, ...cand.ids.filter((p) => p !== t.provider)];
      firstPaid = true;
    } else {
      let best = null;
      for (const pid of cand.ids) {
        const w = await queue.estimateWait(store, cfg, pid, now);
        if (w <= cfg.maxInlineWaitMs) { best = { pid, w }; break; }
        if (!best || w < best.w) best = { pid, w };
      }
      const c = await queue.claim(store, cfg, best.pid, now);
      if (c.waitMs > cfg.maxInlineWaitMs) {
        const position = Math.max(1, Math.ceil(c.waitMs / queue.intervalOf(cfg, best.pid)));
        return send(res, 429, {
          error: 'queued',
          retryAfterMs: c.waitMs,
          ticket: queue.makeTicket(cfg, id, best.pid, c.slot),
          position,
          provider: best.pid,
        }, { 'Retry-After': String(Math.ceil(c.waitMs / 1000)) });
      }
      if (c.waitMs > 0) await sleep(c.waitMs);
      order = [best.pid, ...cand.ids.filter((p) => p !== best.pid)];
      firstPaid = true;
    }

    // ---- Atendimento, trocando de serviço se um falhar ----
    const deadline = nowFn() + (deps.budgetMs || 50000);
    let failure = null;
    for (let i = 0; i < order.length; i++) {
      const pid = order[i];
      const left = deadline - nowFn();
      if (left < 4000) break;
      if (!(i === 0 && firstPaid)) {
        // outro serviço: só vale se a fila dele estiver curta
        const w = await queue.estimateWait(store, cfg, pid, nowFn());
        if (w > 3000) continue;
        const c = await queue.claim(store, cfg, pid, nowFn());
        if (c.waitMs > 0) await sleep(c.waitMs);
      }
      const r = await callProvider(pid, {
        key: cfg.keys[pid],
        tier: cand.tier,
        system: PROMPTS[v.kind],
        prompt: v.summary,
        maxTokens: cand.maxTokens,
        timeoutMs: Math.min(deps.timeoutMs || 25000, left - 1000),
        fetchImpl,
        env: cfg.env,
      });
      if (r.status === 'ok') {
        return send(res, 200, {
          text: finishText(r.text, r.truncated), truncated: !!r.truncated, provider: pid, label: LABELS[pid], model: r.model, kind: v.kind, remainingToday,
        });
      }
      console.error(`ia ${pid} falhou: ${r.status}${r.httpStatus ? ' ' + r.httpStatus : ''}`);
      await markBad(store, pid, r.status === 'ok' ? 'error' : r.status);
      failure = r;
    }
    if (failure && failure.status === 'busy') {
      return send(res, 429, { error: 'busy', retryAfterMs: failure.retryAfterMs || 15000 });
    }
    if (failure && failure.status === 'auth') {
      return send(res, 502, { error: 'Chave da API recusada pelo serviço de IA. Confira a variável na Vercel.' });
    }
    return send(res, failure && failure.aborted ? 504 : 502, { error: 'Nenhum serviço de IA conseguiu responder agora.' });
  };
}

module.exports = makeHandler();
module.exports.makeHandler = makeHandler;
module.exports._internal = { config, validate, cleanText, KINDS, PROMPTS, pickModels, memory };
