// Exclusão completa de um perfil: tudo o que o servidor guarda dele (vínculos, aulas, tarefas, horários, foto, cópia na nuvem,
// conversa, índices de e-mail e chave de recuperação, listas de recursos e grupos). Usada pelo painel (Excluir dados) e pelo
// próprio usuário (Ajustes › Excluir minha conta, ação account_delete em api/link.js): um código só para os dois caminhos.
//
// Quem estava vinculado a este perfil perde o vínculo (o app dele percebe na próxima consulta) e, se ficou sem nenhum vínculo,
// deixa de contar como professor ou aluno nos números do painel.
'use strict';

const profiles = require('./profiles');
const inbox = require('./inbox');
const features = require('./features');
const { K } = require('./metrics');

const BLOCKED = 'pf:bl'; // conjunto dos perfis bloqueados
const EM = 'acct:em'; // hash do e-mail -> código
const RK = 'acct:rk'; // hash da chave de 25 caracteres -> código

const U = (c) => `u:${c}`, T = (c) => `ut:${c}`, S = (c) => `us:${c}`, SL = (c) => `sl:${c}`, SS = (c) => `ss:${c}`;
const LB = (c) => `lb:${c}`, UL = (c) => `ul:${c}`, DN = (c) => `dn:${c}`, VD = (c) => `vd:${c}`, AV = (c) => `av:${c}`;
const TK = (c) => `tk:${c}`, PS = (c) => `ps:${c}`, PH = (c) => `ph:${c}`, MI = (c) => `mi:${c}`, MM = (c) => `mm:${c}`;

/** Apaga o perfil [code]. Devolve { ok: true, links } ou { ok: false, missing: true } se o perfil não existe. */
async function purgeProfile(store, cmd, code, now) {
  const prof = await store.hgetall(U(code));
  if (!prof || prof.h === undefined) return { ok: false, missing: true };
  const [students, teachers] = await Promise.all([store.hgetall(T(code)), store.hgetall(S(code))]);
  const wipePrefix = async (key, prefix) => {
    for (const f of Object.keys(await store.hgetall(key))) if (f.startsWith(prefix)) await store.hdel(key, f);
  };
  for (const st of Object.keys(students)) { // este perfil era o professor deles
    await store.hdel(S(st), code);
    await wipePrefix(SS(st), `${code}:`);
    await wipePrefix(UL(st), `${code}:`);
    await wipePrefix(VD(st), `${code}:`);
    await store.hset(U(st), 'kr', String(now));
    if ((await store.hlen(S(st))) === 0) await profiles.setRole(cmd, st, 's', false, now);
  }
  for (const te of Object.keys(teachers)) { // este perfil era o aluno deles
    await store.hdel(T(te), code);
    await wipePrefix(DN(te), `${code}:`);
    const sl = await store.hgetall(SL(te));
    for (const [id, json] of Object.entries(sl)) {
      try { if (JSON.parse(json).sc === code) await store.hdel(SL(te), id); } catch (_) { /* linha ruim */ }
    }
    await store.hset(U(te), 'kr', String(now));
    if ((await store.hlen(T(te))) === 0) await profiles.setRole(cmd, te, 't', false, now);
  }
  // Índices que apontam para este perfil: e-mail e chave de recuperação (só se ainda forem dele).
  if (prof.eh && (await store.hget(EM, prof.eh)) === code) await store.hdel(EM, prof.eh);
  if (prof.rk && (await store.hget(RK, prof.rk)) === code) await store.hdel(RK, prof.rk);
  // Listas de recursos e grupos de recursos em que ele estava.
  for (const id of Object.keys(features.FEATURES)) await cmd.cmd(['SREM', `ff:l:${id}`, code]);
  for (const g of features.groupsOf(prof)) await cmd.cmd(['SREM', `ff:gm:${g}`, code]);
  // Os dados do próprio perfil.
  for (const key of [T, S, SL, SS, UL, DN, VD, AV, TK, PS, LB, PH, MI, MM, U]) {
    for (const f of Object.keys(await store.hgetall(key(code)))) await store.hdel(key(code), f);
  }
  await inbox.adminDelete(store, code); // a conversa particular some junto com o perfil
  await inbox.requestDrop(store, code); // e o pedido de suporte, se havia
  await profiles.forget(cmd, code);
  await cmd.cmd(['SREM', BLOCKED, code]);
  await cmd.cmd(['HINCRBY', K.total, 'profiles', '-1']);
  return { ok: true, links: Object.keys(students).length + Object.keys(teachers).length };
}

module.exports = { purgeProfile };
