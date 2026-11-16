// Aparelhos de uma conta: a mesma conta (código do perfil) pode ser usada em até MAX_DEVICES aparelhos ao mesmo tempo.
//
// Antes, entrar em um aparelho novo (e-mail ou chave de 25) TROCAVA o dono: o segredo do aparelho antigo deixava de valer.
// Agora o aparelho novo é ADICIONADO à lista; o dono manda em quais aparelhos a conta fica aberta e pode tirar qualquer um.
//
// Onde fica: no próprio hash do perfil (u:<código>), sem chave nova e sem comando a mais no portão do vínculo:
//   h   = hash do segredo de UM aparelho da lista (o campo de sempre; perfis antigos só têm este)
//   dl  = JSON com a lista { i, h, c, l, ou, br, md, dn }: id curto, hash do segredo, criado, visto por último,
//         sistema, navegador, modelo e apelido que a pessoa deu (só o necessário para ela reconhecer o aparelho)
// Um perfil sem "dl" tem um aparelho só (o de "h"): a lista é montada na hora, sem migração em massa.
// O segredo em si nunca é guardado nem devolvido; só o hash e um id de 10 caracteres para o app apontar um aparelho.
'use strict';

const crypto = require('node:crypto');

const MAX_DEVICES = 5;
const SEEN_EVERY = 6 * 3600 * 1000; // "visto por último" grava no máximo a cada 6 h por aparelho (só com 2+ aparelhos)

const sha = (s) => crypto.createHash('sha256').update(s).digest('hex');
const secretHash = (secret) => sha('lnk|' + secret);

function eq(a, b) {
  return typeof a === 'string' && typeof b === 'string' && a.length === b.length && a.length > 0 && crypto.timingSafeEqual(Buffer.from(a), Buffer.from(b));
}

const cleanText = (v, max) => String(v == null ? '' : v).replace(/[\u0000-\u001f\u007f<>]/g, '').replace(/\s+/g, ' ').trim().slice(0, max);

/** A lista de aparelhos do perfil (monta a partir de "h" se o perfil é antigo). */
function list(prof) {
  let l = [];
  try { l = JSON.parse(prof.dl || '[]'); } catch (_) { l = []; }
  if (!Array.isArray(l)) l = [];
  l = l.filter((d) => d && typeof d.h === 'string' && d.h.length === 64);
  if (prof.h && !l.some((d) => eq(d.h, prof.h))) {
    // Aparelho de antes das listas: vira o primeiro (a ficha vem do que o painel já guarda dele).
    let dv = {};
    try { dv = JSON.parse(prof.dv || '{}'); } catch (_) { dv = {}; }
    l.unshift({ i: prof.h.slice(0, 10), h: prof.h, c: Number(prof.ca) || 0, l: Number(prof.la) || 0, ou: dv.ou || '', br: dv.br || '', md: dv.md || '', dn: '' });
  }
  return l;
}

/** O segredo (já em hash) é de algum aparelho da conta? Devolve o aparelho ou null. */
function find(prof, hash) {
  for (const d of list(prof)) if (eq(d.h, hash)) return d;
  return null;
}

/** O que mostrar ao dono: sem o hash do segredo. */
function view(d, meHash) {
  return { id: d.i, ou: d.ou || '', br: d.br || '', md: d.md || '', dn: d.dn || '', c: d.c || 0, l: d.l || 0, me: meHash ? eq(d.h, meHash) : false };
}

function entry(hash, info, name, now) {
  const i = info || {};
  return { i: hash.slice(0, 10), h: hash, c: now, l: now, ou: cleanText(i.ou, 12), br: cleanText(i.br, 16), md: cleanText(i.md, 32), dn: cleanText(name, 40) };
}

async function save(store, code, prof, devices) {
  // "h" continua sendo o hash de um aparelho que ainda existe (outras partes olham só ele).
  const keep = devices.some((d) => eq(d.h, prof.h)) ? prof.h : devices[0].h;
  await store.hset(`u:${code}`, 'dl', JSON.stringify(devices));
  if (keep !== prof.h) await store.hset(`u:${code}`, 'h', keep);
}

/** Acrescenta um aparelho. Devolve { ok, devices } ou { limit: true, devices } quando já há MAX_DEVICES. */
async function add(store, code, prof, hash, info, name, now, dropId) {
  let devices = list(prof);
  if (devices.some((d) => eq(d.h, hash))) return { ok: true, devices, already: true };
  if (dropId) devices = devices.filter((d) => d.i !== String(dropId));
  if (devices.length >= MAX_DEVICES) return { limit: true, devices };
  devices.push(entry(hash, info, name, now));
  await save(store, code, prof, devices);
  return { ok: true, devices };
}

/** Tira um aparelho da conta. Devolve { ok } | { missing } | { last }. */
async function remove(store, code, prof, id) {
  const devices = list(prof);
  const d = devices.find((x) => x.i === String(id));
  if (!d) return { missing: true };
  if (devices.length <= 1) return { last: true };
  const rest = devices.filter((x) => x !== d);
  await save(store, code, { ...prof, h: eq(prof.h, d.h) ? '' : prof.h }, rest);
  return { ok: true, devices: rest };
}

/** Marca "visto por último" do aparelho (só quando a conta tem 2+ aparelhos e faz mais de 6 h). 1 comando no máximo. */
async function seen(store, code, prof, hash, now) {
  if (!prof.dl) return false;
  const devices = list(prof);
  const d = devices.find((x) => eq(x.h, hash));
  if (!d || now - (d.l || 0) < SEEN_EVERY) return false;
  d.l = now;
  await store.hset(`u:${code}`, 'dl', JSON.stringify(devices));
  return true;
}

/** Dá um apelido ao aparelho (o próprio dono, a partir do aparelho que está usando). */
async function rename(store, code, prof, hash, name) {
  const devices = list(prof);
  const d = devices.find((x) => eq(x.h, hash));
  if (!d) return false;
  d.dn = cleanText(name, 40);
  await save(store, code, prof, devices);
  return true;
}

module.exports = { MAX_DEVICES, secretHash, list, find, view, add, remove, seen, rename, eq };
