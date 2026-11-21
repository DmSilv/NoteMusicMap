// Recursos liberados aos poucos ("chaves"): cada novidade nasce desligada, é liberada por código de perfil, depois por
// porcentagem e, por fim, para todos. O SERVIDOR decide; o app só esconde o que não está ligado.
//
// Dados:
//   ff:cfg        hash  recurso -> {"m": "off|list|pct|all", "p": 0..100, "t": ms}   (sem entrada = "list")
//   ff:l:<id>     set   códigos liberados por lista (só para o painel listar/contar e para consultar vários de uma vez)
//   u:<código>    campo "ff": ids liberados por lista, separados por vírgula (leitura de graça: o perfil já é lido em todo pedido)
//
// Estados:  off  = desligado para TODOS (inclusive quem está na lista: é a chave de desligar na hora)
//           list = só quem está na lista (e, no acervo, quem está em LIBRARY_TESTERS)
//           pct  = a lista mais uma parte fixa dos usuários (pelo código; sempre os mesmos)
//           all  = todos
// Grupos: um recurso também pode ser ligado a GRUPOS (campo "g" da configuração). Manuais: ff:g (id -> {n,t}), ff:gm:<id> (set de
// códigos) e o campo "gp" do perfil (ids separados por vírgula, de graça como o "ff"). Automáticos: auto:t (professores) e auto:s (alunos),
// calculados do próprio perfil (rt/rs). Precedência: desligar geral > todos > lista pessoal > grupo > porcentagem > nada.
// Custo: 0 comando a mais por sincronização (campo do perfil); a configuração geral fica 60 s na memória da função.
'use strict';

const crypto = require('node:crypto');

/** Recursos conhecidos. Só estes aparecem no painel e só estes podem ser ligados. */
const FEATURES = {
  acervo: {
    name: 'Acervo e repertório',
    desc: 'O professor cadastra métodos e peças como links; o aluno vinculado abre.',
    scope: 'professor',
    students: true,
  },
  aula_online: {
    name: 'Aula online',
    desc: 'Aula com link (Meet, Zoom…), link padrão do professor e botão "Entrar na aula" para o aluno.',
    scope: 'professor',
    students: true,
  },
  lembrete_escolha: {
    name: 'Lembrete escolhido pelo professor',
    desc: 'O professor escolhe com quanto tempo de antecedência avisar cada aula (5 min a 1 dia, ou nenhum). Sem a chave, o aviso é 15 min antes.',
    scope: 'professor',
    students: true,
  },
  ficha_nova: {
    name: 'Ficha do aluno nova',
    desc: 'A ficha do aluno em três blocos: Agora, Caminho e Combinados (no lugar da tela única com o menu).',
    scope: 'professor',
    students: false,
  },
};

const MODES = ['off', 'list', 'pct', 'all'];
const CFG = 'ff:cfg';
const SET = (id) => `ff:l:${id}`;
const CACHE_MS = 60000;
const GROUPS = 'ff:g';
const GSET = (id) => `ff:gm:${id}`;
const MAX_GROUPS = 20;
const MAX_MEMBERS = 500;
const AUTO = { 'auto:t': { name: 'Todos os professores', has: (p) => p && p.rt === '1' }, 'auto:s': { name: 'Todos os alunos', has: (p) => p && p.rs === '1' } };
const GID = /^g[0-9a-f]{6}$/;
const MAX_GRANT = 200; // alunos liberados junto com um professor, no máximo

let cache = null; // { t, v }
function resetCache() { cache = null; }

const known = (id) => Object.prototype.hasOwnProperty.call(FEATURES, id);

/** Parte fixa de 0 a 99 para este código (sempre a mesma). */
function bucket(code) {
  return parseInt(crypto.createHash('sha256').update(`ff|${code}`).digest('hex').slice(0, 8), 16) % 100;
}

function parseEntry(raw) {
  let j = null;
  try { j = raw ? JSON.parse(raw) : null; } catch (_) { j = null; }
  const m = j && MODES.includes(j.m) ? j.m : 'list';
  const p = j && Number.isFinite(Number(j.p)) ? Math.max(0, Math.min(100, Math.round(Number(j.p)))) : 0;
  const g = j && Array.isArray(j.g) ? j.g.map(String).filter((x) => GID.test(x) || AUTO[x]).slice(0, MAX_GROUPS + 2) : [];
  return { m, p, t: (j && Number(j.t)) || 0, g };
}

/** Configuração geral de todos os recursos (1 comando, guardada 60 s). */
async function loadCfg(store, now) {
  if (cache && now - cache.t < CACHE_MS) return cache.v;
  const raw = await store.hgetall(CFG);
  const v = {};
  for (const id of Object.keys(FEATURES)) v[id] = parseEntry(raw[id]);
  cache = { t: now, v };
  return v;
}

const listOf = (prof) => String((prof && prof.ff) || '').split(',').filter(Boolean);

const groupsOf = (prof) => String((prof && prof.gp) || '').split(',').filter(Boolean);

/** Por que o recurso [id] está (ou não) ligado para [code]: { on, why, group? } (why = off|all|list|legacy|group|pct|none). */
function why(cfg, id, code, prof, legacy) {
  if (!known(id)) return { on: false, why: 'unknown' };
  const e = cfg[id] || { m: 'list', p: 0, g: [] };
  if (e.m === 'off') return { on: false, why: 'off' };
  if (e.m === 'all') return { on: true, why: 'all' };
  if (listOf(prof).includes(id)) return { on: true, why: 'list' };
  if (id === 'acervo' && legacy && legacy.has(code)) return { on: true, why: 'legacy' };
  const mine = groupsOf(prof);
  for (const g of e.g || []) {
    if (AUTO[g] ? AUTO[g].has(prof) : mine.includes(g)) return { on: true, why: 'group', group: g };
  }
  if (e.m === 'pct' && bucket(code) < e.p) return { on: true, why: 'pct' };
  return { on: false, why: 'none' };
}

/** O recurso [id] está ligado para [code]? [legacy] = códigos do acervo em LIBRARY_TESTERS (só vale para o acervo). */
function isOn(cfg, id, code, prof, legacy) { return why(cfg, id, code, prof, legacy).on; }

/** Recursos ligados para este perfil (sem nenhum comando a mais: usa o perfil já lido). */
async function forProfile(store, code, prof, legacy, now) {
  const cfg = await loadCfg(store, now);
  return Object.keys(FEATURES).filter((id) => isOn(cfg, id, code, prof, legacy));
}

/** Entre [codes], quais têm o recurso ligado (1 comando só, para perfis que não foram lidos). */
async function many(cmd, store, id, codes, legacy, now) {
  const out = new Set();
  if (!known(id) || !codes.length) return out;
  const cfg = await loadCfg(store, now);
  const e = cfg[id];
  if (e.m === 'off') return out;
  if (e.m === 'all') return new Set(codes);
  let rest = [];
  for (const c of codes) {
    if ((id === 'acervo' && legacy && legacy.has(c)) || (e.m === 'pct' && bucket(c) < e.p)) out.add(c);
    else rest.push(c);
  }
  const sieve = async (key) => {
    if (!rest.length) return;
    const r = await cmd.cmd(['SMISMEMBER', key, ...rest]);
    const left = [];
    rest.forEach((c, i) => { if (Number((r || [])[i]) === 1) out.add(c); else left.push(c); });
    rest = left;
  };
  await sieve(SET(id));
  // Grupos manuais (um comando por grupo do recurso); os automáticos dependem do perfil e não entram aqui.
  for (const g of (e.g || []).filter((x) => GID.test(x))) await sieve(GSET(g));
  return out;
}

async function setMode(store, id, mode, pct, now) {
  const keep = (await loadCfg(store, 0))[id];
  await store.hset(CFG, id, JSON.stringify({ m: mode, p: mode === 'pct' ? pct : 0, t: now, g: keep.g || [] }));
  resetCache();
}

async function grant(store, cmd, id, code) {
  await cmd.cmd(['SADD', SET(id), code]);
  const prof = await store.hgetall(`u:${code}`);
  const cur = new Set(listOf(prof));
  cur.add(id);
  await store.hset(`u:${code}`, 'ff', [...cur].join(','));
}

async function revoke(store, cmd, id, code) {
  await cmd.cmd(['SREM', SET(id), code]);
  const prof = await store.hgetall(`u:${code}`);
  const cur = new Set(listOf(prof));
  cur.delete(id);
  await store.hset(`u:${code}`, 'ff', [...cur].join(','));
}

/** Grupos: lista com contagem (manuais) e os automáticos. */
async function groupList(store, cmd) {
  const raw = await store.hgetall(GROUPS);
  const manual = [];
  for (const [id, v] of Object.entries(raw || {})) {
    let j = null; try { j = JSON.parse(v); } catch (_) { j = null; }
    if (!GID.test(id) || !j) continue;
    const members = ((await cmd.cmd(['SMEMBERS', GSET(id)])) || []).map(String).sort();
    manual.push({ id, name: String(j.n || ''), t: j.t || 0, count: members.length, members: members.slice(0, 100) });
  }
  manual.sort((a, b) => a.name.localeCompare(b.name));
  return { manual, auto: Object.entries(AUTO).map(([id, v]) => ({ id, name: v.name })), max: { groups: MAX_GROUPS, members: MAX_MEMBERS } };
}

async function groupSave(store, name, now) {
  const n = String(name || '').replace(/[\u0000-\u001f]/g, '').trim().slice(0, 40);
  if (n.length < 2) return { error: 'Dê um nome ao grupo (2 a 40 letras).' };
  const raw = await store.hgetall(GROUPS);
  const ids = Object.keys(raw || {});
  if (ids.length >= MAX_GROUPS) return { error: `Limite de ${MAX_GROUPS} grupos.` };
  const id = 'g' + crypto.createHash('sha256').update(`g|${n}|${now}|${ids.length}`).digest('hex').slice(0, 6);
  await store.hset(GROUPS, id, JSON.stringify({ n, t: now }));
  return { id };
}

async function groupMember(store, cmd, gid, code, on) {
  if (!GID.test(gid) || (await store.hget(GROUPS, gid)) === undefined) return { error: 'Grupo não encontrado.' };
  if (on && Number(await cmd.cmd(['SCARD', GSET(gid)])) >= MAX_MEMBERS) return { error: `Limite de ${MAX_MEMBERS} pessoas por grupo.` };
  await cmd.cmd([on ? 'SADD' : 'SREM', GSET(gid), code]);
  const prof = await store.hgetall(`u:${code}`);
  const cur = new Set(groupsOf(prof));
  if (on) cur.add(gid); else cur.delete(gid);
  await store.hset(`u:${code}`, 'gp', [...cur].join(','));
  return { ok: true };
}

async function groupDelete(store, cmd, gid) {
  if (!GID.test(gid)) return { error: 'Grupo inválido.' };
  const members = ((await cmd.cmd(['SMEMBERS', GSET(gid)])) || []).map(String);
  for (const c of members) {
    const prof = await store.hgetall(`u:${c}`);
    const cur = new Set(groupsOf(prof)); cur.delete(gid);
    await store.hset(`u:${c}`, 'gp', [...cur].join(','));
  }
  await cmd.cmd(['DEL', GSET(gid)]);
  await cmd.cmd(['HDEL', GROUPS, gid]);
  const cfg = await loadCfg(store, 0);
  for (const id of Object.keys(FEATURES)) {
    if ((cfg[id].g || []).includes(gid)) await store.hset(CFG, id, JSON.stringify({ m: cfg[id].m, p: cfg[id].p, t: cfg[id].t, g: cfg[id].g.filter((x) => x !== gid) }));
  }
  resetCache();
  return { ok: true, cleaned: members.length };
}

/** Define os grupos que ligam o recurso. */
async function setGroups(store, id, gids, now) {
  const raw = await store.hgetall(GROUPS);
  const ok = [...new Set((gids || []).map(String))].filter((g) => AUTO[g] || (GID.test(g) && raw && raw[g] !== undefined)).slice(0, MAX_GROUPS + 2);
  const cur = (await loadCfg(store, 0))[id];
  await store.hset(CFG, id, JSON.stringify({ m: cur.m, p: cur.p, t: now, g: ok }));
  resetCache();
  return ok;
}

/** Diagnóstico: cada recurso, ligado ou não, e o motivo, para um perfil. */
async function diagnose(store, code, prof, legacy, now) {
  const cfg = await loadCfg(store, now);
  const raw = (await store.hgetall(GROUPS)) || {};
  const gname = (g) => {
    if (AUTO[g]) return AUTO[g].name;
    try { return JSON.parse(raw[g]).n; } catch (_) { return g; }
  };
  return Object.keys(FEATURES).map((id) => {
    const r = why(cfg, id, code, prof, legacy);
    return { id, name: FEATURES[id].name, mode: cfg[id].m, pct: cfg[id].p, on: r.on, why: r.why, ...(r.group ? { group: r.group, groupName: gname(r.group) } : {}) };
  });
}

/** Para o painel: um cartão por recurso. */
async function overview(store, cmd, legacy, now) {
  const cfg = await loadCfg(store, now);
  const ids = Object.keys(FEATURES);
  const sets = await Promise.all(ids.map((id) => cmd.cmd(['SMEMBERS', SET(id)])));
  return ids.map((id, i) => {
    const members = (sets[i] || []).map(String).sort();
    return {
      id, ...FEATURES[id], mode: cfg[id].m, pct: cfg[id].p, changed: cfg[id].t,
      count: members.length, members: members.slice(0, 100), groups: cfg[id].g || [],
      legacy: id === 'acervo' ? [...(legacy || [])] : [],
    };
  });
}

module.exports = { why, groupsOf, groupList, groupSave, groupMember, groupDelete, setGroups, diagnose, GID, AUTO, FEATURES, MODES, MAX_GRANT, known, bucket, loadCfg, isOn, forProfile, many, setMode, grant, revoke, overview, resetCache, listOf };
