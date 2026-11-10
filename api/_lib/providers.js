'use strict';
// Um adaptador por serviço de IA. Todos recebem {system, prompt} e devolvem
// {status: 'ok'|'busy'|'auth'|'error', text?, model?, retryAfterMs?}.

const OPENAI_LIKE = {
  openai: { url: 'https://api.openai.com/v1/chat/completions', fast: 'gpt-4o-mini', smart: 'gpt-4o', tokensField: 'max_completion_tokens' },
  groq: { url: 'https://api.groq.com/openai/v1/chat/completions', fast: 'llama-3.1-8b-instant', smart: 'llama-3.3-70b-versatile', tokensField: 'max_tokens' },
  openrouter: { url: 'https://openrouter.ai/api/v1/chat/completions', fast: 'meta-llama/llama-3.3-70b-instruct:free', smart: 'meta-llama/llama-3.3-70b-instruct:free', tokensField: 'max_tokens' },
  mistral: { url: 'https://api.mistral.ai/v1/chat/completions', fast: 'mistral-small-latest', smart: 'mistral-large-latest', tokensField: 'max_tokens' },
};
const ANTHROPIC = { url: 'https://api.anthropic.com/v1/messages', fast: 'claude-haiku-5-5', smart: 'claude-sonnet-5-5' };

/** Modelo de cada serviço/nível; dá para trocar por variável: MODEL_OPENAI_FAST, etc. */
function modelFor(id, tier, env = {}) {
  const o = env[`MODEL_${id.toUpperCase()}_${tier.toUpperCase()}`];
  if (o) return o;
  if (id === 'anthropic') return ANTHROPIC[tier];
  return OPENAI_LIKE[id] && OPENAI_LIKE[id][tier];
}

function classify(status) {
  if (status === 401 || status === 403) return 'auth';
  if (status === 429 || status === 503 || status === 529) return 'busy';
  return 'error';
}

async function post(fetchImpl, url, headers, body, timeoutMs) {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), timeoutMs);
  try {
    return await fetchImpl(url, { method: 'POST', signal: ctl.signal, headers: { 'Content-Type': 'application/json', ...headers }, body: JSON.stringify(body) });
  } finally {
    clearTimeout(timer);
  }
}

function retryAfter(r) {
  const h = r.headers && r.headers.get && r.headers.get('retry-after');
  const s = Number(h);
  return Number.isFinite(s) && s > 0 ? Math.min(s, 60) * 1000 : 15000 + Math.floor(Math.random() * 5000);
}

async function callOpenAiLike(id, a) {
  const spec = OPENAI_LIKE[id];
  const model = modelFor(id, a.tier, a.env);
  const r = await post(a.fetchImpl, spec.url, { Authorization: `Bearer ${a.key}` }, {
    model,
    temperature: 0.4,
    [spec.tokensField]: a.maxTokens,
    messages: [{ role: 'system', content: a.system }, { role: 'user', content: a.prompt }],
  }, a.timeoutMs);
  if (!r.ok) return { status: classify(r.status), httpStatus: r.status, retryAfterMs: retryAfter(r), model };
  const data = await r.json();
  const choice = (data.choices || [])[0] || {};
  const text = String(choice.message?.content || '').trim();
  return text ? { status: 'ok', text, model, truncated: choice.finish_reason === 'length' } : { status: 'error', model };
}

async function callAnthropic(a) {
  const model = modelFor('anthropic', a.tier, a.env);
  const r = await post(a.fetchImpl, ANTHROPIC.url, { 'x-api-key': a.key, 'anthropic-version': '2023-06-01' }, {
    model,
    max_tokens: a.maxTokens,
    temperature: 0.4,
    system: a.system,
    messages: [{ role: 'user', content: a.prompt }],
  }, a.timeoutMs);
  if (!r.ok) return { status: classify(r.status), httpStatus: r.status, retryAfterMs: retryAfter(r), model };
  const data = await r.json();
  const text = (data.content || []).map((p) => p.text || '').join('').trim();
  return text ? { status: 'ok', text, model, truncated: data.stop_reason === 'max_tokens' } : { status: 'error', model };
}

// ---- Gemini: descobre na própria conta o modelo "flash" mais novo ----
const FALLBACK_GEMINI = ['gemini-flash-latest', 'gemini-3.8-flash', 'gemini-2.5-flash'];
const versionOf = (n) => {
  const m = /gemini-(\d+(?:\.\d+)?)/.exec(n);
  return m ? parseFloat(m[1]) : 0;
};
function pickModels(list) {
  return (list || [])
    .filter((m) => (m.supportedGenerationMethods || []).includes('generateContent'))
    .map((m) => String(m.name || '').replace(/^models\//, ''))
    .filter((n) => /^gemini-[\d.]+-flash$/.test(n))
    .sort((a, b) => versionOf(b) - versionOf(a));
}
let geminiCache = { at: 0, models: null };
async function geminiModels(a) {
  if (a.env.GEMINI_MODEL) return [a.env.GEMINI_MODEL];
  if (geminiCache.models && Date.now() - geminiCache.at < 3600e3) return geminiCache.models;
  try {
    const r = await a.fetchImpl('https://generativelanguage.googleapis.com/v1beta/models?pageSize=200', { headers: { 'x-goog-api-key': a.key } });
    if (r.ok) {
      const picked = pickModels((await r.json()).models);
      if (picked.length) {
        geminiCache = { at: Date.now(), models: [...picked.slice(0, 3), ...FALLBACK_GEMINI.filter((m) => !picked.includes(m))] };
        return geminiCache.models;
      }
    }
  } catch (_) { /* usa o padrão */ }
  return FALLBACK_GEMINI;
}

async function callGemini(a) {
  let last = { status: 'error' };
  for (const model of await geminiModels(a)) {
    // Modelos que "pensam" gastam parte do limite antes de escrever: sem folga, a resposta é cortada no meio.
    const gen = { temperature: 0.4, maxOutputTokens: Math.min(8192, a.maxTokens * 3) };
    if (/2\.5-flash/.test(model)) gen.thinkingConfig = { thinkingBudget: 0 };
    let r;
    try {
      r = await post(a.fetchImpl,
        `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`,
        { 'x-goog-api-key': a.key },
        { systemInstruction: { parts: [{ text: a.system }] }, contents: [{ role: 'user', parts: [{ text: a.prompt }] }], generationConfig: gen },
        a.timeoutMs);
    } catch (e) {
      last = { status: 'error', model, aborted: e && e.name === 'AbortError' };
      continue;
    }
    if (r.status === 404 || r.status === 400) {
      let why = '';
      try { why = String(((await r.json()).error || {}).message || '').slice(0, 160); } catch (_) { /* sem corpo */ }
      console.error(`gemini ${r.status} (${model}): ${why}`);
      if (/api key|API_KEY/i.test(why)) return { status: 'auth', model };
      last = { status: 'error', model };
      continue; // próximo modelo
    }
    if (!r.ok) {
      const st = classify(r.status);
      if (st === 'auth') return { status: 'auth', model };
      last = { status: st, httpStatus: r.status, retryAfterMs: retryAfter(r), model };
      continue;
    }
    const data = await r.json();
    const parts = data?.candidates?.[0]?.content?.parts;
    const text = (parts || []).map((p) => p.text || '').join('').trim();
    if (text) return { status: 'ok', text, model, truncated: data?.candidates?.[0]?.finishReason === 'MAX_TOKENS' };
    last = { status: 'error', model };
  }
  return last;
}

/** Chama o serviço [id]. Nunca lança: erros viram {status}. */
async function callProvider(id, a) {
  try {
    if (id === 'gemini') return await callGemini(a);
    if (id === 'anthropic') return await callAnthropic(a);
    if (OPENAI_LIKE[id]) return await callOpenAiLike(id, a);
    return { status: 'error' };
  } catch (e) {
    return { status: 'error', aborted: !!(e && e.name === 'AbortError') };
  }
}

/** Se o serviço cortou a resposta, tira a última frase pela metade e avisa (nunca termina no meio da palavra). */
function finishText(text, truncated) {
  const t = String(text || '').trim();
  if (!truncated) return t;
  const lines = t.split('\n');
  // descarta a última linha se ela não termina em pontuação (frase incompleta)
  while (lines.length > 1 && !/[.!?:)\]*_"”»…]$/.test(lines[lines.length - 1].trim())) lines.pop();
  const cut = lines.join('\n').trim();
  return (cut || t) + '\n\n_A resposta foi cortada pelo serviço de IA. Toque em "Analisar de novo" para tentar outra vez._';
}

module.exports = { callProvider, modelFor, pickModels, finishText, OPENAI_LIKE };
