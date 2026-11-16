// Aparelhos da conta (até 5), sem rede: `node --test api/devices.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const account = require('./account');
const link = require('./link');
const devices = require('./_lib/devices');
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
const sec = (ch) => ch.repeat(64).slice(0, 64);
const P1 = code(11111);
const S = ['a', 'b', 'c', 'd', 'e', 'f', '1'].map(sec); // aparelhos 0..6
const MAIL_ENV = { MAIL_API_KEY: 'chave-de-teste', MAIL_FROM: 'Notemusic <nao-responda@exemplo.com>' };

let NOW = Date.UTC(2026, 10, 14, 15, 0, 0);
let sent = [];
let ipN = 0;

function mk() {
  hashes.clear();
  memory.clear();
  resetMem();
  sent = [];
  NOW = Date.UTC(2026, 10, 14, 15, 0, 0);
  const fetch = async (url, init) => {
    if (String(url).includes('resend')) { sent.push(JSON.parse(init.body)); return { ok: true, json: async () => ({}) }; }
    throw new Error('sem rede');
  };
  const deps = { config: () => config(MAIL_ENV), allowMemory: true, fetch, now: () => NOW };
  return { a: account.makeHandler(deps), l: link.makeHandler(deps) };
}
function fakeRes() {
  const r = { headers: {}, statusCode: 0, body: '' };
  r.setHeader = (k, v) => { r.headers[k] = v; };
  r.end = (b) => { r.body = b; };
  r.json = () => JSON.parse(r.body);
  return r;
}
async function call(h, body, headers) {
  const res = fakeRes();
  await h({ method: 'POST', headers: { 'x-forwarded-for': '9.9.9.' + ++ipN, ...(headers || {}) }, body, socket: {} }, res);
  return res;
}
const born = (H, s) => call(H.l, { action: 'sync', code: P1, secret: s });
const rkNew = async (H, s) => (await call(H.a, { action: 'rk_new', code: P1, secret: s })).json().key;
const rkLogin = (H, key, s, extra) => call(H.a, { action: 'rk_login', key, secret: s, ...(extra || {}) });
const list = (H, s) => call(H.a, { action: 'devices', code: P1, secret: s });
const otpOf = (m) => /\b(\d{6})\b/.exec(m.text)[1];

test('perfil antigo (sem lista) tem um aparelho só, o dono', async () => {
  const H = mk();
  await born(H, S[0]);
  const r = await list(H, S[0]);
  assert.equal(r.statusCode, 200);
  const j = r.json();
  assert.equal(j.max, 5);
  assert.equal(j.devices.length, 1);
  assert.equal(j.devices[0].me, true);
  assert.equal(JSON.stringify(j).includes(S[0]), false, 'nunca devolve o segredo');
  assert.equal(JSON.stringify(j).includes(devices.secretHash(S[0])), false, 'nem o hash dele');
});

test('entrar com a chave de 25 acrescenta o aparelho e os dois funcionam', async () => {
  const H = mk();
  await born(H, S[0]);
  const key = await rkNew(H, S[0]);
  assert.equal((await rkLogin(H, key, S[1], { dn: 'Tablet da sala' })).statusCode, 200);
  assert.equal((await call(H.l, { action: 'sync', code: P1, secret: S[0] })).statusCode, 200);
  assert.equal((await call(H.l, { action: 'sync', code: P1, secret: S[1] })).statusCode, 200);
  const j = (await list(H, S[1])).json();
  assert.equal(j.devices.length, 2);
  assert.equal(j.devices.filter((d) => d.me).length, 1);
  assert.equal(j.devices.find((d) => d.me).dn, 'Tablet da sala');
});

test('entrar de novo com o mesmo aparelho não ocupa outra vaga', async () => {
  const H = mk();
  await born(H, S[0]);
  const key = await rkNew(H, S[0]);
  await rkLogin(H, key, S[1]);
  await rkLogin(H, key, S[1]);
  await rkLogin(H, key, S[0]); // o aparelho original usando a chave
  assert.equal((await list(H, S[0])).json().devices.length, 2);
});

test('limite de 5: o sexto aparelho recebe a lista e nada muda até escolher qual tirar', async () => {
  const H = mk();
  await born(H, S[0]);
  const key = await rkNew(H, S[0]);
  for (let i = 1; i < 5; i++) assert.equal((await rkLogin(H, key, S[i])).statusCode, 200);
  const full = await rkLogin(H, key, S[5]);
  assert.equal(full.statusCode, 422);
  assert.equal(full.json().error, 'device_limit');
  assert.equal(full.json().max, 5);
  assert.equal(full.json().devices.length, 5);
  assert.equal(full.json().devices.some((d) => d.me), false);
  assert.equal((await call(H.l, { action: 'sync', code: P1, secret: S[5] })).statusCode, 403, 'o sexto não entrou');
  // escolhe tirar o aparelho 2 e tenta de novo
  const drop = full.json().devices.find((d) => d.id === devices.secretHash(S[2]).slice(0, 10));
  assert.ok(drop);
  const ok = await rkLogin(H, key, S[5], { drop: drop.id });
  assert.equal(ok.statusCode, 200);
  assert.equal((await call(H.l, { action: 'sync', code: P1, secret: S[5] })).statusCode, 200);
  assert.equal((await call(H.l, { action: 'sync', code: P1, secret: S[2] })).statusCode, 403, 'o que saiu perdeu o acesso');
  assert.equal((await list(H, S[5])).json().devices.length, 5);
});

test('e-mail: com a conta cheia o código de 6 dígitos continua valendo para escolher o aparelho', async () => {
  const H = mk();
  await born(H, S[0]);
  const key = await rkNew(H, S[0]);
  await call(H.a, { action: 'bind_start', code: P1, secret: S[0], email: 'ana@exemplo.com' });
  await call(H.a, { action: 'bind_verify', code: P1, secret: S[0], email: 'ana@exemplo.com', otp: otpOf(sent[sent.length - 1]) });
  for (let i = 1; i < 5; i++) await rkLogin(H, key, S[i]);
  await call(H.a, { action: 'login_start', email: 'ana@exemplo.com' });
  const otp = otpOf(sent[sent.length - 1]);
  const full = await call(H.a, { action: 'login_verify', email: 'ana@exemplo.com', otp, secret: S[5] });
  assert.equal(full.statusCode, 422);
  const id = full.json().devices[1].id;
  const ok = await call(H.a, { action: 'login_verify', email: 'ana@exemplo.com', otp, secret: S[5], drop: id });
  assert.equal(ok.statusCode, 200, 'o mesmo código ainda vale');
  assert.equal((await call(H.l, { action: 'sync', code: P1, secret: S[5] })).statusCode, 200);
  // e agora gasto: usar de novo não vale
  const again = await call(H.a, { action: 'login_verify', email: 'ana@exemplo.com', otp, secret: S[6] });
  assert.equal(again.statusCode, 403);
});

test('tirar um aparelho: o dono tira outro, nunca o próprio nem o último', async () => {
  const H = mk();
  await born(H, S[0]);
  const key = await rkNew(H, S[0]);
  await rkLogin(H, key, S[1]);
  const j = (await list(H, S[0])).json();
  const mine = j.devices.find((d) => d.me).id;
  const other = j.devices.find((d) => !d.me).id;
  const self = await call(H.a, { action: 'device_remove', code: P1, secret: S[0], id: mine });
  assert.equal(self.statusCode, 400);
  assert.equal(self.json().error, 'current_device');
  const gone = await call(H.a, { action: 'device_remove', code: P1, secret: S[0], id: other });
  assert.equal(gone.statusCode, 200);
  assert.equal(gone.json().devices.length, 1);
  assert.equal((await call(H.l, { action: 'sync', code: P1, secret: S[1] })).statusCode, 403);
  assert.equal((await call(H.a, { action: 'device_remove', code: P1, secret: S[0], id: 'inexistente' })).statusCode, 404);
});

test('tirar o aparelho que está em "h" passa o "h" para outro e a conta segue aberta', async () => {
  const H = mk();
  await born(H, S[0]); // o dono original está em h
  const key = await rkNew(H, S[0]);
  await rkLogin(H, key, S[1]);
  const id0 = (await list(H, S[1])).json().devices.find((d) => !d.me).id; // aparelho 0
  assert.equal((await call(H.a, { action: 'device_remove', code: P1, secret: S[1], id: id0 })).statusCode, 200);
  assert.equal((await call(H.l, { action: 'sync', code: P1, secret: S[1] })).statusCode, 200);
  assert.equal((await call(H.l, { action: 'sync', code: P1, secret: S[0] })).statusCode, 403);
  const prof = hashes.get(`u:${P1}`);
  assert.equal(prof.get ? prof.get('h') : prof.h, devices.secretHash(S[1]));
});

test('só quem é da conta vê e mexe nos aparelhos', async () => {
  const H = mk();
  await born(H, S[0]);
  assert.equal((await list(H, S[3])).statusCode, 403);
  assert.equal((await call(H.a, { action: 'device_remove', code: P1, secret: S[3], id: 'x' })).statusCode, 403);
  assert.equal((await call(H.a, { action: 'device_name', code: P1, secret: S[3], dn: 'meu' })).statusCode, 403);
});

test('apelido do aparelho: dá nome só ao próprio aparelho e limpa símbolos', async () => {
  const H = mk();
  await born(H, S[0]);
  const key = await rkNew(H, S[0]);
  await rkLogin(H, key, S[1]);
  const r = await call(H.a, { action: 'device_name', code: P1, secret: S[1], dn: '  <b>Celular</b> da Ana  ' });
  assert.equal(r.statusCode, 200);
  const j = r.json();
  assert.equal(j.devices.find((d) => d.me).dn, 'bCelular/b da Ana');
  assert.equal(j.devices.find((d) => !d.me).dn, '');
});

test('a ficha do aparelho (sistema e navegador) vem do navegador de quem entrou', async () => {
  const H = mk();
  await born(H, S[0]);
  const key = await rkNew(H, S[0]);
  const ua = 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36';
  await call(H.a, { action: 'rk_login', key, secret: S[1] }, { 'user-agent': ua });
  const d = (await list(H, S[1])).json().devices.find((x) => x.me);
  assert.equal(d.ou, 'android');
  assert.equal(d.br, 'chrome130');
});

test('a liberação pelo suporte deixa só o aparelho novo na conta', async () => {
  const H = mk();
  await born(H, S[0]);
  const key = await rkNew(H, S[0]);
  await rkLogin(H, key, S[1]);
  const prof = hashes.get(`u:${P1}`);
  assert.ok(prof, 'perfil em memória');
  const crypto = require('node:crypto');
  const sup = 'ABCD2345';
  const put = (k, v) => (prof.set ? prof.set(k, v) : (prof[k] = v));
  put('sc', crypto.createHash('sha256').update(`sup|${P1}|${sup}`).digest('hex'));
  put('sx', String(NOW + 3600000));
  const r = await call(H.l, { action: 'claim', code: P1, secret: S[2], support: sup });
  assert.equal(r.statusCode, 200);
  assert.equal((await call(H.l, { action: 'sync', code: P1, secret: S[2] })).statusCode, 200);
  assert.equal((await call(H.l, { action: 'sync', code: P1, secret: S[0] })).statusCode, 403);
  assert.equal((await call(H.l, { action: 'sync', code: P1, secret: S[1] })).statusCode, 403);
});

test('visto por último: só grava com 2+ aparelhos e no máximo a cada 6 h', async () => {
  const H = mk();
  await born(H, S[0]);
  const key = await rkNew(H, S[0]);
  await call(H.l, { action: 'sync', code: P1, secret: S[0] });
  let prof = hashes.get(`u:${P1}`);
  const get = (k) => (prof.get ? prof.get(k) : prof[k]);
  assert.equal(get('dl'), undefined, 'conta de um aparelho só não grava lista');
  await rkLogin(H, key, S[1]);
  NOW += 7 * 3600000;
  await call(H.l, { action: 'sync', code: P1, secret: S[1] });
  prof = hashes.get(`u:${P1}`);
  const l1 = JSON.parse(get('dl')).find((d) => d.h === devices.secretHash(S[1])).l;
  assert.equal(l1, NOW);
  NOW += 3600000; // 1 h depois: não grava
  await call(H.l, { action: 'sync', code: P1, secret: S[1] });
  prof = hashes.get(`u:${P1}`);
  assert.equal(JSON.parse(get('dl')).find((d) => d.h === devices.secretHash(S[1])).l, NOW - 3600000);
});

test('conta cheia: o aparelho parado há mais de 90 dias cede a vaga sozinho; antes disso, não', async () => {
  const H = mk();
  await born(H, S[0]);
  const key = await rkNew(H, S[0]);
  for (let i = 1; i < 5; i++) await rkLogin(H, key, S[i]);
  NOW += 30 * 86400000;
  assert.equal((await rkLogin(H, key, S[5])).statusCode, 422, 'com 30 dias ninguém é velho demais');
  NOW += 70 * 86400000; // 100 dias no total, todos parados
  const ok = await rkLogin(H, key, S[5]);
  assert.equal(ok.statusCode, 200);
  assert.equal((await list(H, S[5])).json().devices.length, 5);
  assert.equal((await call(H.l, { action: 'sync', code: P1, secret: S[5] })).statusCode, 200);
});

test('"visto por último" não ressuscita um aparelho tirado nem apaga um que acabou de entrar', async () => {
  const H = mk();
  await born(H, S[0]);
  const key = await rkNew(H, S[0]);
  await rkLogin(H, key, S[1]);
  const prof = hashes.get(`u:${P1}`);
  const get = (k) => (prof.get ? prof.get(k) : prof[k]);
  const stale = { h: get('h'), dl: get('dl') }; // o que um pedido em andamento leu antes das mudanças
  const id1 = (await list(H, S[0])).json().devices.find((d) => !d.me).id;
  await call(H.a, { action: 'device_remove', code: P1, secret: S[0], id: id1 }); // tira o aparelho 1
  await rkLogin(H, key, S[2]); // entra o aparelho 2
  const { createStore } = require('./_lib/store');
  const store = createStore(config(MAIL_ENV), async () => { throw new Error('x'); }, () => NOW, { allowMemory: true });
  NOW += 7 * 3600000;
  await devices.seen(store, P1, stale, devices.secretHash(S[1]), NOW); // pedido atrasado do aparelho já tirado
  await devices.seen(store, P1, stale, devices.secretHash(S[0]), NOW);
  assert.equal((await call(H.l, { action: 'sync', code: P1, secret: S[1] })).statusCode, 403, 'o tirado continua tirado');
  assert.equal((await call(H.l, { action: 'sync', code: P1, secret: S[2] })).statusCode, 200, 'o novo continua na conta');
});

// ---------------- ligar outro aparelho com um código de 10 minutos ----------------
const pairNew = (H, s) => call(H.a, { action: 'pair_new', code: P1, secret: s });
const pairJoin = (H, pair, s, extra) => call(H.a, { action: 'pair_join', pair, secret: s, ...(extra || {}) });

test('código de pareamento: um aparelho da conta gera, o novo digita e entra sem e-mail nem chave', async () => {
  const H = mk();
  await born(H, S[0]);
  const n = await pairNew(H, S[0]);
  assert.equal(n.statusCode, 200);
  assert.match(n.json().pair, /^[2-9A-HJ-NP-Z]{4}-[2-9A-HJ-NP-Z]{4}$/);
  assert.equal(n.json().ttl, 600);
  const j = await pairJoin(H, n.json().pair.toLowerCase().replace('-', ' '), S[1], { dn: 'Celular novo' });
  assert.equal(j.statusCode, 200);
  assert.equal(j.json().code, P1);
  assert.equal((await call(H.l, { action: 'sync', code: P1, secret: S[1] })).statusCode, 200);
  assert.equal((await call(H.l, { action: 'sync', code: P1, secret: S[0] })).statusCode, 200, 'o antigo continua');
  assert.equal((await list(H, S[1])).json().devices.find((d) => d.me).dn, 'Celular novo');
});

test('código de pareamento: uso único e vence em 10 minutos', async () => {
  const H = mk();
  await born(H, S[0]);
  const a = (await pairNew(H, S[0])).json().pair;
  assert.equal((await pairJoin(H, a, S[1])).statusCode, 200);
  assert.equal((await pairJoin(H, a, S[2])).statusCode, 403, 'já foi usado');
  const b = (await pairNew(H, S[0])).json().pair;
  NOW += 11 * 60000;
  assert.equal((await pairJoin(H, b, S[3])).statusCode, 403, 'venceu');
});

test('código de pareamento: errado, curto ou com símbolo fora do alfabeto é recusado; só o dono gera', async () => {
  const H = mk();
  await born(H, S[0]);
  for (const bad of ['', 'ABC', 'AAAA-BBBB', '1111-1111', 'ÃÃÃÃ-ÃÃÃÃ', 'x'.repeat(40)]) {
    const r = await pairJoin(H, bad, S[1]);
    assert.ok([400, 403].includes(r.statusCode), String(bad));
  }
  assert.equal((await pairNew(H, S[4])).statusCode, 403, 'quem não é da conta não gera');
  assert.equal((await call(H.l, { action: 'sync', code: P1, secret: S[1] })).statusCode, 403);
});

test('código de pareamento: com a conta cheia responde 422 e o código continua valendo para escolher qual sai', async () => {
  const H = mk();
  await born(H, S[0]);
  const key = await rkNew(H, S[0]);
  for (let i = 1; i < 5; i++) await rkLogin(H, key, S[i]);
  const p = (await pairNew(H, S[0])).json().pair;
  const full = await pairJoin(H, p, S[5]);
  assert.equal(full.statusCode, 422);
  assert.equal(full.json().devices.length, 5);
  const drop = full.json().devices[1].id;
  assert.equal((await pairJoin(H, p, S[5], { drop })).statusCode, 200);
  assert.equal((await call(H.l, { action: 'sync', code: P1, secret: S[5] })).statusCode, 200);
});

test('código de pareamento: perfil bloqueado não deixa entrar e há limite por hora para gerar', async () => {
  const H = mk();
  await born(H, S[0]);
  const prof = hashes.get(`u:${P1}`);
  let last = 0;
  for (let i = 0; i < 12; i++) last = (await pairNew(H, S[0])).statusCode;
  assert.equal(last, 429);
  H.reset = true;
  const H2 = mk();
  await born(H2, S[0]);
  const p = (await pairNew(H2, S[0])).json().pair;
  const pr = hashes.get(`u:${P1}`);
  (pr.set ? pr.set('bl', '1') : (pr.bl = '1'));
  assert.equal((await pairJoin(H2, p, S[1])).statusCode, 403);
});
