// Relatórios de erro do app e a aba "Bugs" do painel, sem rede: `node --test api/errors.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const errors = require('./errors');
const admin = require('./admin');
const { config } = require('./_lib/config');
const { hashes, memory } = require('./_lib/store');
const { resetMem, memCmd } = require('./_lib/store_cmd');
const { fingerprint, cleanReport, sanitize } = require('./_lib/errors_lib');

const KEY = 'chave-de-admin-de-teste';
const DAY = 86400000;
let NOW = 1_800_000_000_000;
let ipN = 0;

function fakeRes() {
  const r = { headers: {}, statusCode: 0, body: '' };
  r.setHeader = (k, v) => { r.headers[k] = v; };
  r.end = (b) => { r.body = b; };
  r.json = () => JSON.parse(r.body);
  return r;
}
function mk(env = {}) {
  hashes.clear();
  memory.clear();
  resetMem();
  NOW = 1_800_000_000_000;
  const deps = { config: () => config({ ADMIN_KEY: KEY, ...env }), allowMemory: true, fetch: async () => ({ status: 200 }), now: () => NOW };
  return { e: errors.makeHandler(deps), a: admin.makeHandler(deps) };
}
async function post(h, body, headers = {}) {
  const res = fakeRes();
  await h({ method: 'POST', headers: { 'x-forwarded-for': '4.4.4.' + ++ipN, ...headers }, body, socket: {} }, res);
  return res;
}
const dev = (n) => `dispositivo${String(n).padStart(8, '0')}`; // 19 caracteres, [a-z0-9]
const report = (over = {}) => ({
  id: dev(1), c: 'APP-00', s: 'action', w: 'Agenda do professor › Marcar aula', d: 'StateError: quebrou\n#0 f (pacote:a.dart:1:1)',
  v: 'abc1234', pl: 'android-chrome', in: 'pwa', lk: 'online', vw: 'teacher', bc: ['Agenda', 'Marcar aula'], ...over,
});
const send = (H, over) => post(H.e, report(over));
const adm = (H, body) => post(H.a, body, { authorization: 'Bearer ' + KEY });

test('relatório válido é aceito e aparece agrupado no painel', async () => {
  const H = mk();
  const r = await send(H);
  assert.equal(r.statusCode, 200);
  assert.equal(r.json().status, 'new');
  const l = (await adm(H, { action: 'bugs' })).json();
  assert.equal(l.items.length, 1);
  const b = l.items[0];
  assert.equal(b.code, 'APP-00');
  assert.equal(b.n, 1);
  assert.equal(b.devices, 1);
  assert.deepEqual(b.versions, { abc1234: 1 });
  assert.deepEqual(b.platforms, { 'android-chrome': 1 });
  assert.equal(b.trend.length, 14);
  assert.equal(b.trend.at(-1), 1);
  assert.equal(l.summary.today.total, 1);
  assert.equal(l.summary.newToday, 1);
});

test('o mesmo bug agrupa; aparelhos distintos contam uma vez cada', async () => {
  const H = mk();
  await send(H);
  await send(H); // mesmo aparelho
  await send(H, { id: dev(2), v: 'zzz9999', pl: 'ios-safari' });
  const b = (await adm(H, { action: 'bugs' })).json().items;
  assert.equal(b.length, 1);
  assert.equal(b[0].n, 3);
  assert.equal(b[0].devices, 2);
  assert.deepEqual(b[0].versions, { abc1234: 2, zzz9999: 1 });
  assert.deepEqual(b[0].platforms, { 'android-chrome': 2, 'ios-safari': 1 });
});

test('bugs diferentes (outro código ou tela) ficam separados', async () => {
  const H = mk();
  await send(H);
  await send(H, { w: 'Perfil' });
  await send(H, { c: 'NET-01', s: 'info' });
  assert.equal((await adm(H, { action: 'bugs' })).json().items.length, 3);
});

test('privacidade: nada pessoal é guardado, nem o código do aparelho', async () => {
  const H = mk();
  await send(H, { d: 'falha com K7QM-4TXK, ana@exemplo.com, https://x.com/api?code=ABCD-EFGH, tel 11987654321, ' + 'a1'.repeat(32), w: 'Perfil de K7QM-4TXK' });
  const dump = JSON.stringify([...hashes.entries()].map(([k, v]) => [k, [...v.entries()]]));
  for (const bad of ['K7QM-4TXK', 'ana@exemplo.com', '?code=', '11987654321', 'a1a1a1a1', dev(1)]) {
    assert.equal(dump.includes(bad), false, 'vazou: ' + bad);
  }
  const d = (await adm(H, { action: 'bugs' })).json().items[0];
  const det = (await adm(H, { action: 'bug', fp: d.fp })).json();
  assert.ok(det.msg.includes('[código]'));
  assert.ok(det.occurrences[0].dv.length === 8, 'só um apelido curto do aparelho');
});

test('validação: código, gravidade, aparelho, tamanho e corpo', async () => {
  const H = mk();
  for (const bad of [{ c: 'xx' }, { c: 'APP-0' }, { s: 'grave' }, { id: 'curto' }, { id: 'ABC' + dev(1) }]) {
    assert.equal((await send(H, bad)).statusCode, 400, JSON.stringify(bad));
  }
  assert.equal((await post(H.e, null)).statusCode, 400);
  assert.equal((await post(H.e, [])).statusCode, 400);
  assert.equal((await post(H.e, 'texto solto')).statusCode, 400);
  assert.equal((await send(H, { d: 'x'.repeat(9000) })).statusCode, 400, 'corpo acima do limite');
  const ok = await send(H, { d: 'y'.repeat(700) });
  assert.equal(ok.statusCode, 200);
  assert.equal((await adm(H, { action: 'bugs' })).json().items[0].msg.length <= 600, true);
  assert.equal((await H.e({ method: 'GET', headers: {}, socket: {} }, fakeRes())), undefined);
});

test('trilha: só itens válidos entram; valores estranhos são descartados', () => {
  const r = cleanReport(report({ bc: ['Agenda', 'Meu espaço', '<script>', 'x'.repeat(80), 'ok:1', 5, null, ...Array(20).fill('a')], vw: 'admin', lk: 'ONLINE!!', in: 'tv' }));
  assert.deepEqual(r.bc.slice(0, 3), ['Agenda', 'Meu espaço', 'ok:1']);
  assert.ok(r.bc.length <= 10);
  assert.equal(r.vw, '');
  assert.equal(r.lk, '');
  assert.equal(r.in, 'browser');
});

test('limite por aparelho (por hora) e teto global do dia', async () => {
  const H = mk();
  for (let i = 0; i < 10; i++) assert.equal((await send(H, { w: 'T' + i })).statusCode, 200);
  assert.equal((await send(H, { w: 'T11' })).statusCode, 429);
  assert.equal((await send(H, { id: dev(2), w: 'outro aparelho' })).statusCode, 200, 'outro aparelho não é afetado');
  const G = mk({ ERRORS_DAILY_CAP: '3' });
  const out = [];
  for (let i = 0; i < 5; i++) out.push((await send(G, { id: dev(10 + i), w: 'T' + i })).json());
  assert.equal(out.filter((x) => x.dropped).length, 2);
  assert.equal((await adm(G, { action: 'bugs' })).json().items.length, 3);
});

test('chave de desligar: nada é guardado', async () => {
  const H = mk({ ERRORS_DISABLED: '1' });
  const r = await send(H);
  assert.equal(r.statusCode, 200);
  assert.equal(r.json().off, true);
  assert.equal((await adm(H, { action: 'bugs' })).json().items.length, 0);
});

test('modo leve: bug que já se repetiu demais só soma contadores', async () => {
  const H = mk();
  const fp = fingerprint('APP-00', report().w, report().d);
  hashes.set(`er:f:${fp}`, new Map([['n', '250'], ['c', 'APP-00'], ['s', 'action'], ['w', 'x'], ['first', '1'], ['last', '1']]));
  await send(H);
  assert.equal(hashes.get(`er:f:${fp}`).get('n'), '251');
  const det = (await adm(H, { action: 'bug', fp })).json();
  assert.equal(det.occurrences.length, 0, 'sem ocorrência detalhada no modo leve');
});

test('custo: comandos do Redis por evento ficam dentro do orçamento', async () => {
  // Redis "de mentira" que conta comandos e responde pela mesma emulação dos testes.
  let cmds = 0;
  const redis = async (url, init) => {
    const body = JSON.parse(init.body);
    const list = String(url).endsWith('/pipeline') ? body : [body];
    cmds += list.length;
    const out = list.map((c) => ({ result: memCmd(c) }));
    return { ok: true, json: async () => (String(url).endsWith('/pipeline') ? out : out[0]) };
  };
  hashes.clear(); memory.clear(); resetMem();
  const cfg = config({ UPSTASH_REDIS_REST_URL: 'https://redis.exemplo', UPSTASH_REDIS_REST_TOKEN: 't', ADMIN_KEY: KEY });
  const h = errors.makeHandler({ config: () => cfg, fetch: redis, now: () => NOW });
  assert.equal((await post(h, report())).statusCode, 200);
  const novo = cmds;
  cmds = 0;
  assert.equal((await post(h, report({ id: dev(2) }))).statusCode, 200);
  const repetido = cmds;
  assert.ok(novo <= 26, `evento novo usou ${novo} comandos`);
  assert.ok(repetido <= 24, `repetição usou ${repetido} comandos`);
  console.log(`  custo medido: evento novo = ${novo} comandos, repetição = ${repetido}`);
});

// ---------------- Painel: filtros, detalhe, status ----------------
async function seed(H) {
  await send(H, { c: 'APP-00', s: 'critical', w: 'Início', d: 'Falha A', v: 'v1', pl: 'android-chrome' });
  await send(H, { c: 'NET-01', s: 'info', w: 'Agenda', d: 'Falha B', v: 'v2', pl: 'ios-safari', id: dev(2) });
  await send(H, { c: 'DATA-01', s: 'action', w: 'Importar aluno', d: 'Falha C', v: 'v2', pl: 'windows-edge', id: dev(3) });
  return (await adm(H, { action: 'bugs' })).json().items;
}

test('filtros: gravidade, versão, plataforma, código, texto e status', async () => {
  const H = mk();
  await seed(H);
  const q = async (f) => (await adm(H, { action: 'bugs', ...f })).json();
  assert.equal((await q({ sev: 'critical' })).items.length, 1);
  assert.equal((await q({ ver: 'v2' })).items.length, 2);
  assert.equal((await q({ plat: 'windows-edge' })).items.length, 1);
  assert.equal((await q({ code: 'net-01' })).items.length, 1);
  assert.equal((await q({ q: 'importar' })).items.length, 1);
  assert.equal((await q({ q: 'inexistente' })).items.length, 0);
  assert.equal((await q({ status: 'open' })).items.length, 3);
  assert.equal((await q({ status: 'resolved' })).items.length, 0);
  const all = await q({});
  assert.deepEqual(all.filters.versions, ['v1', 'v2']);
  assert.deepEqual(all.filters.codes, ['APP-00', 'DATA-01', 'NET-01']);
  assert.equal(all.summary.criticalOpen, 1);
});

test('período: bug antigo sai da janela de 1 dia mas aparece em 30', async () => {
  const H = mk();
  await send(H, { d: 'antigo' });
  NOW += 10 * DAY;
  await send(H, { d: 'recente', id: dev(2) });
  assert.equal((await adm(H, { action: 'bugs', days: 1 })).json().items.length, 1);
  assert.equal((await adm(H, { action: 'bugs', days: 30 })).json().items.length, 2);
});

test('detalhe traz pilha, trilha, ambiente e as últimas ocorrências', async () => {
  const H = mk();
  await send(H, { bc: ['Meu espaço', 'Agenda', 'Marcar aula'] });
  await send(H, { id: dev(2), v: 'v9', pl: 'ios-safari', in: 'browser' });
  const fp = (await adm(H, { action: 'bugs' })).json().items[0].fp;
  const d = (await adm(H, { action: 'bug', fp })).json();
  assert.equal(d.n, 2);
  assert.equal(d.devices, 2);
  assert.ok(d.msg.includes('StateError'));
  assert.equal(d.occurrences.length, 2);
  assert.deepEqual(d.occurrences[1].bc, ['Meu espaço', 'Agenda', 'Marcar aula']);
  assert.deepEqual(d.installs, { pwa: 1, browser: 1 });
  assert.equal(d.trend.length, 30);
  assert.equal((await adm(H, { action: 'bug', fp: 'nao-existe!' })).statusCode, 400);
  assert.equal((await adm(H, { action: 'bug', fp: '0'.repeat(12) })).statusCode, 404);
});

test('status: visto, ignorado, resolvido, anotação, e volta a novo', async () => {
  const H = mk();
  const [b] = await seed(H);
  for (const status of ['seen', 'ignored', 'resolved', 'new']) {
    const r = await adm(H, { action: 'bug_status', fp: b.fp, status, note: 'nota ' + status });
    assert.equal(r.statusCode, 200);
    const d = (await adm(H, { action: 'bug', fp: b.fp })).json();
    assert.equal(d.status, status);
    assert.equal(d.note, 'nota ' + status);
  }
  assert.equal((await adm(H, { action: 'bug_status', fp: b.fp, status: 'qualquer' })).statusCode, 400);
  assert.equal((await adm(H, { action: 'bug_status', fp: '1'.repeat(12), status: 'seen' })).statusCode, 404);
  const log = (await adm(H, { action: 'log' })).json().items.map((x) => x.a);
  assert.ok(log.includes('bug_resolved'));
});

test('ignorado continua ignorado; novas ocorrências só contam', async () => {
  const H = mk();
  const [b] = await seed(H);
  await adm(H, { action: 'bug_status', fp: b.fp, status: 'ignored' });
  await send(H, { c: 'APP-00', s: 'critical', w: 'Início', d: 'Falha A', v: 'v1', pl: 'android-chrome' });
  const d = (await adm(H, { action: 'bug', fp: b.fp })).json();
  assert.equal(d.status, 'ignored');
  assert.equal(d.n, 2);
});

test('reabertura: só volta se vier de uma versão publicada DEPOIS da correção', async () => {
  const H = mk();
  await send(H, { v: 'v1' });
  const fp = (await adm(H, { action: 'bugs' })).json().items[0].fp;
  NOW += DAY;
  await adm(H, { action: 'bug_status', fp, status: 'resolved' });
  // aparelho com versão antiga (já existia antes da correção): continua resolvido
  NOW += 1000;
  await send(H, { v: 'v1', id: dev(2) });
  assert.equal((await adm(H, { action: 'bug', fp })).json().status, 'resolved');
  // versão nova (primeira vez vista depois da correção): reabre
  NOW += 1000;
  const r = await send(H, { v: 'v2', id: dev(3) });
  assert.equal(r.json().status, 'reopened');
  const d = (await adm(H, { action: 'bug', fp })).json();
  assert.equal(d.status, 'reopened');
  assert.equal((await adm(H, { action: 'bugs', status: 'open' })).json().summary.reopened, 1);
});

test('painel: ações de bugs exigem a chave de admin', async () => {
  const H = mk();
  await send(H);
  for (const action of ['bugs', 'bug', 'bug_status']) {
    const r = await post(H.a, { action, fp: '0'.repeat(12), status: 'seen' }, { authorization: 'Bearer errada' });
    assert.equal(r.statusCode, 401, action);
  }
});

test('sanitize em JS tem a mesma regra do app', () => {
  assert.equal(sanitize('K7QM-4TXK e ana@x.com'), '[código] e [e-mail]');
  assert.equal(sanitize('a​b\u0000c'), 'abc');
  assert.equal(sanitize('x'.repeat(5000)).length, 600);
  assert.equal(sanitize(null), '');
});
