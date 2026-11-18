// Pesquisas do app: o administrador cria, libera e retira no painel; o app só LÊ a pesquisa ativa
// (GET /api/feedback?survey=1, com cache de CDN, como o boletim em /api/news).
//
// Dados:
//   sv:items  hash  id -> JSON {t, te, qs, st, from, to, c, u, p, h, k}
//     t/te    título em português / inglês (opcional)
//     qs      perguntas: {id, k: 'choice'|'text', q, qe, o: [{v, e}], r: obrigatória}
//     st      "draft" (rascunho) | "live" (liberada) | "off" (encerrada; continua no histórico)
//     from/to quando liberar / quando retirar (ms; 0 = sem data). Só valem com st = "live".
//     c/u/p   criada, alterada e liberada por último (ms)
//     h       histórico [{t, e, n?}] (os últimos 30 eventos)
//     k       chave do modelo pronto de onde veio (para o app reconhecer quem já respondeu a versão antiga)
// Nada vai ao app sozinho: só "live" dentro da janela from..to.
'use strict';

const crypto = require('node:crypto');

const HASH = 'sv:items';
const MAX_ITEMS = 40;
const MAX_TITLE = 60;
const MAX_QUESTIONS = 6;
const MAX_Q = 120;
const MAX_OPTIONS = 8;
const MAX_OPTION = 40; // até 40 caracteres a resposta conta como opção no resumo (acima disso, é texto livre)
const MAX_HISTORY = 30;
const STATES = ['draft', 'live', 'off'];
const MONTH_MAX = 3; // participações por aparelho por mês
const SEED_KEY = 'rapida';

const newId = () => crypto.randomBytes(5).toString('hex');
const validId = (id) => typeof id === 'string' && /^[0-9a-f]{10}$/.test(id);

function clean(v, max) {
  return String(v == null ? '' : v).replace(/[\u0000-\u001f\u007f]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, max);
}

/** Valida o que veio do painel; devolve { v } ou { error }. `id` ajuda a gerar ids de pergunta únicos. */
function validate(b, id) {
  const t = clean(b && b.t, MAX_TITLE);
  if (!t) return { error: 'Falta o título da pesquisa.' };
  const raw = Array.isArray(b.qs) ? b.qs : [];
  if (!raw.length) return { error: 'Inclua pelo menos uma pergunta.' };
  if (raw.length > MAX_QUESTIONS) return { error: `O limite é ${MAX_QUESTIONS} perguntas.` };
  const qs = [];
  const used = new Set();
  for (let i = 0; i < raw.length; i++) {
    const x = raw[i] || {};
    const q = clean(x.q, MAX_Q);
    if (!q) return { error: `Falta o texto da pergunta ${i + 1}.` };
    const k = x.k === 'text' ? 'text' : 'choice';
    let qid = clean(x.id, 32).toLowerCase();
    if (!/^[a-z0-9_]{1,32}$/.test(qid) || used.has(qid)) qid = `${id || 'n'}_${i + 1}`;
    used.add(qid);
    const item = { id: qid, k, q, qe: clean(x.qe, MAX_Q), r: x.r === true };
    if (k === 'choice') {
      const o = [];
      for (const y of Array.isArray(x.o) ? x.o : []) {
        const v = clean(y && typeof y === 'object' ? y.v : y, MAX_OPTION);
        if (v && !o.some((z) => z.v === v)) o.push({ v, e: clean(y && typeof y === 'object' ? y.e : '', MAX_OPTION) });
      }
      if (o.length < 2) return { error: `A pergunta ${i + 1} precisa de pelo menos 2 opções.` };
      if (o.length > MAX_OPTIONS) return { error: `O limite é ${MAX_OPTIONS} opções por pergunta.` };
      item.o = o;
    }
    qs.push(item);
  }
  const from = Math.max(0, Math.round(Number(b.from)) || 0);
  const to = Math.max(0, Math.round(Number(b.to)) || 0);
  if (from && to && to <= from) return { error: 'A data de retirar precisa ser depois da data de liberar.' };
  return { v: { t, te: clean(b.te, MAX_TITLE), qs, from, to } };
}

function parse(raw) {
  try {
    const j = JSON.parse(raw);
    if (!j || typeof j !== 'object' || !Array.isArray(j.qs)) return null;
    return {
      t: String(j.t || ''), te: String(j.te || ''), qs: j.qs,
      st: STATES.includes(j.st) ? j.st : 'draft', from: Number(j.from) || 0, to: Number(j.to) || 0,
      c: Number(j.c) || 0, u: Number(j.u) || 0, p: Number(j.p) || 0, k: String(j.k || ''),
      h: Array.isArray(j.h) ? j.h.slice(-MAX_HISTORY) : [],
    };
  } catch (_) { return null; }
}

/** O que vale agora: draft | scheduled (liberada, mas ainda não chegou a data) | active | closed (encerrada ou data de retirar vencida). */
function status(it, now) {
  if (it.st === 'draft') return 'draft';
  if (it.st === 'off') return 'closed';
  if (it.from && now < it.from) return 'scheduled';
  if (it.to && now >= it.to) return 'closed';
  return 'active';
}

const addHistory = (it, e, now, n) => [...it.h, { t: now, e, ...(n ? { n } : {}) }].slice(-MAX_HISTORY);

/** Tudo (rascunhos, liberadas, encerradas), do mais novo ao mais antigo, com o estado de agora. 1 comando. */
async function listAll(store, now) {
  const all = await store.hgetall(HASH);
  const out = [];
  for (const [id, raw] of Object.entries(all || {})) {
    const it = parse(raw);
    if (it && (validId(id) || id === SEED_KEY)) out.push({ id, ...it, status: status(it, now) });
  }
  return out.sort((a, b) => Math.max(b.p, b.u, b.c) - Math.max(a.p, a.u, a.c));
}

/** O que o app recebe: só a pesquisa ativa (a liberada mais recentemente), sem dado interno. */
function publicSurvey(all) {
  const act = all.filter((i) => i.status === 'active').sort((a, b) => Math.max(b.from, b.p) - Math.max(a.from, a.p))[0];
  if (!act) return null;
  return {
    id: act.id, t: act.t, ...(act.te ? { te: act.te } : {}), ...(act.k ? { k: act.k } : {}),
    qs: act.qs.map((q) => ({ id: q.id, k: q.k, q: q.q, ...(q.qe ? { qe: q.qe } : {}), ...(q.r ? { r: 1 } : {}), ...(q.o ? { o: q.o.map((o) => (o.e ? { v: o.v, e: o.e } : { v: o.v })) } : {}) })),
    max: MONTH_MAX,
  };
}

async function save(store, id, v, now, key) {
  if (id) {
    if (!validId(id) && id !== SEED_KEY) return { error: 'Pesquisa inválida.' };
    const cur = parse(await store.hget(HASH, id));
    if (!cur) return { error: 'Pesquisa não encontrada.' };
    const next = { ...cur, ...v, u: now, h: addHistory(cur, 'edit', now) };
    await store.hset(HASH, id, JSON.stringify(next));
    return { id, item: next };
  }
  if ((await store.hlen(HASH)) >= MAX_ITEMS) return { error: `O limite é ${MAX_ITEMS} pesquisas. Exclua algumas antigas.` };
  const nid = newId();
  const qs = v.qs.map((q, i) => (/^n_\d+$/.test(q.id) ? { ...q, id: `${nid}_${i + 1}` } : q));
  const item = { ...v, qs, st: 'draft', c: now, u: now, p: 0, k: key || '', h: [{ t: now, e: 'create' }] };
  await store.hset(HASH, nid, JSON.stringify(item));
  return { id: nid, item };
}

/** Libera (live), encerra (off) ou volta a rascunho. Liberar marca a hora. */
async function setState(store, id, st, now) {
  if (!validId(id) && id !== SEED_KEY) return { error: 'Pesquisa inválida.' };
  if (!STATES.includes(st)) return { error: 'Estado inválido.' };
  const cur = parse(await store.hget(HASH, id));
  if (!cur) return { error: 'Pesquisa não encontrada.' };
  const next = { ...cur, st, u: now, p: st === 'live' && cur.st !== 'live' ? now : cur.p, h: addHistory(cur, st, now) };
  await store.hset(HASH, id, JSON.stringify(next));
  return { id, item: next, before: cur.st };
}

async function remove(store, id) {
  if (!validId(id) && id !== SEED_KEY) return { error: 'Pesquisa inválida.' };
  await store.hdel(HASH, id);
  return { ok: true };
}

/** Modelo pronto (a pesquisa rápida que o app já trazia), para o administrador usar como rascunho. */
const SEED = {
  k: SEED_KEY,
  t: 'Pesquisa rápida', te: 'Quick survey',
  qs: [
    { id: 'mais_usa', k: 'choice', q: 'Qual recurso você mais usa?', qe: 'Which feature do you use most?', r: true,
      o: [{ v: 'Afinador', e: 'Tuner' }, { v: 'Metrônomo', e: 'Metronome' }, { v: 'Grade de notas', e: 'Note grid' }, { v: 'Escalas e exercícios', e: 'Scales and exercises' }, { v: 'Estudo (timer)', e: 'Study (timer)' }] },
    { id: 'melhorar', k: 'text', q: 'O que poderia melhorar? (opcional)', qe: 'What could be better? (optional)' },
  ],
};

// ---------------- participações (o que o painel mostra) ----------------

const LEGACY_WINDOW_MS = 120000; // respostas antigas (sem id) do mesmo aparelho enviadas em até 2 min = uma participação

/**
 * Junta as linhas de fb:v1 (cada pergunta/nota é uma linha) em participações: uma por envio.
 * Linhas novas trazem `pid`; as antigas (sem pid) do mesmo aparelho enviadas quase juntas viram uma só.
 * Devolve do mais novo ao mais antigo.
 */
function groupParticipations(rows) {
  const parts = new Map();
  const lastLegacy = new Map();
  const order = [];
  for (const r of rows) {
    if (!r || (r.k !== 'survey' && r.k !== 'rating')) continue;
    const ms = Date.parse(r.t) || 0;
    let key;
    if (r.pid) key = 'p:' + r.pid;
    else if (r.k === 'survey') {
      const l = lastLegacy.get(r.d);
      key = l && ms - l.ms <= LEGACY_WINDOW_MS ? l.key : 'l:' + r.d + ':' + ms;
      if (!l || l.key !== key) lastLegacy.set(r.d, { key, ms });
    } else key = 'r:' + r.d + ':' + ms;
    let p = parts.get(key);
    if (!p) {
      p = { id: key, t: r.t, kind: r.k, sv: r.sv || '', dev: r.d, ver: r.v || '', plat: r.p || '', code: r.u || '', answers: [], r: 0, c: '' };
      parts.set(key, p);
      order.push(key);
    }
    if (r.u && !p.code) p.code = r.u;
    if (r.k === 'rating') { p.r = r.r || 0; p.c = r.c || ''; } else p.answers.push({ q: r.q || '', a: r.a || '' });
    if (r.sv && !p.sv) p.sv = r.sv;
  }
  return order.map((k) => parts.get(k)).reverse();
}

module.exports = {
  HASH, MAX_ITEMS, MAX_TITLE, MAX_QUESTIONS, MAX_Q, MAX_OPTIONS, MAX_OPTION, MAX_HISTORY, STATES, MONTH_MAX, SEED, SEED_KEY,
  clean, validate, parse, status, listAll, publicSurvey, save, setState, remove, validId, groupParticipations,
};
