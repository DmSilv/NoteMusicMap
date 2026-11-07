'use strict';
// Configuração lida das variáveis de ambiente da Vercel. NENHUMA chave fica no código.

const crypto = require('node:crypto');

/** Nomes aceitos para a chave de cada serviço (o primeiro preenchido vale). */
const PROVIDER_KEYS = {
  gemini: ['geminiAPI', 'GEMINI_API_KEY', 'GEMINI_API', 'GOOGLE_API_KEY'],
  openai: ['OPENAI_API_KEY', 'openaiAPI', 'CHATGPYAPI', 'chatgpyAPI', 'CHATGPTAPI', 'chatgptAPI', 'CHATGPT_API_KEY'],
  anthropic: ['ANTHROPIC_API_KEY', 'anthropicAPI', 'CLAUDE_API_KEY', 'claudeAPI', 'CLAUDEAPI'],
  groq: ['GROQ_API_KEY', 'groqAPI'],
  openrouter: ['OPENROUTER_API_KEY', 'openrouterAPI'],
  mistral: ['MISTRAL_API_KEY', 'mistralAPI'],
};

const LABELS = {
  gemini: 'Gemini',
  openai: 'OpenAI',
  anthropic: 'Claude',
  groq: 'Groq',
  openrouter: 'OpenRouter',
  mistral: 'Mistral',
};

/** Pedidos por minuto que cada serviço aguenta no plano gratuito/básico (ajustável). */
const DEFAULT_RPM = { gemini: 8, openai: 20, anthropic: 20, groq: 20, openrouter: 10, mistral: 10 };

const num = (v, d) => {
  const n = Number(v);
  return Number.isFinite(n) && n > 0 ? n : d;
};

const list = (v) =>
  String(v || '')
    .split(',')
    .map((x) => x.trim().toLowerCase())
    .filter(Boolean);

function config(env = process.env) {
  const keys = {};
  for (const [id, names] of Object.entries(PROVIDER_KEYS)) {
    for (const n of names) {
      if (env[n]) {
        keys[id] = env[n];
        break;
      }
    }
  }
  const allow = list(env.AI_PROVIDERS);
  const rpm = {};
  for (const id of Object.keys(PROVIDER_KEYS)) {
    rpm[id] = num(env[`AI_RPM_${id.toUpperCase()}`], id === 'gemini' ? num(env.AI_RPM, DEFAULT_RPM.gemini) : DEFAULT_RPM[id]);
  }
  const routes = {};
  for (const kind of ['session_summary', 'question', 'teacher_report', 'study_plan']) {
    const r = list(env[`AI_ROUTE_${kind.toUpperCase()}`]);
    if (r.length) routes[kind] = r;
  }
  const secret =
    env.AI_TICKET_SECRET ||
    crypto.createHash('sha256').update(Object.values(keys).sort().join('|') || 'sem-chave').digest('hex');
  return {
    keys,
    allow: allow.length ? allow : null,
    rpm,
    routes,
    userDaily: num(env.AI_USER_DAILY, 5),
    cooldownS: num(env.AI_COOLDOWN_S, 20),
    rpd: num(env.AI_RPD, 200),
    maxInlineWaitMs: num(env.AI_MAX_WAIT_MS, 8000),
    ticketSecret: secret,
    redisUrl: env.UPSTASH_REDIS_REST_URL || env.KV_REST_API_URL || '',
    redisToken: env.UPSTASH_REDIS_REST_TOKEN || env.KV_REST_API_TOKEN || '',
    geminiModel: env.GEMINI_MODEL || '',
    env,
  };
}

module.exports = { config, PROVIDER_KEYS, LABELS, DEFAULT_RPM };
