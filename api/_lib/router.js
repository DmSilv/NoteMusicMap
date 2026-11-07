'use strict';
// REGRA DE NEGÓCIO: qual IA atende cada tipo de pedido, e quando trocar de serviço.
//
//  - cada tipo de pedido tem uma ordem de preferência e um "nível" de modelo
//    (rápido e barato para resumos; mais capaz para relatórios e planos);
//  - só entram os serviços que têm chave configurada (e não foram desligados em AI_PROVIDERS);
//  - um serviço "doente" (muitas falhas, cota esgotada, chave recusada) fica de
//    quarentena por um tempo e só é usado em último caso;
//  - a ordem pode ser trocada por variável: AI_ROUTE_TEACHER_REPORT=anthropic,openai.

const KINDS = {
  session_summary: { tier: 'fast', maxTokens: 2600, prefs: ['gemini', 'groq', 'mistral', 'openai', 'anthropic', 'openrouter'] },
  question: { tier: 'fast', maxTokens: 1200, prefs: ['gemini', 'groq', 'openai', 'mistral', 'anthropic', 'openrouter'] },
  teacher_report: { tier: 'smart', maxTokens: 2800, prefs: ['anthropic', 'openai', 'gemini', 'mistral', 'groq', 'openrouter'] },
  study_plan: { tier: 'smart', maxTokens: 2400, prefs: ['openai', 'anthropic', 'gemini', 'mistral', 'groq', 'openrouter'] },
};

function isKind(k) {
  return Object.prototype.hasOwnProperty.call(KINDS, k);
}

/** Quarentena (s) por tipo de problema. */
const COOLDOWN_S = { auth: 600, busy: 45, error: 20 };

async function isOpen(store, id) {
  return (await store.get(`hb:${id}`)) != null;
}

async function markBad(store, id, status) {
  await store.set(`hb:${id}`, status, COOLDOWN_S[status] || 20);
}

/**
 * Serviços na ordem em que devem ser tentados para [kind]: os saudáveis na ordem
 * de preferência e, no fim, os de quarentena (último recurso).
 */
async function candidates(kind, cfg, store) {
  const spec = KINDS[kind];
  const order = cfg.routes[kind] || spec.prefs;
  const usable = order.filter((id) => cfg.keys[id] && (!cfg.allow || cfg.allow.includes(id)));
  // inclui os que sobraram da lista padrão (caso a rota personalizada seja curta)
  for (const id of spec.prefs) {
    if (!usable.includes(id) && cfg.keys[id] && (!cfg.allow || cfg.allow.includes(id))) usable.push(id);
  }
  const good = [], bad = [];
  for (const id of usable) ((await isOpen(store, id)) ? bad : good).push(id);
  return { ids: [...good, ...bad], healthy: good.length, tier: spec.tier, maxTokens: spec.maxTokens };
}

module.exports = { KINDS, isKind, candidates, markBad, isOpen, COOLDOWN_S };
