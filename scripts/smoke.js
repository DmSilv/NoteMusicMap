// Teste de fumaça: os fluxos principais do app de ponta a ponta, rodando as funções do servidor de verdade (sem rede, sem Redis real).
// Uso: node scripts/smoke.js            -> fluxos da API (marcar, pegar horário, tarefa, aula online, remarcar, trocar, pausar, painel)
//      node scripts/smoke.js --web      -> também confere o build (build/web) e, se houver Chrome, se o app abre de verdade
// Falha (código 1) no primeiro passo que quebrar e diz qual foi. Roda no CI a cada envio. Ver docs/PLANO_DE_TESTES.md (seção 4).
'use strict';
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const link = require('../api/link');
const admin = require('../api/admin');
const { config } = require('../api/_lib/config');
const { hashes, memory } = require('../api/_lib/store');
const { resetMem } = require('../api/_lib/store_cmd');

const ROOT = path.join(__dirname, '..');
const NOW = 1_800_000_000_000;
const DAY = 86400000;
const KEY = 'chave-de-fumaca';
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
const PROF = code(101), ALU = code(202), ALU2 = code(303);
const secret = (c) => crypto.createHash('sha256').update('fumaca' + c).digest('hex');
const MEET = 'https://meet.google.com/abc-defg-hij';

let ipN = 0;
const fake = () => { const r = { headers: {}, statusCode: 0, body: '' }; r.setHeader = (k, v) => { r.headers[k] = v; }; r.end = (b) => { r.body = b; }; r.json = () => JSON.parse(r.body); return r; };
hashes.clear(); memory.clear(); resetMem();
const cfg = config({ ADMIN_KEY: KEY });
const deps = { config: () => cfg, allowMemory: true, fetch: async () => ({ status: 200 }), now: () => NOW };
const L = link.makeHandler(deps);
const ADM = admin.makeHandler(deps);
async function as(who, body) { const r = fake(); await L({ method: 'POST', headers: { 'x-forwarded-for': '7.7.7.' + (++ipN % 250) }, body: { code: who, secret: secret(who), ...body }, socket: {} }, r); return r; }
async function adm(body) { const r = fake(); await ADM({ method: 'POST', headers: { 'x-forwarded-for': '8.8.8.' + (++ipN % 250), authorization: 'Bearer ' + KEY }, body, socket: {} }, r); return r; }
const slot = (id, extra = {}) => ({ id, s: NOW + 3 * DAY, d: 60, u: NOW, ...extra });
const mine = async (who) => (await as(who, { action: 'sched' })).json().slots;

let passed = 0;
const steps = [];
const step = (name, fn) => steps.push([name, fn]);

step('vincular professor e alunos', async () => {
  for (const [who, nm] of [[PROF, 'Prof'], [ALU, 'Ana'], [ALU2, 'Bia']]) assert.equal((await as(who, { action: 'sync', name: nm })).statusCode, 200);
  assert.equal((await as(PROF, { action: 'link', role: 'teacher', other: ALU })).statusCode, 200);
  assert.equal((await as(PROF, { action: 'link', role: 'teacher', other: ALU2 })).statusCode, 200);
});

step('marcar aula toda semana: o aluno vê na agenda', async () => {
  assert.equal((await as(PROF, { action: 'sched_put', other: ALU, slot: slot('aula1', { w: 1 }) })).statusCode, 200);
  const r = await mine(ALU);
  assert.equal(r.length, 1);
  assert.equal(r[0].w, 1);
});

step('horário livre: o aluno pega, o professor vê e só o primeiro leva', async () => {
  assert.equal((await as(PROF, { action: 'avail_put', slot: slot('livre1', { s: NOW + 4 * DAY }) })).statusCode, 200);
  const open = (await as(ALU, { action: 'avail', other: PROF })).json().open;
  assert.equal(open.length, 1);
  // Os dois pegam AO MESMO TEMPO: só um pode levar (a trava "o primeiro leva").
  const [a, b] = await Promise.all([
    as(ALU, { action: 'avail_take', other: PROF, slot: 'livre1' }),
    as(ALU2, { action: 'avail_take', other: PROF, slot: 'livre1' }),
  ]);
  assert.deepEqual([a.statusCode, b.statusCode].sort(), [200, 409], 'exatamente um aluno leva o horário');
  const winner = a.statusCode === 200 ? ALU : ALU2;
  const late = await as(winner === ALU ? ALU2 : ALU, { action: 'avail_take', other: PROF, slot: 'livre1' });
  assert.equal(late.statusCode, 409, 'depois de pego, ninguém mais leva');
  const picks = (await as(PROF, { action: 'picks' })).json().slots;
  assert.equal(picks.length, 1);
  assert.equal(picks[0].sc, winner);
  assert.ok((await mine(winner)).some((x) => x.id === picks[0].id), 'o horário pego entra na agenda do aluno');
});

step('passar tarefa: a aula chega para o aluno', async () => {
  const lesson = { id: 'ls01', t: NOW - 3600000, d: 3000, tasks: [{ id: 'tk1', title: 'Escala de Dó', kind: 'scale', st: 0, pc: 0 }], notes: ['Treinar devagar'] };
  assert.equal((await as(PROF, { action: 'lesson', other: ALU, lesson })).statusCode, 200);
  const l = (await as(ALU, { action: 'lessons' })).json().lessons;
  assert.equal(l.length, 1);
  assert.equal(l[0].tasks[0].title, 'Escala de Dó');
  assert.equal((await as(ALU2, { action: 'lessons' })).json().lessons.length, 0, 'outro aluno não vê');
});

step('aula online: sem a chave não liga; com a chave o link chega ao aluno', async () => {
  assert.equal((await as(PROF, { action: 'meet_set', link: MEET })).statusCode, 403, 'sem a chave deve recusar');
  assert.equal((await adm({ action: 'feature_grant', id: 'aula_online', code: PROF })).statusCode, 200);
  assert.equal((await as(PROF, { action: 'meet_set', link: MEET })).statusCode, 200);
  assert.equal((await as(PROF, { action: 'meet_set', link: 'http://inseguro.exemplo/x' })).statusCode, 400, 'só https');
  assert.equal((await as(PROF, { action: 'sched_put', other: ALU2, slot: slot('online1', { s: NOW + 5 * DAY, m: 'o', l: MEET }) })).statusCode, 200);
  const o = (await mine(ALU2)).find((x) => x.id === 'online1');
  assert.equal(o.m, 'o');
  assert.equal(o.l, MEET);
});

step('remarcar só uma data: cancela aquela e cria a aula avulsa', async () => {
  const regra = slot('aula1', { w: 1 });
  const data = regra.s + 7 * DAY;
  assert.equal((await as(PROF, { action: 'sched_put', other: ALU, slot: { ...regra, x: [data], u: NOW + 1 } })).statusCode, 200);
  assert.equal((await as(PROF, { action: 'sched_put', other: ALU, slot: slot('avulsa1', { s: data + 3600000, u: NOW + 1 }) })).statusCode, 200);
  const r = await mine(ALU);
  assert.deepEqual(r.find((x) => x.id === 'aula1').x, [data]);
  assert.equal(r.find((x) => x.id === 'avulsa1').w, undefined);
});

step('trocar o aluno da aula: o novo recebe e o anterior deixa de ver', async () => {
  assert.equal((await as(PROF, { action: 'sched_put', other: ALU2, slot: slot('troca1', { s: NOW + 6 * DAY }) })).statusCode, 200);
  assert.equal((await as(PROF, { action: 'sched_put', other: ALU, slot: slot('troca1', { s: NOW + 6 * DAY, u: NOW + 1 }) })).statusCode, 200);
  assert.ok((await mine(ALU)).some((x) => x.id === 'troca1'));
  assert.ok(!(await mine(ALU2)).some((x) => x.id === 'troca1'));
});

step('pausar: a aula aparece como cancelada para o aluno', async () => {
  assert.equal((await as(PROF, { action: 'sched_put', other: ALU, slot: slot('troca1', { s: NOW + 6 * DAY, c: 1, u: NOW + 2 }) })).statusCode, 200);
  assert.equal((await mine(ALU)).find((x) => x.id === 'troca1').c, 1);
});

step('painel: custos e relatório de contas respondem', async () => {
  const c = await adm({ action: 'costs' });
  assert.equal(c.statusCode, 200);
  const r = await adm({ action: 'cost_report', users: 1000, fx: 5.5, basis: 'sim', m: c.json().measured });
  assert.equal(r.statusCode, 200);
  assert.ok(r.json().scenarios.length >= 4);
  assert.equal((await adm({ action: 'funnel' })).statusCode, 200);
});

step('proteções: sem a chave o painel recusa e entrada inválida volta 400', async () => {
  const r = fake();
  await ADM({ method: 'POST', headers: { 'x-forwarded-for': '6.6.6.6', authorization: 'Bearer errada' }, body: { action: 'costs' }, socket: {} }, r);
  assert.equal(r.statusCode, 401);
  assert.equal((await as(PROF, { action: 'sched_put', other: ALU, slot: { id: '!', s: 1 } })).statusCode, 400);
});

step('projeto: no máximo 12 funções da Vercel e vercel.json válido', async () => {
  const fns = fs.readdirSync(path.join(ROOT, 'api')).filter((f) => f.endsWith('.js') && !f.endsWith('.test.js'));
  assert.ok(fns.length <= 12, `${fns.length} funções (limite do plano Hobby: 12)`);
  JSON.parse(fs.readFileSync(path.join(ROOT, 'vercel.json'), 'utf8'));
});

// ---------------- Build web (opcional, --web) ----------------
const WEB = path.join(ROOT, 'build', 'web');
const types = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json', '.wasm': 'application/wasm', '.png': 'image/png', '.css': 'text/css' };
function serveWeb() {
  return new Promise((resolve) => {
    const srv = http.createServer((req, res) => {
      const u = new URL(req.url, 'http://x');
      if (u.pathname.startsWith('/api/')) { res.setHeader('Content-Type', 'application/json'); return res.end('{"ok":true}'); }
      let f = path.join(WEB, u.pathname === '/' ? 'index.html' : u.pathname);
      if (!f.startsWith(WEB) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) f = path.join(WEB, 'index.html');
      res.setHeader('Content-Type', types[path.extname(f)] || 'application/octet-stream');
      res.end(fs.readFileSync(f));
    }).listen(0, () => resolve(srv));
  });
}
function findChrome() {
  const c = [process.env.CHROME_BIN, '/usr/bin/google-chrome', '/usr/bin/google-chrome-stable', '/usr/bin/chromium', '/usr/bin/chromium-browser',
    'C:/Program Files/Google/Chrome/Application/chrome.exe', 'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe'];
  return c.filter(Boolean).find((p) => fs.existsSync(p)) || null;
}

/** Abre a página no Chrome (sem janela), espera o Flutter desenhar e devolve { glass, errors }. Usa o protocolo de depuração (CDP). */
async function openInChrome(chrome, url) {
  const os = require('node:os');
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'smoke-'));
  const proc = require('node:child_process').spawn(chrome, ['--headless=new', '--no-sandbox', '--disable-gpu', '--use-gl=swiftshader', '--enable-unsafe-swiftshader',
    '--remote-debugging-port=0', `--user-data-dir=${profile}`, '--window-size=390,844', 'about:blank'], { stdio: 'ignore' });
  try {
    const portFile = path.join(profile, 'DevToolsActivePort');
    for (let i = 0; i < 100 && !fs.existsSync(portFile); i++) await new Promise((r) => setTimeout(r, 200));
    assert.ok(fs.existsSync(portFile), 'o Chrome não iniciou');
    const port = fs.readFileSync(portFile, 'utf8').split(/\r?\n/)[0].trim();
    const list = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
    const page = list.find((t) => t.type === 'page');
    const ws = new WebSocket(page.webSocketDebuggerUrl);
    await new Promise((res, rej) => { ws.onopen = res; ws.onerror = () => rej(new Error('sem conexão com o Chrome')); });
    let id = 0; const wait = {}; const errors = [];
    ws.onmessage = (m) => {
      const j = JSON.parse(m.data);
      if (j.id && wait[j.id]) { wait[j.id](j.result); delete wait[j.id]; }
      if (j.method === 'Runtime.exceptionThrown') errors.push(String((j.params.exceptionDetails.exception || {}).description || j.params.exceptionDetails.text).split(/\r?\n/)[0]);
    };
    const send = (method, params = {}) => new Promise((res) => { const n = ++id; wait[n] = res; ws.send(JSON.stringify({ id: n, method, params })); });
    await send('Runtime.enable'); await send('Page.enable');
    await send('Page.navigate', { url });
    let glass = false;
    for (let i = 0; i < 60 && !glass; i++) {
      await new Promise((r) => setTimeout(r, 1000));
      const r = await send('Runtime.evaluate', { expression: "!!document.querySelector('flt-glass-pane')" });
      glass = !!(r && r.result && r.result.value);
    }
    if (glass) await new Promise((r) => setTimeout(r, 1500));
    ws.close();
    return { glass, errors };
  } finally { proc.kill(); try { fs.rmSync(profile, { recursive: true, force: true }); } catch (_) { /* Windows pode segurar o arquivo */ } }
}
if (process.argv.includes('--web')) {
  step('build web: arquivos essenciais existem', async () => {
    for (const f of ['index.html', 'main.dart.js', 'flutter_bootstrap.js', 'version.json', 'manifest.json', 'admin.html']) {
      assert.ok(fs.existsSync(path.join(WEB, f)), `falta build/web/${f} (rode flutter build web --release)`);
    }
    assert.ok(fs.statSync(path.join(WEB, 'main.dart.js')).size > 500000, 'main.dart.js pequeno demais');
  });
  step('build web: o app abre no Chrome e desenha a tela', async () => {
    const chrome = findChrome();
    if (!chrome) { console.log('   (sem Chrome neste computador: passo pulado)'); return; }
    const srv = await serveWeb();
    try {
      const url = `http://127.0.0.1:${srv.address().port}/`;
      const html = await openInChrome(chrome, url);
      assert.ok(html.glass, 'o Flutter não montou a tela (sem flt-glass-pane)');
      assert.ok(html.errors.length === 0, 'erros no console da página: ' + html.errors.slice(0, 2).join(' | '));
    } finally { srv.close(); }
  });
}

(async () => {
  for (const [name, fn] of steps) {
    try { await fn(); passed++; console.log('  ok   ' + name); } catch (e) {
      console.log('  FALHOU ' + name + '\n         ' + String(e && e.message || e).split('\n')[0]);
      console.log(`\nFumaça: ${passed} de ${steps.length} passos passaram.`);
      process.exit(1);
    }
  }
  console.log(`\nFumaça: ${passed} de ${steps.length} passos passaram.`);
  process.exit(0);
})();
