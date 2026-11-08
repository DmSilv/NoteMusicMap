// POST /api/feedback: nota do app e respostas das pesquisas rápidas (anônimas).
// GET  /api/feedback: resumo para o dono do app (exige FEEDBACK_ADMIN_KEY).
//
// Privacidade: guarda só a resposta, a versão e um código do aparelho EMBARALHADO
// (hash). Nada de nome, e-mail, IP ou áudio. Sem Redis, as respostas só duram na
// memória da instância (e vão para o log da Vercel); com Upstash Redis ficam guardadas.
'use strict';

const crypto = require('node:crypto');
const { config } = require('./_lib/config');
const { createStore } = require('./_lib/store');

const LIST_KEY = 'fb:v1';
const DAILY_LIMIT = 30; // envios por aparelho+IP por dia

function clientIp(req) {
  const xf = String(req.headers['x-forwarded-for'] || '').split(',')[0].trim();
  return xf || (req.socket && req.socket.remoteAddress) || 'ip-desconhecido';
}

function deviceOf(req) {
  return String(req.headers['x-device-id'] || '').replace(/[^A-Za-z0-9_-]/g, '').slice(0, 64);
}

const sha = (s) => crypto.createHash('sha256').update(s).digest('hex');

function readBody(req) {
  // Pedido grande demais nunca é do app: nem tenta ler.
  const len = Number(req.headers && req.headers['content-length']);
  if (Number.isFinite(len) && len > 4096) return null;
  if (typeof req.body === 'string' && req.body.length > 4096) return null;
  if (req.body && typeof req.body === 'object') return req.body;
  if (typeof req.body === 'string') {
    try { return JSON.parse(req.body); } catch (_) { return null; }
  }
  return null;
}

/** Tira caracteres de controle, corta o tamanho. */
function clean(v, max) {
  return String(v == null ? '' : v).replace(/[\u0000-\u001f\u007f]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, max);
}

/** Valida e normaliza o pedido; devolve { rec } ou { error }. */
function parse(body, deviceHash, now) {
  if (!body || typeof body !== 'object') return { error: 'Corpo inválido.' };
  const kind = body.kind === 'rating' ? 'rating' : body.kind === 'survey' ? 'survey' : '';
  if (!kind) return { error: 'Tipo inválido.' };
  const rec = { t: new Date(now).toISOString(), d: deviceHash, k: kind, v: clean(body.version, 40), p: clean(body.platform, 20) };
  if (kind === 'rating') {
    const r = Number(body.rating);
    if (!Number.isInteger(r) || r < 1 || r > 5) return { error: 'A nota vai de 1 a 5.' };
    rec.r = r;
    const c = clean(body.comment, 500);
    if (c) rec.c = c;
  } else {
    const q = clean(body.qid, 32);
    if (!/^[a-z0-9_]{1,32}$/.test(q)) return { error: 'Pergunta inválida.' };
    const a = clean(body.answer, 300);
    if (!a) return { error: 'Resposta vazia.' };
    rec.q = q;
    rec.a = a;
  }
  return { rec };
}

/** Resumo: média e distribuição das notas (última nota de cada aparelho) e respostas por pergunta. */
function summarize(rows) {
  const lastRating = new Map();
  const surveys = {};
  const comments = [];
  for (const r of rows) {
    if (r.k === 'rating') {
      lastRating.set(r.d, r);
    } else if (r.k === 'survey') {
      const s = (surveys[r.q] ||= { total: 0, answers: {}, lastText: [] });
      const seen = (s._seen ||= new Set());
      if (seen.has(r.d)) continue; // uma resposta por aparelho
      seen.add(r.d);
      s.total += 1;
      s.answers[r.a.length <= 40 ? r.a : 'outro (texto)'] = (s.answers[r.a.length <= 40 ? r.a : 'outro (texto)'] || 0) + 1;
      if (r.a.length > 40) s.lastText.push({ t: r.t, a: r.a });
    }
  }
  const hist = { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0 };
  let sum = 0;
  for (const r of lastRating.values()) {
    hist[r.r] += 1;
    sum += r.r;
    if (r.c) comments.push({ t: r.t, r: r.r, c: r.c, v: r.v });
  }
  const n = lastRating.size;
  for (const s of Object.values(surveys)) {
    delete s._seen;
    s.lastText = s.lastText.slice(-20);
  }
  comments.sort((a, b) => (a.t < b.t ? 1 : -1));
  return {
    rating: { count: n, average: n ? Math.round((sum / n) * 100) / 100 : null, histogram: hist },
    comments: comments.slice(0, 20),
    surveys,
    totalRecords: rows.length,
  };
}

function makeHandler(deps = {}) {
  const fetchImpl = deps.fetch || globalThis.fetch;
  const getCfg = deps.config || (() => config());
  const clock = deps.now || Date.now;
  return async function handler(req, res) {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.setHeader('Cache-Control', 'no-store');
    const cfg = getCfg();
    const store = createStore(cfg, fetchImpl, clock);

    if (req.method === 'GET') {
      if (!cfg.feedbackKey) {
        res.statusCode = 404;
        return res.end(JSON.stringify({ error: 'Não configurado.' }));
      }
      const given = String(req.headers.authorization || '').replace(/^Bearer\s+/i, '');
      const ok = crypto.timingSafeEqual(Buffer.from(sha(given)), Buffer.from(sha(cfg.feedbackKey)));
      if (!ok) {
        res.statusCode = 401;
        return res.end(JSON.stringify({ error: 'Chave inválida.' }));
      }
      const rows = [];
      for (const line of await store.recent(LIST_KEY, 5000)) {
        try { rows.push(JSON.parse(line)); } catch (_) { /* linha ruim */ }
      }
      res.statusCode = 200;
      return res.end(JSON.stringify({ shared: store.redis, ...summarize(rows) }));
    }

    if (req.method !== 'POST') {
      res.statusCode = 405;
      return res.end(JSON.stringify({ error: 'Use POST.' }));
    }

    const dev = deviceOf(req);
    if (!dev) {
      res.statusCode = 400;
      return res.end(JSON.stringify({ error: 'Aparelho não identificado.' }));
    }
    const day = Math.floor(clock() / 86400000);
    const limiter = await store.incr(`fblim:${sha(dev + '|' + clientIp(req)).slice(0, 24)}:${day}`, 86400);
    if (limiter.n > DAILY_LIMIT) {
      res.statusCode = 429;
      return res.end(JSON.stringify({ error: 'Muitos envios hoje. Tente amanhã.' }));
    }

    const deviceHash = sha('fb|' + dev).slice(0, 16);
    const { rec, error } = parse(readBody(req), deviceHash, clock());
    if (error) {
      res.statusCode = 400;
      return res.end(JSON.stringify({ error }));
    }
    await store.push(LIST_KEY, JSON.stringify(rec));
    console.log('feedback', JSON.stringify(rec)); // também no log da Vercel (sobrevive sem Redis)
    res.statusCode = 200;
    res.end(JSON.stringify({ ok: true }));
  };
}

module.exports = makeHandler();
module.exports.makeHandler = makeHandler;
module.exports._internal = { parse, summarize, clean };
