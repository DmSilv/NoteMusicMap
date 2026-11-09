// Métricas anônimas de uso: nomes das chaves, o dia (fuso de Brasília) e o contador que o servidor
// soma sozinho quando algo acontece (aula enviada, vínculo criado...). Falhar aqui NUNCA pode
// derrubar o que o usuário estava fazendo.
'use strict';

const { createCmd } = require('./store_cmd');

const BR_OFFSET = 3 * 3600 * 1000; // UTC-3 (o Brasil não tem mais horário de verão)

/** "2026-11-09": o dia no Brasil. */
const dayKey = (ms) => new Date(ms - BR_OFFSET).toISOString().slice(0, 10);

const K = {
  all: 'st:hll:all', // aparelhos distintos de todos os tempos (HyperLogLog)
  day: (d) => `st:hll:d:${d}`, // aparelhos distintos do dia
  ct: (d) => `st:ct:d:${d}`, // contadores do dia (hash): open, new, lesson, slot, remind, link
  dim: (d) => `st:dim:d:${d}`, // aparelhos por plataforma/instalação/versão no dia (hash)
  tab: (d, t) => `st:hll:d:${d}:tab:${t}`, // aparelhos distintos que abriram cada aba no dia
  total: 'st:cnt:all', // totais (hash): profiles, links
  online: 'st:online', // conjunto ordenado: aparelho -> última batida (ms)
};

const TABS = ['tuner', 'pedal', 'metronome', 'grid', 'study', 'profile', 'teacher', 'agenda', 'settings'];
const EVENTS = ['lesson', 'slot', 'remind', 'link', 'done'];

/** Soma 1 num contador do dia (e, se pedido, no total). Silencioso se der erro. */
async function bump(cfg, fetchImpl, clock, opts, event, { total } = {}) {
  try {
    const m = createCmd(cfg, fetchImpl, opts);
    const list = [];
    if (event && EVENTS.includes(event)) list.push(['HINCRBY', K.ct(dayKey(clock())), event, '1']);
    if (total) list.push(['HINCRBY', K.total, total.field, String(total.by)]);
    if (list.length) await m.pipeline(list);
  } catch (_) { /* métrica não derruba nada */ }
}

module.exports = { K, TABS, EVENTS, dayKey, bump, BR_OFFSET };
