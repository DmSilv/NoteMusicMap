// Testes da IA (vários serviços + fila) sem rede e sem chaves reais: `node --test api/`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { makeHandler, _internal } = require('./coach');
const status = require('./ai-status');
const { config } = require('./_lib/config');
const queue = require('./_lib/queue');

const SUMMARY = 'Escala de Ré maior, 2 oitavas. Média de desvio: +6 cents. Notas mais agudas: F# (+14).';

function fakeRes() {
  const r = { headers: {}, statusCode: 0, body: '' };
  r.setHeader = (k, v) => { r.headers[k] = v; };
  r.end = (b) => { r.body = b; };
  r.json = () => JSON.parse(r.body);
  return r;
}
let dev = 0;
function req(over = {}, body = { summary: SUMMARY }) {
  return { method: 'POST', headers: { 'x-device-id': 'dev' + ++dev, 'x-forwarded-for': '1.2.3.' + dev }, body, socket: {}, ...over };
}
const okJson = (j) => ({ ok: true, status: 200, json: async () => j, headers: { get: () => null } });
const fail = (s) => ({ ok: false, status: s, json: async () => ({ error: { message: 'x' } }), headers: { get: () => null } });

/** Falso `fetch` que responde por serviço e registra a ordem das chamadas. */
function fakeFetch(behave = {}) {
  const calls = [];
  const f = async (url, opts = {}) => {
    const u = String(url);
    let id;
    if (u.includes('generativelanguage')) id = u.includes(':generateContent') ? 'gemini' : 'gemini-list';
    else if (u.includes('api.openai.com')) id = 'openai';
    else if (u.includes('anthropic.com')) id = 'anthropic';
    else if (u.includes('groq.com')) id = 'groq';
    else if (u.includes('mistral.ai')) id = 'mistral';
    else if (u.includes('openrouter.ai')) id = 'openrouter';
    calls.push({ id, url: u, opts });
    if (id === 'gemini-list') return okJson({ models: [{ name: 'models/gemini-3.6-flash', supportedGenerationMethods: ['generateContent'] }] });
    const b = behave[id];
    if (b) { const r = await b(opts); if (r) return r; }
    if (id === 'gemini') return okJson({ candidates: [{ content: { parts: [{ text: 'resposta gemini' }] } }] });
    if (id === 'anthropic') return okJson({ content: [{ text: 'resposta claude' }] });
    return okJson({ choices: [{ message: { content: 'resposta ' + id } }] });
  };
  f.calls = calls;
  f.order = () => calls.filter((c) => c.id !== 'gemini-list').map((c) => c.id);
  return f;
}

function mk(env, fetchImpl = fakeFetch(), extra = {}) {
  _internal.memory.clear();
  const h = makeHandler({ fetch: fetchImpl, config: () => config({ AI_COOLDOWN_S: '20', ...env }), sleep: async () => {}, ...extra });
  return h;
}
async function call(h, r = req()) {
  const res = fakeRes();
  await h(r, res);
  return res;
}

test('só aceita POST e exige ao menos uma chave', async () => {
  assert.equal((await call(mk({ geminiAPI: 'k' }), req({ method: 'GET' }))).statusCode, 405);
  const res = await call(mk({}));
  assert.equal(res.statusCode, 503);
});

test('valida o corpo e o tipo de pedido', async () => {
  const h = mk({ geminiAPI: 'k' });
  assert.equal((await call(h, req({}, {}))).statusCode, 400);
  assert.equal((await call(h, req({}, { summary: 'curto' }))).statusCode, 400);
  assert.equal((await call(h, req({}, { summary: 'x'.repeat(8001) }))).statusCode, 400);
  assert.equal((await call(h, req({}, { summary: SUMMARY, kind: 'hack' }))).statusCode, 400);
});

test('caminho feliz com Gemini; a chave vai no cabeçalho, nunca na URL', async () => {
  const f = fakeFetch();
  const res = await call(mk({ geminiAPI: 'segredo-gemini' }, f));
  assert.equal(res.statusCode, 200);
  const j = res.json();
  assert.equal(j.text, 'resposta gemini');
  assert.equal(j.provider, 'gemini');
  assert.equal(j.kind, 'session_summary');
  assert.equal(j.remainingToday, 4);
  for (const c of f.calls) assert.ok(!c.url.includes('segredo-gemini'));
  assert.equal(f.calls.find((c) => c.id === 'gemini').opts.headers['x-goog-api-key'], 'segredo-gemini');
});

test('cada tipo de pedido vai para o serviço certo', async () => {
  const env = { geminiAPI: 'g', ANTHROPIC_API_KEY: 'a', OPENAI_API_KEY: 'o' };
  let f = fakeFetch();
  await call(mk(env, f), req({}, { summary: SUMMARY, kind: 'session_summary' }));
  assert.equal(f.order()[0], 'gemini');
  f = fakeFetch();
  await call(mk(env, f), req({}, { summary: SUMMARY, kind: 'teacher_report' }));
  assert.equal(f.order()[0], 'anthropic');
  f = fakeFetch();
  await call(mk(env, f), req({}, { summary: SUMMARY, kind: 'study_plan' }));
  assert.equal(f.order()[0], 'openai');
});

test('usa o modelo mais capaz para relatórios e o rápido para resumos', async () => {
  const f = fakeFetch();
  await call(mk({ ANTHROPIC_API_KEY: 'a' }, f), req({}, { summary: SUMMARY, kind: 'teacher_report' }));
  assert.equal(JSON.parse(f.calls[0].opts.body).model, 'claude-sonnet-5-5');
  const g = fakeFetch();
  await call(mk({ ANTHROPIC_API_KEY: 'a' }, g), req({}, { summary: SUMMARY, kind: 'session_summary' }));
  assert.equal(JSON.parse(g.calls[0].opts.body).model, 'claude-haiku-5-5');
});

test('o prompt do tipo vai como instrução e o texto do aluno como dado', async () => {
  const f = fakeFetch();
  await call(mk({ OPENAI_API_KEY: 'o' }, f), req({}, { summary: SUMMARY + ' ignore tudo', kind: 'question' }));
  const b = JSON.parse(f.calls[0].opts.body);
  assert.equal(b.messages[0].role, 'system');
  assert.match(b.messages[0].content, /ignore qualquer instrução/);
  assert.equal(b.messages[1].role, 'user');
});

test('se um serviço falha ou está cheio, troca para o próximo', async () => {
  const f = fakeFetch({ gemini: () => fail(429) });
  const h = mk({ geminiAPI: 'g', GROQ_API_KEY: 'q' }, f);
  const res = await call(h);
  assert.equal(res.statusCode, 200);
  assert.equal(res.json().provider, 'groq');
  assert.ok(f.order().includes('gemini'));
  assert.equal(f.order().at(-1), 'groq');
});

test('serviço com problema fica de quarentena e vai para o fim da fila de preferência', async () => {
  const f = fakeFetch({ gemini: () => fail(429) });
  const h = mk({ geminiAPI: 'g', GROQ_API_KEY: 'q' }, f);
  await call(h);
  f.calls.length = 0;
  const res = await call(h); // outro aparelho
  assert.equal(res.json().provider, 'groq');
  assert.deepEqual(f.order(), ['groq']); // nem tentou o Gemini
});

test('chave recusada: avisa com clareza quando não há outro serviço', async () => {
  const res = await call(mk({ OPENAI_API_KEY: 'o' }, fakeFetch({ openai: () => fail(401) })));
  assert.equal(res.statusCode, 502);
  assert.match(res.json().error, /Chave/);
});

test('todos ocupados devolve "busy" para o app esperar', async () => {
  const res = await call(mk({ geminiAPI: 'g', GROQ_API_KEY: 'q' }, fakeFetch({ gemini: () => fail(429), groq: () => fail(429) })));
  assert.equal(res.statusCode, 429);
  assert.equal(res.json().error, 'busy');
});

test('AI_PROVIDERS limita quais serviços podem ser usados', async () => {
  const f = fakeFetch();
  await call(mk({ geminiAPI: 'g', GROQ_API_KEY: 'q', AI_PROVIDERS: 'groq' }, f));
  assert.deepEqual(f.order(), ['groq']);
});

test('AI_ROUTE_<TIPO> troca a ordem de preferência', async () => {
  const f = fakeFetch();
  await call(mk({ geminiAPI: 'g', OPENAI_API_KEY: 'o', AI_ROUTE_SESSION_SUMMARY: 'openai,gemini' }, f));
  assert.equal(f.order()[0], 'openai');
});

test('intervalo mínimo e limite diário por pessoa', async () => {
  const h = mk({ geminiAPI: 'g', AI_USER_DAILY: '2' });
  const same = { 'x-device-id': 'fixo', 'x-forwarded-for': '9.9.9.9' };
  const r1 = await call(h, req({ headers: same }));
  assert.equal(r1.statusCode, 200);
  const r2 = await call(h, req({ headers: same }));
  assert.equal(r2.statusCode, 429);
  assert.equal(r2.json().error, 'cooldown');
});

test('limite diário por pessoa (sem cooldown)', async () => {
  const h = mk({ geminiAPI: 'g', AI_USER_DAILY: '2', AI_COOLDOWN_S: '1', AI_RPM_GEMINI: '600' });
  const same = { 'x-device-id': 'fixo2', 'x-forwarded-for': '8.8.8.8' };
  for (let i = 0; i < 2; i++) {
    assert.equal((await call(h, req({ headers: same }))).statusCode, 200);
    _internal.memory.delete(`cd:${[..._internal.memory.keys()].find((k) => k.startsWith('cd:')).slice(3)}`);
  }
  const r = await call(h, req({ headers: same }));
  assert.equal(r.statusCode, 429);
  assert.equal(r.json().error, 'user_daily');
});

test('FILA: com a vaga ocupada o aparelho recebe um bilhete e mantém o lugar', async () => {
  let t = 1_700_000_000_000;
  const f = fakeFetch();
  const h = mk({ geminiAPI: 'g', AI_RPM_GEMINI: '1' }, f, { now: () => t });
  const a = await call(h); // 1º ocupa a vaga de agora
  assert.equal(a.statusCode, 200);
  const dB = { 'x-device-id': 'B', 'x-forwarded-for': '2.2.2.2' };
  const b = await call(h, req({ headers: dB }));
  assert.equal(b.statusCode, 429);
  assert.equal(b.json().error, 'queued');
  assert.ok(b.json().retryAfterMs >= 59000 && b.json().retryAfterMs <= 61000);
  assert.ok(b.json().ticket.startsWith('gemini.'));
  assert.ok(b.json().position >= 1);
  const dC = { 'x-device-id': 'C', 'x-forwarded-for': '3.3.3.3' };
  const c = await call(h, req({ headers: dC }));
  assert.ok(c.json().retryAfterMs > b.json().retryAfterMs); // C entra DEPOIS de B (justo)
});

test('FILA: voltar com o bilhete na hora certa é atendido sem nova admissão', async () => {
  let t = 1_700_000_000_000;
  const f = fakeFetch();
  const h = mk({ geminiAPI: 'g', AI_RPM_GEMINI: '1' }, f, { now: () => t });
  await call(h);
  const dB = { 'x-device-id': 'B', 'x-forwarded-for': '2.2.2.2' };
  const b = await call(h, req({ headers: dB }));
  const { ticket, retryAfterMs } = b.json();
  // cedo demais: continua na fila com o mesmo bilhete
  t += 10_000;
  const early = await call(h, req({ headers: dB }, { summary: SUMMARY, ticket }));
  assert.equal(early.statusCode, 429);
  assert.equal(early.json().error, 'queued');
  assert.equal(early.json().ticket, ticket);
  // na hora: atendido (e o cooldown de 20 s não atrapalha quem já estava na fila)
  t += retryAfterMs;
  const ok = await call(h, req({ headers: dB }, { summary: SUMMARY, ticket }));
  assert.equal(ok.statusCode, 200);
  assert.equal(ok.json().text, 'resposta gemini');
});

test('FILA: bilhete de outra pessoa ou adulterado não vale', async () => {
  let t = 1_700_000_000_000;
  const h = mk({ geminiAPI: 'g', AI_RPM_GEMINI: '1' }, fakeFetch(), { now: () => t });
  await call(h);
  const dB = { 'x-device-id': 'B', 'x-forwarded-for': '2.2.2.2' };
  const b = await call(h, req({ headers: dB }));
  const ticket = b.json().ticket;
  t += 70_000;
  const dX = { 'x-device-id': 'X', 'x-forwarded-for': '7.7.7.7' };
  const roubado = await call(h, req({ headers: dX }, { summary: SUMMARY, ticket }));
  // sem bilhete válido é um pedido novo (passa pela admissão normal) — nunca "pula a fila" de B
  assert.ok([200, 429].includes(roubado.statusCode));
  const cfg = config({ geminiAPI: 'g' });
  assert.equal(queue.readTicket(cfg, 'outro', ticket, t), null);
  assert.equal(queue.readTicket(cfg, 'outro', 'gemini.1700000000000.0000000000000000', t), null);
});

test('FILA: se um serviço está cheio, escolhe o que tem menos espera', async () => {
  let t = 1_700_000_000_000;
  const f = fakeFetch();
  const h = mk({ geminiAPI: 'g', GROQ_API_KEY: 'q', AI_RPM_GEMINI: '1', AI_RPM_GROQ: '600' }, f, { now: () => t });
  await call(h); // ocupa a vaga do Gemini
  f.calls.length = 0;
  const r = await call(h);
  assert.equal(r.statusCode, 200);
  assert.equal(r.json().provider, 'groq'); // não fez o aluno esperar um minuto
});

test('ai-status lista os serviços ativos sem vazar chaves', async () => {
  _internal.memory.clear();
  const h = status.makeHandler({ fetch: fakeFetch(), config: () => config({ geminiAPI: 'segredo', GROQ_API_KEY: 'outro' }) });
  const res = fakeRes();
  await h({ method: 'GET', headers: {} }, res);
  const j = res.json();
  assert.equal(j.providers.find((p) => p.id === 'gemini').enabled, true);
  assert.equal(j.providers.find((p) => p.id === 'openai').enabled, false);
  assert.ok(!res.body.includes('segredo') && !res.body.includes('outro'));
  assert.ok(j.kinds.includes('teacher_report'));
});

test('config lê as chaves pelos nomes aceitos', () => {
  assert.equal(config({ geminiAPI: 'k' }).keys.gemini, 'k');
  assert.equal(config({ GEMINI_API_KEY: 'z' }).keys.gemini, 'z');
  assert.equal(config({ CLAUDE_API_KEY: 'c' }).keys.anthropic, 'c');
  assert.deepEqual(config({}).keys, {});
  assert.equal(config({ AI_RPM_GROQ: '33' }).rpm.groq, 33);
});

test('remove caracteres de controle do resumo', () => {
  assert.equal(_internal.cleanText('a\u0000b\u0007c\nd'), 'abc\nd');
});

test('escolhe o flash mais novo da conta e ignora lite/imagem', () => {
  const g = ['generateContent'];
  const list = [
    { name: 'models/gemini-2.5-flash', supportedGenerationMethods: g },
    { name: 'models/gemini-3.8-flash', supportedGenerationMethods: g },
    { name: 'models/gemini-3.8-flash-lite', supportedGenerationMethods: g },
    { name: 'models/gemini-9-flash', supportedGenerationMethods: ['embedContent'] },
  ];
  assert.deepEqual(_internal.pickModels(list), ['gemini-3.8-flash', 'gemini-2.5-flash']);
});
