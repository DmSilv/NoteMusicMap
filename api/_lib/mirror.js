// Espelho da conta entre aparelhos: o que o professor (e a pessoa) guarda só no aparelho — alunos com tarefas, observações e
// aulas, agenda, métodos, histórico de estudo — passa a ficar também no servidor, para o outro aparelho da MESMA conta ter tudo.
//
// SÓ vale com 2 ou mais aparelhos na conta (api/_lib/devices.js): quem usa um aparelho só não gasta nem um comando a mais.
// Com 1 aparelho de novo, o espelho é apagado.
//
// Cada coisa é uma SEÇÃO (texto JSON): "S:<código do aluno>" ou "S:i:<id>" para aluno sem código, "AG" agenda, "OS" horários
// livres, "ME" métodos, "PR" ajustes da conta, "SE" histórico de estudo. O servidor não entende o conteúdo: guarda, limita e
// diz o que mudou. Quem decide como juntar é o app (packages/afina_core/lib/mirror.dart).
//   mi:<código>  hash  seção -> texto
//   mm:<código>  hash  seção -> { u: versão (ms), x?: 1 se foi apagada, n: tamanho }   (leve: dá para listar sem baixar tudo)
//   u:<código>.mr  = revisão do espelho (muda a cada gravação; vai junto da consulta barata 'rev')
'use strict';

const MAX_SECTIONS = 400;
const MAX_SECTION_CHARS = 120000;
const MAX_GET = 20;
const MAX_TOTAL_CHARS = 4000000; // 4 MB por conta
const SEC_RE = /^[A-Za-z0-9:_.-]{1,64}$/;

const MI = (code) => `mi:${code}`;
const MM = (code) => `mm:${code}`;

function parseMeta(raw) {
  try {
    const j = JSON.parse(raw);
    return { u: Number(j.u) || 0, x: j.x === 1, n: Number(j.n) || 0 };
  } catch (_) {
    return null;
  }
}

/** Lista leve: seção -> { u, x? }. */
async function list(store, code) {
  const all = await store.hgetall(MM(code));
  const secs = {};
  for (const [sec, raw] of Object.entries(all)) {
    const m = parseMeta(raw);
    if (m) secs[sec] = m.x ? { u: m.u, x: 1 } : { u: m.u };
  }
  return secs;
}

/** Baixa as seções pedidas (até MAX_GET): { sec: { u, d } } (apagadas voltam com x: 1 e sem d). */
async function get(store, code, wanted) {
  const out = {};
  for (const sec of wanted.slice(0, MAX_GET)) {
    if (typeof sec !== 'string' || !SEC_RE.test(sec)) continue;
    const meta = parseMeta(await store.hget(MM(code), sec));
    if (!meta) continue;
    if (meta.x) { out[sec] = { u: meta.u, x: 1 }; continue; }
    const d = await store.hget(MI(code), sec);
    if (typeof d === 'string') out[sec] = { u: meta.u, d };
  }
  return out;
}

/** Grava uma seção. Devolve { ok, mr } | { stale: true, u } | { error }. Versão mais antiga que a guardada é ignorada. */
async function put(store, code, sec, u, d, now) {
  if (typeof sec !== 'string' || !SEC_RE.test(sec)) return { error: 'bad_section' };
  if (typeof d !== 'string' || d.length > MAX_SECTION_CHARS) return { error: 'too_big' };
  const ver = Number(u);
  if (!Number.isFinite(ver) || ver <= 0 || ver > now + 86400000) return { error: 'bad_version' };
  const cur = parseMeta(await store.hget(MM(code), sec));
  if (cur && cur.u >= ver) return { stale: true, u: cur.u };
  // Teto da conta: seções (400) e tamanho total (4 MB), para ninguém encher o banco.
  const metas = await store.hgetall(MM(code));
  if (!cur && Object.keys(metas).length >= MAX_SECTIONS) return { error: 'too_many' };
  let total = d.length;
  for (const [k, raw] of Object.entries(metas)) if (k !== sec) total += (parseMeta(raw) || {}).n || 0;
  if (total > MAX_TOTAL_CHARS) return { error: 'too_big' };
  await store.hset(MI(code), sec, d);
  await store.hset(MM(code), sec, JSON.stringify({ u: ver, n: d.length }));
  await store.hset(`u:${code}`, 'mr', String(now));
  return { ok: true, mr: now };
}

/** Marca uma seção como apagada (fica a marca, para o outro aparelho apagar também). */
async function del(store, code, sec, u, now) {
  if (typeof sec !== 'string' || !SEC_RE.test(sec)) return { error: 'bad_section' };
  const ver = Number(u);
  if (!Number.isFinite(ver) || ver <= 0 || ver > now + 86400000) return { error: 'bad_version' };
  const cur = parseMeta(await store.hget(MM(code), sec));
  if (cur && cur.u >= ver) return { stale: true, u: cur.u };
  if (!cur && (await store.hlen(MM(code))) >= MAX_SECTIONS) return { error: 'too_many' };
  await store.hdel(MI(code), sec);
  await store.hset(MM(code), sec, JSON.stringify({ u: ver, x: 1, n: 0 }));
  await store.hset(`u:${code}`, 'mr', String(now));
  return { ok: true, mr: now };
}

/** Apaga o espelho todo (a conta voltou a ter um aparelho só, ou o perfil foi apagado). */
async function clear(store, code) {
  for (const key of [MI(code), MM(code)]) {
    for (const f of Object.keys(await store.hgetall(key))) await store.hdel(key, f);
  }
  await store.hdel(`u:${code}`, 'mr');
}

module.exports = { MAX_SECTIONS, MAX_SECTION_CHARS, MAX_GET, MAX_TOTAL_CHARS, SEC_RE, list, get, put, del, clear, MI, MM };
