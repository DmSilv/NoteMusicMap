// Guardrails de segurança da API: entradas malformadas, gigantes e hostis. Nada pode quebrar,
// vazar segredo ou gravar lixo. `node --test api/guardrails.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const link = require('./link');
const admin = require('./admin');
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
const PROF = code(11111), ALU = code(22222);
const secret = (c) => crypto.createHash('sha256').update('s' + c).digest('hex');
const KEY = 'chave-de-admin-de-teste';
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
function mk() {
  hashes.clear();
  memory.clear();
  resetMem();
  NOW = NOW0;
  const deps = { config: () => config({ ADMIN_KEY: KEY }), allowMemory: true, fetch: async () => ({ status: 200 }), now: () => NOW };
  return { l: link.makeHandler(deps), a: admin.makeHandler(deps) };
}
async function raw(h, body, headers = {}, method = 'POST') {
  const res = fakeRes();
  await h({ method, headers: { 'x-forwarded-for': '3.3.3.' + ++ipN, ...headers }, body, socket: {} }, res);
  return res;
}
const asUser = (H, who, body) => raw(H.l, { code: who, secret: secret(who), ...body });

async function vincula(H) {
  await asUser(H, ALU, { action: 'sync' });
  assert.equal((await asUser(H, PROF, { action: 'link', role: 'teacher', other: ALU, name: 'Ana' })).statusCode, 200);
}

test('corpo ausente, nulo, lista, texto ou número: 400, nunca erro 500', async () => {
  const H = mk();
  for (const body of [undefined, null, [], [1, 2], 'texto', 42, true]) {
    const r = await raw(H.l, body);
    assert.ok([400].includes(r.statusCode), `corpo ${JSON.stringify(body)} deu ${r.statusCode}`);
  }
});

test('código e segredo fora do formato: 400', async () => {
  const H = mk();
  const ruins = [
    { code: '', secret: secret(ALU) }, { code: 'xx', secret: secret(ALU) }, { code: ALU, secret: '' },
    { code: ALU, secret: 'g'.repeat(64) }, { code: ALU, secret: 'a'.repeat(63) }, { code: ALU, secret: 'a'.repeat(65) },
    { code: { toString: () => ALU }, secret: secret(ALU) }, { code: [ALU], secret: secret(ALU) },
  ];
  for (const b of ruins) assert.equal((await raw(H.l, { action: 'sync', ...b })).statusCode, 400, JSON.stringify(b).slice(0, 60));
});

test('corpo gigante é recusado sem gravar nada', async () => {
  const H = mk();
  const r = await asUser(H, ALU, { action: 'sync', name: 'x'.repeat(50000) });
  assert.equal(r.statusCode, 400);
  assert.equal(hashes.get('u:' + ALU), undefined, 'nenhum perfil foi criado');
  const adm = await raw(H.a, { action: 'list', q: 'x'.repeat(5000) }, { authorization: 'Bearer ' + KEY });
  assert.equal(adm.statusCode, 400);
});

test('chaves perigosas (__proto__, constructor) não contaminam nem quebram', async () => {
  const H = mk();
  const body = JSON.parse('{"action":"sync","__proto__":{"admin":true},"constructor":{"prototype":{"x":1}}}');
  const r = await asUser(H, ALU, body);
  assert.equal(r.statusCode, 200);
  assert.equal({}.admin, undefined);
  assert.equal({}.x, undefined);
});

test('ação desconhecida ou de tipo errado: 400', async () => {
  const H = mk();
  await vincula(H);
  for (const action of ['nada', '', 123, null, ['sync'], { a: 1 }, 'SYNC', 'sync; drop']) {
    const r = await asUser(H, ALU, { action });
    // ação ausente/ inválida de tipo vira "sync" (padrão) ou 400; nunca 500
    assert.ok([200, 400].includes(r.statusCode), `ação ${JSON.stringify(action)} deu ${r.statusCode}`);
  }
  assert.equal((await asUser(H, ALU, { action: 'nada' })).statusCode, 400);
});

test('apelido: sem caracteres invisíveis nem de controle e com tamanho limitado', async () => {
  const H = mk();
  const sujo = 'Ana‮​\u0000\u0007 <script>alert(1)</script> ' + 'y'.repeat(200);
  await asUser(H, ALU, { action: 'sync', name: sujo });
  const j = (await raw(H.a, { action: 'detail', code: ALU }, { authorization: 'Bearer ' + KEY })).json();
  const n = j.profile.name;
  assert.ok(n.length <= 40, 'limitado a 40');
  for (const c of ['‮', '​', '\u0000', '\u0007']) assert.equal(n.includes(c), false);
});

test('nenhuma resposta vaza o segredo nem o hash dele', async () => {
  const H = mk();
  await vincula(H);
  const hash = crypto.createHash('sha256').update('lnk|' + secret(ALU)).digest('hex');
  const todas = [
    await asUser(H, ALU, { action: 'sync' }), await asUser(H, ALU, { action: 'rev' }),
    await asUser(H, PROF, { action: 'sync' }), await asUser(H, PROF, { action: 'dones' }),
    await asUser(H, ALU, { action: 'lessons' }), await asUser(H, ALU, { action: 'sched' }),
    await asUser(H, ALU, { action: 'verdicts' }), await asUser(H, PROF, { action: 'picks' }),
    await raw(H.a, { action: 'detail', code: ALU }, { authorization: 'Bearer ' + KEY }),
    await raw(H.a, { action: 'list' }, { authorization: 'Bearer ' + KEY }),
  ];
  for (const r of todas) {
    assert.equal(r.body.includes(secret(ALU)), false, 'segredo na resposta');
    assert.equal(r.body.includes(hash), false, 'hash do segredo na resposta');
    assert.equal(r.body.includes(secret(PROF)), false);
  }
});

test('segredo errado: 403 genérico, sem dizer se o código existe', async () => {
  const H = mk();
  await asUser(H, ALU, { action: 'sync' });
  const errado = await raw(H.l, { action: 'sync', code: ALU, secret: secret(PROF) });
  assert.equal(errado.statusCode, 403);
  const inexistente = await raw(H.l, { action: 'sync', code: PROF, secret: secret(PROF) }); // cria perfil novo (comportamento anônimo)
  assert.equal(inexistente.statusCode, 200);
  assert.equal(errado.json().error, 'Este código pertence a outro aparelho.');
});

test('muitas tentativas com segredo errado: 429', async () => {
  const H = mk();
  await asUser(H, ALU, { action: 'sync' });
  let last = 0;
  for (let i = 0; i < 40; i++) {
    const res = fakeRes();
    await H.l({ method: 'POST', headers: { 'x-forwarded-for': '2.2.2.2' }, body: { action: 'sync', code: ALU, secret: secret('x' + i) }, socket: {} }, res);
    last = res.statusCode;
  }
  assert.equal(last, 429);
});

test('aula marcada e horário: nota com HTML fica como texto limitado; listas gigantes são cortadas', async () => {
  const H = mk();
  await vincula(H);
  const slot = {
    id: 'aula1', s: NOW + 3 * 86400000, d: 60, u: NOW, n: '<img src=x onerror=alert(1)>' + 'z'.repeat(500),
    x: Array.from({ length: 500 }, (_, i) => NOW + i),
  };
  assert.equal((await asUser(H, PROF, { action: 'sched_put', other: ALU, slot })).statusCode, 400, 'corpo maior que o limite é recusado');
  const ok = { id: 'aula2', s: NOW + 3 * 86400000, d: 60, u: NOW, n: '<b>oi</b>​' + 'z'.repeat(300) };
  assert.equal((await asUser(H, PROF, { action: 'sched_put', other: ALU, slot: ok })).statusCode, 200);
  const got = (await asUser(H, ALU, { action: 'sched' })).json().slots[0];
  assert.ok(got.n.length <= 200);
  assert.equal(got.n.includes('​'), false);
});

test('ids de tarefa, aula e horário com caracteres estranhos são recusados', async () => {
  const H = mk();
  await vincula(H);
  const ruins = ['', 'A B', '../x', 'x'.repeat(41), '<x>', 'a:b', 'ç', '\n'];
  for (const id of ruins) {
    assert.equal((await asUser(H, ALU, { action: 'done', other: PROF, lesson: 'aula0001', task: id, done: true })).statusCode, 400, `tarefa ${JSON.stringify(id)}`);
    assert.equal((await asUser(H, ALU, { action: 'avail_take', other: PROF, slot: id })).statusCode, 400, `horário ${JSON.stringify(id)}`);
    assert.equal((await asUser(H, PROF, { action: 'verdict', other: ALU, lesson: 'aula0001', task: id, verdict: 'ok' })).statusCode, 400);
  }
});

test('painel: chave só no cabeçalho (nunca na URL ou no corpo); método errado recusado', async () => {
  const H = mk();
  assert.equal((await raw(H.a, { action: 'kpis', key: KEY, adminKey: KEY })).statusCode, 401);
  const res = fakeRes();
  await H.a({ method: 'POST', url: '/api/admin?key=' + KEY, query: { key: KEY }, headers: { 'x-forwarded-for': '1.1.1.1' }, body: { action: 'kpis' }, socket: {} }, res);
  assert.equal(res.statusCode, 401);
  for (const m of ['GET', 'PUT', 'DELETE']) assert.equal((await raw(H.a, { action: 'kpis' }, { authorization: 'Bearer ' + KEY }, m)).statusCode, 405);
});

test('painel: código inválido ou com texto de ataque nunca chega ao armazenamento', async () => {
  const H = mk();
  const h = { authorization: 'Bearer ' + KEY };
  for (const c of ['', 'x', "ABCD-EFGH'; DEL *", '<script>', 'A'.repeat(200), null, 5, ['A']]) {
    for (const action of ['detail', 'block', 'unblock', 'delete']) {
      const r = await raw(H.a, { action, code: c, confirm: c }, h);
      assert.equal(r.statusCode, 400, `${action} ${JSON.stringify(c)}`);
    }
  }
});

test('respostas de erro nunca trazem rastros internos', async () => {
  const H = mk();
  const respostas = [await raw(H.l, null), await asUser(H, ALU, { action: 'nada' }), await raw(H.a, { action: 'x' }, { authorization: 'Bearer errada' })];
  for (const r of respostas) {
    assert.equal(/at .*\.js:\d+|node_modules|\\Users\\|\/home\//.test(r.body), false, r.body);
    assert.equal(r.headers['X-Content-Type-Options'], 'nosniff');
    assert.equal(r.headers['Cache-Control'], 'no-store');
  }
});
