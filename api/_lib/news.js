// Boletim do app ("Novidades"): textos curtos que o administrador escreve, publica, oculta ou exclui no painel.
// O app só LÊ a lista publicada (GET /api/news, com cache de CDN), então o custo por usuário é praticamente zero.
//
// Dados:
//   nw:items   hash  id -> JSON {t, b, te, be, st, c, u, p, k}
//     t/b    título e texto em português; te/be (opcionais) em inglês
//     st     "draft" (rascunho) | "live" (publicado) | "off" (oculto, continua no histórico)
//     c/u/p  criado, alterado e publicado por último (ms); p = 0 se nunca foi publicado
//     k      chave da sugestão pronta de onde veio (para não oferecer a mesma duas vezes)
//     fb     rótulo opcional: "idea" (sugestão de usuário que virou melhoria) | "fix" (correção feita a partir de feedback)
//     fn     apelido citado como crédito: SÓ existe se o usuário aceitou (conversa do painel); sem ele o app diz "um usuário"
// Nada é publicado sozinho: só o administrador muda "st" para "live".
'use strict';

const crypto = require('node:crypto');

const HASH = 'nw:items';
const MAX_ITEMS = 100; // rascunhos + histórico
const MAX_TITLE = 60;
const MAX_BODY = 420;
const MAX_LIVE = 10; // quantos o app recebe (os mais recentes)
const STATES = ['draft', 'live', 'off'];
const FB_KINDS = ['idea', 'fix'];

/** Tira caracteres de controle (mantém quebra de linha no texto), corta o tamanho. */
function clean(v, max, multiline) {
  let s = String(v == null ? '' : v).replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, ' ');
  s = multiline ? s.replace(/[ \t]+/g, ' ').replace(/ *\n */g, '\n').replace(/\n{3,}/g, '\n\n') : s.replace(/\s+/g, ' ');
  return s.trim().slice(0, max);
}

/** Valida o que veio do painel; devolve { v } ou { error }. */
function validate(b) {
  const t = clean(b && b.t, MAX_TITLE, false);
  const body = clean(b && b.b, MAX_BODY, true);
  if (!t) return { error: 'Falta o título.' };
  if (!body) return { error: 'Falta o texto.' };
  const v = { t, b: body, te: clean(b.te, MAX_TITLE, false), be: clean(b.be, MAX_BODY, true) };
  // Rótulo de feedback: só altera se o painel mandou a chave (painel antigo não apaga o que já existe).
  if (b && b.fb !== undefined) v.fb = FB_KINDS.includes(b.fb) ? b.fb : '';
  return { v };
}

function parse(raw) {
  try {
    const j = JSON.parse(raw);
    if (!j || typeof j !== 'object') return null;
    return {
      t: String(j.t || ''), b: String(j.b || ''), te: String(j.te || ''), be: String(j.be || ''),
      st: STATES.includes(j.st) ? j.st : 'draft', c: Number(j.c) || 0, u: Number(j.u) || 0, p: Number(j.p) || 0, k: String(j.k || ''),
      fb: FB_KINDS.includes(j.fb) ? j.fb : '', fn: clean(j.fn, 40, false),
    };
  } catch (_) { return null; }
}

const newId = () => crypto.randomBytes(5).toString('hex');
const validId = (id) => typeof id === 'string' && /^[0-9a-f]{10}$/.test(id);

/** Tudo (rascunhos, publicados e ocultos), do mais novo ao mais antigo. 1 comando. */
async function listAll(store) {
  const all = await store.hgetall(HASH);
  const out = [];
  for (const [id, raw] of Object.entries(all || {})) {
    const it = parse(raw);
    if (it && validId(id)) out.push({ id, ...it });
  }
  return out.sort((a, b) => Math.max(b.p, b.u, b.c) - Math.max(a.p, a.u, a.c));
}

/** O que o app recebe: só os publicados, o mais recente primeiro, sem dado interno. */
function publicItems(all) {
  return all
    .filter((i) => i.st === 'live')
    .sort((a, b) => b.p - a.p)
    .slice(0, MAX_LIVE)
    .map((i) => ({ id: i.id, t: i.t, b: i.b, ...(i.te ? { te: i.te } : {}), ...(i.be ? { be: i.be } : {}), ...(i.fb ? { fb: i.fb, ...(i.fn ? { fn: i.fn } : {}) } : {}), p: i.p }));
}

/** Cria (sem id) ou altera (com id) um rascunho/texto. Quem já foi publicado continua com o mesmo estado. */
async function save(store, id, v, now, key) {
  if (id) {
    if (!validId(id)) return { error: 'Publicação inválida.' };
    const cur = parse(await store.hget(HASH, id));
    if (!cur) return { error: 'Publicação não encontrada.' };
    const next = { ...cur, ...v, u: now };
    await store.hset(HASH, id, JSON.stringify(next));
    return { id, item: next };
  }
  if ((await store.hlen(HASH)) >= MAX_ITEMS) return { error: `O limite é ${MAX_ITEMS} publicações. Exclua algumas antigas.` };
  const nid = newId();
  const item = { ...v, st: 'draft', c: now, u: now, p: 0, k: key || '' };
  await store.hset(HASH, nid, JSON.stringify(item));
  return { id: nid, item };
}

/** Publica, oculta ou volta a rascunho. Publicar marca a hora (a ordem no app é pela hora da publicação). */
async function setState(store, id, st, now) {
  if (!validId(id)) return { error: 'Publicação inválida.' };
  if (!STATES.includes(st)) return { error: 'Estado inválido.' };
  const cur = parse(await store.hget(HASH, id));
  if (!cur) return { error: 'Publicação não encontrada.' };
  const next = { ...cur, st, u: now, p: st === 'live' && cur.st !== 'live' ? now : cur.p };
  await store.hset(HASH, id, JSON.stringify(next));
  return { id, item: next, before: cur.st };
}

async function remove(store, id) {
  if (!validId(id)) return { error: 'Publicação inválida.' };
  await store.hdel(HASH, id);
  return { ok: true };
}

module.exports = { FB_KINDS, HASH, MAX_ITEMS, MAX_TITLE, MAX_BODY, MAX_LIVE, STATES, clean, validate, parse, listAll, publicItems, save, setState, remove, validId };
