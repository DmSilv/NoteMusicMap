// Painel mais preciso: saúde, custos, coortes, período anterior, horas, limpeza e erros do servidor.
// `node --test api/painel_precisao.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const link = require('./link');
const admin = require('./admin');
const stats = require('./stats');
const errors = require('./errors');
const { serverError } = require('./_lib/error_store');
const { config } = require('./_lib/config');
const { hashes, memory } = require('./_lib/store');
const { resetMem } = require('./_lib/store_cmd');

const A = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
function code(seed) {
  let p = '';
  let x = seed;
  for (let i = 0; i < 7; i++) { p += A[x % 32]; x = Math.floor(x / 32) + 7 + i; }
  let s = 0;
  for (let i = 0; i < 7; i++) s += A.indexOf(p[i]) * (2 * i + 1);
  const c = p + A[s % 32];
  return `${c.slice(0, 4)}-${c.slice(4)}`;
}
const PROF = code(11111), ALU = code(22222), ALU2 = code(33333);
const secret = (c) => crypto.createHash('sha256').update('s' + c).digest('hex');
const KEY = 'chave-de-admin-de-teste';
const DAY = 86400000;
const NOW0 = 1_800_000_000_000;
let NOW = NOW0;
let ipN = 0;

function fakeRes() {
  const r = { headers: {}, statusCode: 0, body: '' };
  r.setHeader = (k, v) => { r.headers[k] = v; };
  r.end = (b) => { r.body = b; };
  r.json = () => JSON.parse(r.body);
  return r;
}
function mk(env = {}) {
  hashes.clear(); memory.clear(); resetMem();
  NOW = NOW0;
  const deps = { config: () => config({ ADMIN_KEY: KEY, ERRORS_DAILY_CAP: '500', ...env }), allowMemory: true, fetch: async () => ({ status: 200 }), now: () => NOW };
  return { l: link.makeHandler(deps), a: admin.makeHandler(deps), s: stats.makeHandler(deps), e: errors.makeHandler(deps), deps };
}
async function post(h, body, headers = {}, method = 'POST') {
  const res = fakeRes();
  await h({ method, headers: { 'x-forwarded-for': '7.7.7.' + ++ipN, ...headers }, body, query: {}, socket: {} }, res);
  return res;
}
const adm = (H, body) => post(H.a, body, { authorization: 'Bearer ' + KEY });
const user = (H, who, body) => post(H.l, { code: who, secret: secret(who), ...body });
const dev = (n) => `dispositivo${String(n).padStart(8, '0')}`;
const report = (over = {}) => ({ id: dev(1), c: 'APP-00', s: 'action', w: 'Agenda', d: 'StateError: x', v: 'v1', pl: 'android-chrome', in: 'pwa', ...over });
const statsOpen = (H, id, tabs = []) => post(H.s, { t: 'open', id, d: { pl: 'android-chrome', in: 'pwa', v: 'v1' }, tabs });
const statsFull = async (H) => (await post(H.s, undefined, { authorization: 'Bearer ' + KEY }, 'GET')).json();
async function vincula(H, aluno = ALU) {
  await user(H, aluno, { action: 'sync' });
  assert.equal((await user(H, PROF, { action: 'link', role: 'teacher', other: aluno, name: 'Ana' })).statusCode, 200);
}

// ---------------- Erros do próprio servidor ----------------
test('erro do servidor entra no painel de bugs como plataforma "server", higienizado', async () => {
  const H = mk();
  await serverError({ cfg: H.deps.config(), fetchImpl: H.deps.fetch, clock: H.deps.now, allowMemory: true }, 'link', new Error('falha com K7QM-4TXK e ana@x.com'));
  const l = (await adm(H, { action: 'bugs' })).json();
  assert.equal(l.items.length, 1);
  assert.equal(l.items[0].where, 'API link');
  assert.deepEqual(l.items[0].platforms, { server: 1 });
  assert.equal(l.items[0].msg.includes('K7QM'), false);
  assert.equal(l.items[0].msg.includes('@'), false);
  const h = (await adm(H, { action: 'health' })).json();
  assert.equal(h.serverToday, 1);
  assert.equal(h.level, 'yellow');
  assert.ok(h.reasons.includes('Falha no servidor hoje'));
});

test('erro do servidor respeita a chave de desligar e nunca lança', async () => {
  const H = mk({ ERRORS_DISABLED: '1' });
  await serverError({ cfg: H.deps.config(), fetchImpl: H.deps.fetch, clock: H.deps.now, allowMemory: true }, 'admin', new Error('x'));
  assert.equal((await adm(H, { action: 'bugs' })).json().items.length, 0);
  await serverError({ cfg: null }, 'x', new Error('y')); // config quebrada: só ignora
});

// ---------------- Saúde ----------------
test('saúde: verde sem erros; vermelho com erro grave; amarelo com muitos erros por abertura', async () => {
  const H = mk();
  let h = (await adm(H, { action: 'health' })).json();
  assert.equal(h.level, 'green');
  assert.equal(h.cleanDays, 13, 'sem erro grave nos 13 dias anteriores');
  assert.equal(h.per100, null, 'poucas aberturas: sem taxa');

  await post(H.e, report({ c: 'APP-99', s: 'critical', w: 'Início' }));
  h = (await adm(H, { action: 'health' })).json();
  assert.equal(h.level, 'red');
  assert.deepEqual(h.reasons, ['Erro grave hoje']);

  const Y = mk();
  Y.deps.now = () => NOW;
  const today = new Date(NOW - 3 * 3600000).toISOString().slice(0, 10);
  hashes.set(`st:ct:d:${today}`, new Map([['open', '100']]));
  // 8 erros espalhados pelo dia (sem pico nas últimas 2 horas)
  hashes.set(`er:d:${today}`, new Map([['total', '8'], ['action', '8'], ['h10', '2'], ['h12', '2'], ['h14', '2'], ['h16', '2']]));
  h = (await adm(Y, { action: 'health' })).json();
  assert.equal(h.per100, 8);
  assert.equal(h.level, 'yellow');
});

test('saúde: pico nas últimas 2 horas fica vermelho; dias sem erro grave são contados', async () => {
  const H = mk();
  for (let i = 0; i < 6; i++) await post(H.e, report({ id: dev(i + 1), w: 'T' + i, s: 'action' }));
  const h = (await adm(H, { action: 'health' })).json();
  assert.equal(h.level, 'red');
  assert.ok(h.reasons.includes('Pico de erros nas últimas 2 horas'));
  // erro grave há 3 dias: a sequência limpa é de 2 dias (ontem e anteontem)
  const G = mk();
  NOW -= 3 * DAY;
  await post(G.e, report({ c: 'APP-99', s: 'critical' }));
  NOW = NOW0;
  const g = (await adm(G, { action: 'health' })).json();
  assert.equal(g.cleanDays, 2);
  assert.equal(g.level, 'green');
});

// ---------------- Custos ----------------
test('custos: estimativa por tipo, total do mês, projeção e orçamento', async () => {
  const H = mk();
  const d = (n) => new Date(NOW - 3 * 3600000 - n * DAY).toISOString().slice(0, 10);
  hashes.set(`st:ct:d:${d(0)}`, new Map([['open', '100'], ['new', '10'], ['lesson', '5'], ['rev10', '50']]));
  hashes.set(`st:ct:d:${d(1)}`, new Map([['open', '50']]));
  for (let i = 0; i < 4; i++) await post(H.e, report({ id: dev(i + 1), w: 'T' + i }));
  const c = (await adm(H, { action: 'costs' })).json();
  assert.equal(c.budget, 500000);
  const k = Object.fromEntries(c.kinds.map((x) => [x.name, x.n]));
  assert.equal(k['Aberturas'], 150 * 11 + 10 * 1);
  assert.equal(k['Consultas de vínculo'], 50 * 10 * 1);
  assert.equal(k['Aulas enviadas'], 30);
  assert.equal(k['Relatórios de erro'], 4 * 23);
  assert.equal(c.month, c.kinds.reduce((a, x) => a + x.n, 0));
  assert.equal(c.perDay.length, 30);
  assert.ok(c.projection > 0 && c.pct > 0);
  assert.ok(c.note.includes('Estimativa'));
});

test('consulta barata é amostrada (1 em 10) para estimar o polling', async () => {
  const H = mk();
  await vincula(H);
  const orig = Math.random;
  try {
    Math.random = () => 0.05;
    await user(H, ALU, { action: 'rev' });
    await user(H, ALU, { action: 'rev' });
    Math.random = () => 0.5;
    await user(H, ALU, { action: 'rev' });
  } finally { Math.random = orig; }
  const today = new Date(NOW - 3 * 3600000).toISOString().slice(0, 10);
  assert.equal(hashes.get(`st:ct:d:${today}`).get('rev10'), '2');
});

test('tarefa validada e horário pego entram nos contadores do dia', async () => {
  const H = mk();
  await vincula(H);
  await user(H, PROF, { action: 'verdict', other: ALU, lesson: 'aula0001', task: 'k1', verdict: 'ok' });
  await user(H, PROF, { action: 'avail_put', slot: { id: 'h1', s: NOW + 3 * DAY, d: 60, u: NOW } });
  await user(H, ALU, { action: 'avail_take', other: PROF, slot: 'h1' });
  const today = new Date(NOW - 3 * 3600000).toISOString().slice(0, 10);
  const ct = hashes.get(`st:ct:d:${today}`);
  assert.equal(ct.get('verdict'), '1');
  assert.equal(ct.get('pick'), '1');
});

// ---------------- Estatísticas: período anterior e horas ----------------
test('estatísticas: aberturas por hora, período anterior e hora da geração', async () => {
  const H = mk();
  // aparelho A abriu há 10 dias (semana anterior à atual); B hoje; C há 40 dias (mês anterior)
  NOW = NOW0 - 10 * DAY; await statsOpen(H, 'aaaaaaaaaaaaaaaa01');
  NOW = NOW0 - 40 * DAY; await statsOpen(H, 'cccccccccccccccc03');
  NOW = NOW0; await statsOpen(H, 'bbbbbbbbbbbbbbbb02');
  await statsOpen(H, 'bbbbbbbbbbbbbbbb02');
  const j = await statsFull(H);
  assert.equal(j.wau, 1, 'só B nesta semana');
  assert.equal(j.wauPrev, 1, 'A na semana anterior');
  assert.equal(j.mau, 2, 'A e B nos últimos 30 dias');
  assert.equal(j.mauPrev, 1, 'C no mês anterior');
  assert.equal(j.generatedAt, NOW);
  const hoje = j.series.at(-1);
  assert.equal(hoje.hours.length, 24);
  assert.equal(hoje.hours.reduce((a, b) => a + b, 0), hoje.opens, 'as horas somam as aberturas do dia');
  assert.equal(hoje.opens, 2);
});

// ---------------- Coortes ----------------
test('coortes: perfis agrupados por semana de entrada, com retorno em D1, D7 e D30', async () => {
  const H = mk();
  NOW = NOW0 - 40 * DAY; // todos entram na mesma semana
  for (const c of [ALU, ALU2, PROF]) await user(H, c, { action: 'sync' });
  NOW = NOW0 - 38 * DAY; await user(H, ALU, { action: 'sync' }); // voltou dia 2
  NOW = NOW0 - 20 * DAY; await user(H, ALU2, { action: 'sync' }); // voltou dia 20
  NOW = NOW0;
  const k = (await adm(H, { action: 'kpis' })).json();
  assert.ok(k.cohorts.length >= 1);
  const c = k.cohorts[0];
  assert.match(c.week, /^\d{4}-\d{2}-\d{2}$/);
  assert.equal(c.size, 3);
  assert.deepEqual([c.d1.back, c.d1.of], [2, 3], 'ALU e ALU2 voltaram depois do dia 1');
  assert.deepEqual([c.d7.back, c.d7.of], [1, 3], 'só ALU2 voltou depois do dia 7');
  assert.deepEqual([c.d30.back, c.d30.of], [0, 3]);
});

// ---------------- Limpeza ----------------
test('limpeza: bug sem ocorrência há mais de 90 dias sai do Redis', async () => {
  const H = mk();
  await post(H.e, report());
  const fp = (await adm(H, { action: 'bugs' })).json().items[0].fp;
  assert.ok(hashes.get(`er:f:${fp}`));
  NOW += 100 * DAY;
  await post(H.e, report({ id: dev(2), w: 'Outra tela' })); // um bug novo, ainda vivo
  const l = (await adm(H, { action: 'bugs', days: 90 })).json();
  assert.equal(l.gc, 1);
  assert.equal(hashes.get(`er:f:${fp}`), undefined);
  assert.equal(l.items.length, 1);
});

test('as novas ações do painel exigem a chave de admin', async () => {
  const H = mk();
  for (const action of ['health', 'costs', 'kpis']) {
    assert.equal((await post(H.a, { action }, { authorization: 'Bearer errada' })).statusCode, 401, action);
  }
});
