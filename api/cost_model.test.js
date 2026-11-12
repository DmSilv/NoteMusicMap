// Testes da conta de custos (quanto custa manter a plataforma): `node --test api/cost_model.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const cm = require('./_lib/cost_model');
const admin = require('./admin');
const { config } = require('./_lib/config');
const { hashes, memory } = require('./_lib/store');
const { resetMem } = require('./_lib/store_cmd');

const near = (a, b, tol = 0.011) => assert.ok(Math.abs(a - b) <= tol, `${a} não está perto de ${b}`);
const item = (p, key) => p.items.find((x) => x.key === key);

test('1.000 usuários no consumo simulado: tudo dentro dos planos grátis (com aviso na Vercel)', () => {
  const p = cm.project(1000, cm.SIM);
  assert.equal(p.users, 1000);
  assert.equal(p.commands, 387000);
  assert.equal(item(p, 'redis').plan, 'Grátis');
  assert.equal(item(p, 'redis').usd, 0);
  assert.equal(item(p, 'qstash').plan, 'Grátis');
  assert.equal(item(p, 'vercel').plan, 'Hobby (grátis)');
  assert.equal(p.totalUsd, 0);
  assert.ok(p.alerts.some((a) => /Hobby/.test(a)), 'avisa que passou de 100 mil chamadas');
});

test('5.000 usuários: o banco passa do grátis (centavos) e a Vercel ainda cabe no Hobby', () => {
  const p = cm.project(5000, cm.SIM);
  near(item(p, 'redis').usd, ((5000 * 387 - 500000) / 100000) * 0.2);
  assert.equal(item(p, 'redis').plan, 'Pay as you go');
  assert.equal(item(p, 'vercel').plan, 'Hobby (grátis)');
  assert.ok(p.alerts.some((a) => /banco passa do limite/.test(a)));
  near(p.totalUsd, 2.87);
});

test('10.000 usuários: a Vercel precisa do Pro e o total soma os serviços', () => {
  const p = cm.project(10000, cm.SIM);
  assert.equal(item(p, 'vercel').plan, 'Pro');
  near(item(p, 'vercel').usd, 20 + 0.36 * 0.6);
  near(item(p, 'redis').usd, ((10000 * 387 - 500000) / 100000) * 0.2);
  near(p.totalUsd, item(p, 'redis').usd + item(p, 'qstash').usd + item(p, 'vercel').usd);
  assert.ok(p.needsPro);
});

test('uso comercial exige o Pro da Vercel mesmo com poucos usuários', () => {
  const p = cm.project(100, cm.SIM, { commercial: true });
  assert.equal(item(p, 'vercel').plan, 'Pro');
  assert.equal(item(p, 'vercel').usd, 20);
  assert.ok(p.alerts.some((a) => /não comercial/.test(a)));
});

test('reais: usa a cotação informada e o custo por usuário', () => {
  const p = cm.project(10000, cm.SIM, { fx: 5 });
  near(p.totalBrl, p.totalUsd * 5, 0.02);
  assert.ok(p.perUserUsd > 0 && p.perUserUsd < 0.01);
});

test('lembretes acima do limite diário grátis do QStash passam a custar', () => {
  const p = cm.price({ commands: 0, calls: 0, reminders: 45000 * 30 / 10, users: 1, mb: 0 });
  assert.equal(item(p, 'qstash').plan, 'Pay as you go');
  assert.ok(item(p, 'qstash').usd > 0);
});

test('o relatório traz cenários ordenados, o escolhido e o consumo real quando há dados', () => {
  const r = cm.report({ measured: { users30: 100, commands: 50000, calls: 20000, reminders: 300 }, users: 2500, fx: 5.5, basis: 'real' });
  assert.deepEqual(r.scenarios.map((s) => s.users), [100, 1000, 2500, 5000, 10000]);
  assert.equal(r.basis, 'real');
  assert.equal(r.perUser.real.commandsPerUser, 500);
  assert.equal(r.scenarios.find((s) => s.users === 1000).commands, 500000);
  assert.equal(r.now.users30, 100);
  assert.equal(r.now.commands, 50000);
});

test('sem dados suficientes o relatório cai para a simulação e diz isso', () => {
  const r = cm.report({ measured: { users30: 3, commands: 900, calls: 100, reminders: 0 }, users: 1000, basis: 'real' });
  assert.equal(r.realAvailable, false);
  assert.equal(r.basis, 'sim');
  assert.equal(r.perUser.used.commandsPerUser, cm.SIM.commandsPerUser);
});

test('cotação e entradas absurdas são limitadas', () => {
  const r = cm.report({ users: 1000, fx: 9999 });
  assert.equal(r.fx, 20);
  assert.equal(cm.report({ users: 1000, fx: -3 }).fx, 1);
});

// ---- ação do painel ----
const KEY = 'chave-de-admin-de-teste';
const NOW = 1_800_000_000_000;
let ipN = 0;
function fakeRes() { const r = { headers: {}, statusCode: 0, body: '' }; r.setHeader = (k, v) => { r.headers[k] = v; }; r.end = (b) => { r.body = b; }; r.json = () => JSON.parse(r.body); return r; }
function mk() {
  hashes.clear(); memory.clear(); resetMem();
  const cfg = config({ ADMIN_KEY: KEY });
  return admin.makeHandler({ config: () => cfg, allowMemory: true, fetch: async () => ({ status: 200 }), now: () => NOW });
}
async function adm(H, body, key = KEY) {
  const res = fakeRes();
  await H({ method: 'POST', headers: { 'x-forwarded-for': '5.5.5.' + ++ipN, authorization: 'Bearer ' + key }, body, socket: {} }, res);
  return res;
}
const sha = (s) => crypto.createHash('sha256').update(s).digest('hex');

test('painel: costs devolve o que foi medido e cost_report calcula sem consultar o Redis', async () => {
  const H = mk();
  const c = (await adm(H, { action: 'costs' })).json();
  assert.equal(typeof c.measured.users30, 'number');
  assert.ok(['commands', 'calls', 'reminders'].every((k) => typeof c.measured[k] === 'number'));
  const r = await adm(H, { action: 'cost_report', users: 1000, fx: 5.5, basis: 'sim', commercial: false, m: c.measured });
  assert.equal(r.statusCode, 200);
  const j = r.json();
  assert.equal(j.scenarios.find((s) => s.users === 1000).totalUsd, 0);
  assert.ok(j.prices.asOf);
  assert.ok(j.notes.length >= 2);
});

test('painel: cost_report exige a chave e recusa usuários inválidos', async () => {
  const H = mk();
  assert.equal((await adm(H, { action: 'cost_report', users: 1000 }, 'errada')).statusCode, 401);
  assert.equal((await adm(H, { action: 'cost_report', users: 0 })).statusCode, 400);
  assert.equal((await adm(H, { action: 'cost_report', users: 'abc' })).statusCode, 400);
  assert.ok(sha('x').length === 64);
});
