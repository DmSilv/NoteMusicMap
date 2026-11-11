// Testes da aba "Visitantes" do painel (quem usa sem cadastro): `node --test api/visitors.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const stats = require('./stats');
const link = require('./link');
const admin = require('./admin');
const { config } = require('./_lib/config');
const { hashes, memory } = require('./_lib/store');
const { resetMem } = require('./_lib/store_cmd');

const KEY = 'chave-de-admin-de-teste';
let NOW = Date.UTC(2026, 10, 9, 15, 0, 0); // 09/11/2026 12:00 em Brasília
let ipN = 0;
const DAY = 86400000;

function fakeRes() {
  const r = { headers: {}, statusCode: 0, body: '' };
  r.setHeader = (k, v) => { r.headers[k] = v; };
  r.end = (b) => { r.body = b; };
  r.json = () => JSON.parse(r.body);
  return r;
}
function mk() {
  hashes.clear(); memory.clear(); resetMem();
  NOW = Date.UTC(2026, 10, 9, 15, 0, 0);
  const cfg = config({ ADMIN_KEY: KEY });
  const deps = { config: () => cfg, allowMemory: true, fetch: async () => ({ status: 200 }), now: () => NOW, random: () => 0.5 };
  return { s: stats.makeHandler(deps), l: link.makeHandler(deps), a: admin.makeHandler(deps) };
}
const rid = () => crypto.randomBytes(12).toString('hex');
async function ping(H, body) {
  const res = fakeRes();
  await H.s({ method: 'POST', headers: { 'x-forwarded-for': '7.7.7.' + ++ipN }, body, socket: {} }, res);
  return res;
}
async function visitors(H) {
  const res = fakeRes();
  await H.a({ method: 'POST', headers: { 'x-forwarded-for': '5.5.5.' + ++ipN, authorization: 'Bearer ' + KEY }, body: { action: 'visitors' }, socket: {} }, res);
  return res;
}
const x = (mic, inst) => ({ os: 'android', sc: 'p', lg: 'pt', th: 'escuro', tc: 'sim', mic, nt: 'nd' });

test('conta aparelhos de hoje por origem, novos, voltaram e sem marca', async () => {
  const H = mk();
  const a = rid(), b = rid(), c = rid(), d = rid();
  // ontem: a e b abriram
  NOW -= DAY;
  await ping(H, { t: 'open', id: a, d: { pl: 'android-chrome', in: 'browser', v: 'v1', o: 'yt', x: x('sim') } });
  await ping(H, { t: 'open', id: b, d: { pl: 'ios-safari', in: 'browser', v: 'v1', o: 'ig', x: x('nd') } });
  NOW += DAY;
  // hoje: a volta; c e d chegam novos (um pelo Instagram, outro sem marca)
  await ping(H, { t: 'open', id: a, d: { pl: 'android-chrome', in: 'browser', v: 'v1', o: 'yt', x: x('sim') }, tabs: ['tuner', 'metronome'] });
  await ping(H, { t: 'open', id: c, d: { pl: 'android-chrome', in: 'pwa', v: 'v1', o: 'ig', x: x('sim') }, tabs: ['tuner'] });
  await ping(H, { t: 'open', id: d, d: { pl: 'android-chrome', in: 'browser', v: 'v1', x: x('nao') } });
  const j = (await visitors(H)).json();
  assert.equal(j.ok, true);
  assert.equal(j.users, 3);
  assert.equal(j.news, 2);
  assert.equal(j.returning, 1);
  assert.equal(j.yesterday.users, 2);
  assert.equal(j.backFromYesterday, 1);
  const hoje = j.days[6];
  assert.equal(hoje.origins.yt, 1);
  assert.equal(hoje.origins.ig, 1);
  assert.equal(j.days[5].origins.ig, 1);
  assert.equal(j.tabs.tuner, 2);
  assert.equal(j.tabs.metronome, 1);
  assert.equal(j.perms.mic.sim, 2);
  assert.equal(j.perms.mic.nao, 1);
  assert.equal(j.perms.in.pwa, 1);
  assert.equal(j.uniq7, 4);
});

test('sem cadastro = aparelhos de hoje menos perfis ativos hoje (estimativa)', async () => {
  const H = mk();
  for (let i = 0; i < 5; i++) await ping(H, { t: 'open', id: rid(), d: { pl: 'android-chrome', in: 'browser', v: 'v1', x: x('nd') } });
  let j = (await visitors(H)).json();
  assert.equal(j.users, 5);
  assert.equal(j.noProfileEst, 5);
  assert.equal(j.profilesActive, 0);
});

test('só o admin vê a aba Visitantes', async () => {
  const H = mk();
  const res = fakeRes();
  await H.a({ method: 'POST', headers: { 'x-forwarded-for': '5.5.5.1', authorization: 'Bearer errada' }, body: { action: 'visitors' }, socket: {} }, res);
  assert.equal(res.statusCode, 401);
});
