// Conversa particular entre o administrador e cada usuário (aparece em Avisos no app).
//
// Dados (Redis, hashes; nada de endpoint novo):
//   cv:th  hash  código do perfil -> JSON {m:[{i,f,t,x,ref?,ask?}], ok?}   a conversa (no máximo MAX_MSGS mensagens)
//            f = "a" (administrador) | "u" (usuário); t = hora (ms); x = texto; ref = trecho da sugestão respondida;
//            ask = 1: a mensagem pede licença para citar o apelido no boletim; ok = resposta do usuário (1 sim | 0 não)
//   cv:ix  hash  código do perfil -> JSON {t,f,s,n,x,c?}   resumo para a caixa de entrada (leitura barata do painel)
//            s = "open" | "done" (resolvida); n = respostas do usuário ainda não vistas pelo admin; x = trecho; c = ok
//   u:<código> campo "cr" = hora da última mensagem do admin (o app vê na sincronização que já faz: custo extra zero)
// Privacidade: só o dono do código lê a própria conversa (o servidor autentica o segredo antes); texto limpo e curto.
// O usuário NÃO inicia conversa: só responde quando o administrador escreveu primeiro.
'use strict';

const crypto = require('node:crypto');

const TH = 'cv:th';
const IX = 'cv:ix';
const MAX_MSGS = 30; // por conversa
const MAX_ADMIN = 600; // texto do administrador
const MAX_USER = 280; // resposta curta do usuário
const MAX_REF = 90;
const MAX_THREADS = 800; // teto da caixa de entrada
const ADMIN_PER_DAY = 10; // mensagens do admin para o mesmo perfil por dia
const USER_PER_HOUR = 6; // respostas do mesmo perfil por hora
const USER_STREAK = 3; // respostas seguidas sem o admin escrever

function clean(v, max) {
  let s = String(v == null ? '' : v).replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, ' ');
  s = s.replace(/[ \t]+/g, ' ').replace(/ *\n */g, '\n').replace(/\n{3,}/g, '\n\n');
  return s.trim().slice(0, max);
}

const newId = () => crypto.randomBytes(4).toString('hex');

function parseThread(raw) {
  try {
    const j = JSON.parse(raw);
    if (!j || !Array.isArray(j.m)) return { m: [] };
    const m = j.m.filter((x) => x && (x.f === 'a' || x.f === 'u') && typeof x.x === 'string').slice(-MAX_MSGS);
    return { m, ...(j.ok === 0 || j.ok === 1 ? { ok: j.ok } : {}) };
  } catch (_) { return { m: [] }; }
}

function parseIx(raw) {
  try {
    const j = JSON.parse(raw);
    if (!j || typeof j !== 'object') return null;
    return { t: Number(j.t) || 0, f: j.f === 'u' ? 'u' : 'a', s: j.s === 'done' ? 'done' : 'open', n: Math.max(0, Number(j.n) || 0), x: String(j.x || ''), ...(j.c === 0 || j.c === 1 ? { c: j.c } : {}) };
  } catch (_) { return null; }
}

const snippet = (s) => s.replace(/\s+/g, ' ').slice(0, 70);

/** O administrador escreve para o perfil [code]. Devolve { ok, msg } ou { error }. */
async function adminSend(store, code, text, now, opts = {}) {
  const x = clean(text, MAX_ADMIN);
  if (!x) return { error: 'Escreva a mensagem.' };
  const lim = await store.incr(`cvA:${code}:${Math.floor(now / 86400000)}`, 86400);
  if (lim.n > ADMIN_PER_DAY) return { error: 'Já são muitas mensagens para este perfil hoje. Tente amanhã.' };
  const prev = parseIx(await store.hget(IX, code));
  if (!prev && (await store.hlen(IX)) >= MAX_THREADS) return { error: `A caixa de entrada chegou a ${MAX_THREADS} conversas. Resolva e apague as antigas.` };
  const th = parseThread(await store.hget(TH, code));
  const msg = { i: newId(), f: 'a', t: now, x };
  const ref = clean(opts.ref, MAX_REF);
  if (ref) msg.ref = ref;
  if (opts.ask) msg.ask = 1;
  th.m.push(msg);
  th.m = th.m.slice(-MAX_MSGS);
  if (opts.ask) delete th.ok; // nova pergunta, nova resposta
  await store.hset(TH, code, JSON.stringify(th));
  const ix = { t: now, f: 'a', s: 'open', n: 0, x: snippet(x), ...(th.ok === 0 || th.ok === 1 ? { c: th.ok } : prev && prev.c !== undefined && !opts.ask ? { c: prev.c } : {}) };
  await store.hset(IX, code, JSON.stringify(ix));
  await store.hset(`u:${code}`, 'cr', String(now)); // o app vê no próximo sync/rev
  return { ok: true, msg };
}

/** O que o app mostra ao dono: a conversa e a pergunta de crédito ainda sem resposta. */
async function userView(store, code) {
  const th = parseThread(await store.hget(TH, code));
  const last = th.m.filter((x) => x.f === 'a').pop();
  return { m: th.m, askOpen: !!(last && last.ask && th.ok === undefined) };
}

/** O usuário responde (só se o admin já escreveu; limite por hora e por sequência). */
async function userReply(store, code, text, now) {
  const x = clean(text, MAX_USER);
  if (!x) return { error: 'Escreva a resposta.' };
  const th = parseThread(await store.hget(TH, code));
  if (!th.m.some((m) => m.f === 'a')) return { error: 'Sem conversa aberta.' };
  let streak = 0;
  for (let i = th.m.length - 1; i >= 0 && th.m[i].f === 'u'; i--) streak++;
  if (streak >= USER_STREAK) return { error: 'Aguarde a resposta antes de enviar mais.' };
  const lim = await store.incr(`cvU:${code}:${Math.floor(now / 3600000)}`, 3600);
  if (lim.n > USER_PER_HOUR) return { error: 'Muitas respostas agora. Tente mais tarde.' };
  const msg = { i: newId(), f: 'u', t: now, x };
  th.m.push(msg);
  th.m = th.m.slice(-MAX_MSGS);
  await store.hset(TH, code, JSON.stringify(th));
  const prev = parseIx(await store.hget(IX, code)) || { t: 0, f: 'a', s: 'open', n: 0, x: '' };
  await store.hset(IX, code, JSON.stringify({ ...prev, t: now, f: 'u', s: 'open', n: prev.n + 1, x: snippet(x) }));
  return { ok: true, msg };
}

/** O usuário aceita (1) ou recusa (0) ser citado pelo apelido no boletim. Só vale se houve a pergunta. */
async function userConsent(store, code, yes) {
  const th = parseThread(await store.hget(TH, code));
  const last = th.m.filter((x) => x.f === 'a').pop();
  if (!last || !last.ask) return { error: 'Sem pergunta aberta.' };
  th.ok = yes ? 1 : 0;
  await store.hset(TH, code, JSON.stringify(th));
  const prev = parseIx(await store.hget(IX, code));
  if (prev) await store.hset(IX, code, JSON.stringify({ ...prev, c: th.ok }));
  return { ok: true, c: th.ok };
}

/** Caixa de entrada: 1 comando. Quem respondeu e ainda não foi lido primeiro, depois a atividade mais recente. */
async function adminList(store) {
  const all = await store.hgetall(IX);
  const out = [];
  for (const [code, raw] of Object.entries(all || {})) {
    const ix = parseIx(raw);
    if (ix) out.push({ code, ...ix });
  }
  return out.sort((a, b) => (b.n > 0) - (a.n > 0) || b.t - a.t);
}

/** Uma conversa para o painel; zera o contador de "não lidas". */
async function adminThread(store, code) {
  const th = parseThread(await store.hget(TH, code));
  const ix = parseIx(await store.hget(IX, code));
  if (ix && ix.n > 0) await store.hset(IX, code, JSON.stringify({ ...ix, n: 0 }));
  return { m: th.m, s: ix ? ix.s : 'open', ...(th.ok === 0 || th.ok === 1 ? { ok: th.ok } : {}) };
}

async function adminResolve(store, code, done) {
  const ix = parseIx(await store.hget(IX, code));
  if (!ix) return { error: 'Conversa não encontrada.' };
  await store.hset(IX, code, JSON.stringify({ ...ix, s: done ? 'done' : 'open' }));
  return { ok: true };
}

async function adminDelete(store, code) {
  await store.hdel(TH, code);
  await store.hdel(IX, code);
  return { ok: true };
}

/** Quem aceitou ser citado? Devolve 1, 0 ou undefined (nunca perguntado). */
async function consentOf(store, code) {
  const ix = parseIx(await store.hget(IX, code));
  return ix ? ix.c : undefined;
}

module.exports = {
  TH, IX, MAX_MSGS, MAX_ADMIN, MAX_USER, ADMIN_PER_DAY, USER_PER_HOUR, USER_STREAK,
  clean, parseThread, parseIx, adminSend, userView, userReply, userConsent, adminList, adminThread, adminResolve, adminDelete, consentOf,
};
