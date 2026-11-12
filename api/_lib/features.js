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
};

const MODES = ['off', 'list', 'pct', 'all'];
const CFG = 'ff:cfg';
const SET = (id) => `ff:l:${id}`;
const CACHE_MS = 60000;
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
  return { m, p, t: (j && Number(j.t)) || 0 };
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

/** O recurso [id] está ligado para [code]? [legacy] = códigos do acervo em LIBRARY_TESTERS (só vale para o acervo). */
function isOn(cfg, id, code, prof, legacy) {
  if (!known(id)) return false;
  const e = cfg[id] || { m: 'list', p: 0 };
  if (e.m === 'off') return false;
  if (e.m === 'all') return true;
  if (listOf(prof).includes(id)) return true;
  if (id === 'acervo' && legacy && legacy.has(code)) return true;
  if (e.m === 'pct' && bucket(code) < e.p) return true;
  return false;
}

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
  const rest = [];
  for (const c of codes) {
    if ((id === 'acervo' && legacy && legacy.has(c)) || (e.m === 'pct' && bucket(c) < e.p)) out.add(c);
    else rest.push(c);
  }
  if (rest.length) {
    const r = await cmd.cmd(['SMISMEMBER', SET(id), ...rest]);
    rest.forEach((c, i) => { if (Number((r || [])[i]) === 1) out.add(c); });
  }
  return out;
}

async function setMode(store, id, mode, pct, now) {
  await store.hset(CFG, id, JSON.stringify({ m: mode, p: mode === 'pct' ? pct : 0, t: now }));
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

/** Para o painel: um cartão por recurso. */
async function overview(store, cmd, legacy, now) {
  const cfg = await loadCfg(store, now);
  const ids = Object.keys(FEATURES);
  const sets = await Promise.all(ids.map((id) => cmd.cmd(['SMEMBERS', SET(id)])));
  return ids.map((id, i) => {
    const members = (sets[i] || []).map(String).sort();
    return {
      id, ...FEATURES[id], mode: cfg[id].m, pct: cfg[id].p, changed: cfg[id].t,
      count: members.length, members: members.slice(0, 100),
      legacy: id === 'acervo' ? [...(legacy || [])] : [],
    };
  });
}

module.exports = { FEATURES, MODES, MAX_GRANT, known, bucket, loadCfg, isOn, forProfile, many, setMode, grant, revoke, overview, resetCache, listOf };
