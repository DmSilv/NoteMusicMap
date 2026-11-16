// Testes do e-mail da conta (sem senha), sem rede: `node --test api/account.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const account = require('./account');
const link = require('./link');
const { config } = require('./_lib/config');
const { hashes, memory } = require('./_lib/store');
const { resetMem, createCmd } = require('./_lib/store_cmd');
const { isEmpty } = require('./_lib/sweep');

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
const secret = (c) => c.repeat(64).slice(0, 64);
const P1 = code(11111), P2 = code(22222);
const S1 = secret('a'), S2 = secret('b'), SNEW = secret('c');
const MAIL_ENV = { MAIL_API_KEY: 'chave-de-teste', MAIL_FROM: 'Notemusic <nao-responda@exemplo.com>' };

let NOW = Date.UTC(2026, 10, 14, 15, 0, 0);
let sent = [];
let ipN = 0;

function mk(env = MAIL_ENV) {
  hashes.clear();
  memory.clear();
  resetMem();
  sent = [];
  NOW = Date.UTC(2026, 10, 14, 15, 0, 0);
  const fetch = async (url, init) => {
    if (String(url).includes('resend')) { sent.push(JSON.parse(init.body)); return { ok: true, json: async () => ({}) }; }
    throw new Error('sem rede');
  };
  const deps = { config: () => config(env), allowMemory: true, fetch, now: () => NOW };
  return { a: account.makeHandler(deps), l: link.makeHandler(deps), cfg: config(env) };
}
function fakeRes() {
  const r = { headers: {}, statusCode: 0, body: '' };
  r.setHeader = (k, v) => { r.headers[k] = v; };
  r.end = (b) => { r.body = b; };
  r.json = () => JSON.parse(r.body);
  return r;
}
async function call(h, body, ip) {
  const res = fakeRes();
  await h({ method: 'POST', headers: { 'x-forwarded-for': ip || '9.9.9.' + ++ipN }, body, socket: {} }, res);
  return res;
}
const otpOf = (m) => /\b(\d{6})\b/.exec(m.text)[1];
const lastOtp = () => otpOf(sent[sent.length - 1]);
/** Cria o perfil no servidor (o primeiro uso registra o segredo). */
const born = (H, c, s) => call(H.l, { action: 'sync', code: c, secret: s });
const bind = async (H, c, s, email) => {
  assert.equal((await call(H.a, { action: 'bind_start', code: c, secret: s, email })).statusCode, 200);
  return call(H.a, { action: 'bind_verify', code: c, secret: s, email, otp: lastOtp() });
};

test('sem e-mail configurado: o status diz desligado e pedir código dá 503', async () => {
  const H = mk({});
  await born(H, P1, S1);
  const st = (await call(H.a, { action: 'status', code: P1, secret: S1 })).json();
  assert.equal(st.enabled, false);
  assert.equal((await call(H.a, { action: 'bind_start', code: P1, secret: S1, email: 'a@exemplo.com' })).statusCode, 503);
  assert.equal(sent.length, 0);
});

test('status de um perfil que nunca foi ao servidor: só diz se o e-mail está disponível, sem criar nada', async () => {
  const H = mk();
  const st = (await call(H.a, { action: 'status', code: P1, secret: S1 })).json();
  assert.deepEqual([st.ok, st.enabled, st.linked], [true, true, false]);
  assert.equal(hashes.has('u:' + P1), false, 'nenhum perfil foi criado');
});

test('ligar o e-mail: manda o código, confere e passa a constar como ligado (só o hash fica guardado)', async () => {
  const H = mk();
  await born(H, P1, S1);
  const r = await call(H.a, { action: 'bind_start', code: P1, secret: S1, email: 'Ana@Exemplo.com' });
  assert.equal(r.statusCode, 200);
  assert.equal(sent.length, 1);
  assert.equal(sent[0].to[0], 'ana@exemplo.com', 'o e-mail é normalizado');
  assert.match(sent[0].subject, /^Seu código do Notemusic: \d{6}$/);
  const v = await call(H.a, { action: 'bind_verify', code: P1, secret: S1, email: 'ana@exemplo.com', otp: lastOtp() });
  assert.equal(v.statusCode, 200);
  assert.equal(v.json().hint, 'a***@exemplo.com');
  const st = (await call(H.a, { action: 'status', code: P1, secret: S1 })).json();
  assert.deepEqual([st.enabled, st.linked, st.hint], [true, true, 'a***@exemplo.com']);
  // o e-mail em si não fica guardado em lugar nenhum do banco
  const guardado = JSON.stringify([...hashes.entries()].map(([k, m]) => [k, [...m.entries()]]));
  assert.equal(guardado.includes('ana@exemplo.com'), false);
  assert.equal(guardado.includes('Ana@Exemplo.com'), false);
});

test('código errado é recusado, vale uma vez só e some depois de 5 erros', async () => {
  const H = mk();
  await born(H, P1, S1);
  await call(H.a, { action: 'bind_start', code: P1, secret: S1, email: 'a@exemplo.com' });
  const certo = lastOtp();
  const errado = certo === '000000' ? '111111' : '000000';
  for (let i = 0; i < 5; i++) assert.equal((await call(H.a, { action: 'bind_verify', code: P1, secret: S1, email: 'a@exemplo.com', otp: errado })).statusCode, 403);
  assert.equal((await call(H.a, { action: 'bind_verify', code: P1, secret: S1, email: 'a@exemplo.com', otp: certo })).statusCode, 403, 'depois de 5 erros nem o certo vale');
  // um código novo funciona e só uma vez
  await call(H.a, { action: 'bind_start', code: P1, secret: S1, email: 'a@exemplo.com' });
  const novo = lastOtp();
  assert.equal((await call(H.a, { action: 'bind_verify', code: P1, secret: S1, email: 'a@exemplo.com', otp: novo })).statusCode, 200);
  assert.equal((await call(H.a, { action: 'bind_verify', code: P1, secret: S1, email: 'a@exemplo.com', otp: novo })).statusCode, 403);
});

test('o código vence em 10 minutos', async () => {
  const H = mk();
  await born(H, P1, S1);
  await call(H.a, { action: 'bind_start', code: P1, secret: S1, email: 'a@exemplo.com' });
  const otp = lastOtp();
  NOW += 11 * 60 * 1000;
  assert.equal((await call(H.a, { action: 'bind_verify', code: P1, secret: S1, email: 'a@exemplo.com', otp })).statusCode, 403);
});

test('só o dono do perfil liga o e-mail (segredo errado é recusado e nada é enviado)', async () => {
  const H = mk();
  await born(H, P1, S1);
  const r = await call(H.a, { action: 'bind_start', code: P1, secret: S2, email: 'a@exemplo.com' });
  assert.equal(r.statusCode, 403);
  assert.equal(sent.length, 0);
});

test('o mesmo e-mail não protege dois perfis', async () => {
  const H = mk();
  await born(H, P1, S1);
  await born(H, P2, S2);
  assert.equal((await bind(H, P1, S1, 'a@exemplo.com')).statusCode, 200);
  const r = await call(H.a, { action: 'bind_start', code: P2, secret: S2, email: 'a@exemplo.com' });
  assert.equal(r.statusCode, 409);
  assert.equal(r.json().error, 'email_in_use');
});

test('entrar com e-mail: o aparelho novo entra na conta e o antigo continua valendo', async () => {
  const H = mk();
  await born(H, P1, S1);
  await bind(H, P1, S1, 'ana@exemplo.com');
  sent = [];
  const st = await call(H.a, { action: 'login_start', email: 'ANA@exemplo.com' });
  assert.equal(st.statusCode, 200);
  assert.equal(sent.length, 1);
  const v = await call(H.a, { action: 'login_verify', email: 'ana@exemplo.com', otp: lastOtp(), secret: SNEW });
  assert.equal(v.statusCode, 200);
  assert.equal(v.json().code, P1);
  assert.equal(sent.length, 2, 'um aviso de novo acesso vai para o e-mail');
  assert.match(sent[1].subject, /Novo acesso/);
  assert.equal((await call(H.l, { action: 'sync', code: P1, secret: S1 })).statusCode, 200, 'o aparelho antigo continua na conta');
  assert.equal((await call(H.l, { action: 'sync', code: P1, secret: SNEW })).statusCode, 200, 'o novo também entra');
});

test('entrar com e-mail não revela quem tem conta: a resposta é a mesma e nada é enviado a quem não tem', async () => {
  const H = mk();
  await born(H, P1, S1);
  await bind(H, P1, S1, 'ana@exemplo.com');
  sent = [];
  const sem = await call(H.a, { action: 'login_start', email: 'ninguem@exemplo.com' });
  const com = await call(H.a, { action: 'login_start', email: 'ana@exemplo.com' });
  assert.equal(sem.statusCode, 200);
  assert.deepEqual(sem.json(), com.json());
  assert.equal(sent.length, 1);
  assert.equal(sent[0].to[0], 'ana@exemplo.com');
});

test('o código de ligar o e-mail não serve para entrar (e vice-versa)', async () => {
  const H = mk();
  await born(H, P1, S1);
  await call(H.a, { action: 'bind_start', code: P1, secret: S1, email: 'a@exemplo.com' });
  const r = await call(H.a, { action: 'login_verify', email: 'a@exemplo.com', otp: lastOtp(), secret: SNEW });
  assert.equal(r.statusCode, 403);
});

test('limite de códigos por hora no mesmo e-mail e por perfil', async () => {
  const H = mk();
  await born(H, P1, S1);
  for (let i = 0; i < 5; i++) assert.equal((await call(H.a, { action: 'bind_start', code: P1, secret: S1, email: 'a@exemplo.com' })).statusCode, 200);
  assert.equal((await call(H.a, { action: 'bind_start', code: P1, secret: S1, email: 'a@exemplo.com' })).statusCode, 429);
  assert.equal(sent.length, 5);
});

test('desligar o e-mail: o status volta a "não ligado" e entrar com ele não manda mais nada', async () => {
  const H = mk();
  await born(H, P1, S1);
  await bind(H, P1, S1, 'ana@exemplo.com');
  assert.equal((await call(H.a, { action: 'unbind', code: P1, secret: S1 })).statusCode, 200);
  const st = (await call(H.a, { action: 'status', code: P1, secret: S1 })).json();
  assert.equal(st.linked, false);
  sent = [];
  await call(H.a, { action: 'login_start', email: 'ana@exemplo.com' });
  assert.equal(sent.length, 0);
});

test('e-mail malformado e ação desconhecida são recusados', async () => {
  const H = mk();
  await born(H, P1, S1);
  for (const e of ['sem-arroba', 'a@b', 'a b@exemplo.com', '', 42, null]) {
    assert.equal((await call(H.a, { action: 'bind_start', code: P1, secret: S1, email: e })).statusCode, 400, String(e));
  }
  assert.equal((await call(H.a, { action: 'xablau', code: P1, secret: S1 })).statusCode, 400);
  assert.equal(sent.length, 0);
});

test('quem ligou um e-mail nunca é apagado pela limpeza de perfis abandonados', async () => {
  const H = mk();
  await born(H, P1, S1);
  const cmd = createCmd(H.cfg, async () => { throw new Error('sem rede'); }, { allowMemory: true });
  assert.equal(await isEmpty(cmd, P1), true, 'sem e-mail e sem dados, é apagável');
  await bind(H, P1, S1, 'ana@exemplo.com');
  assert.equal(await isEmpty(cmd, P1), false, 'com e-mail, fica');
});

// ---------------- chave de recuperação de 25 caracteres (sem e-mail) ----------------
const rkNew = (H, c, s) => call(H.a, { action: 'rk_new', code: c, secret: s });

test('chave de 25: gera no formato certo e funciona mesmo com o e-mail desligado', async () => {
  const H = mk({});
  await born(H, P1, S1);
  const r = await rkNew(H, P1, S1);
  assert.equal(r.statusCode, 200);
  assert.match(r.json().key, /^([2-9A-HJ-NP-Z]{5}-){4}[2-9A-HJ-NP-Z]{5}$/);
  const st = (await call(H.a, { action: 'status', code: P1, secret: S1 })).json();
  assert.equal(st.hasKey, true);
  assert.equal(st.enabled, false);
  assert.equal(sent.length, 0);
});

test('chave de 25: o servidor guarda só o hash, nunca a chave', async () => {
  const H = mk();
  await born(H, P1, S1);
  const key = (await rkNew(H, P1, S1)).json().key;
  const guardado = JSON.stringify([...hashes.entries()].map(([k, m]) => [k, [...m.entries()]]));
  assert.equal(guardado.includes(key), false);
  assert.equal(guardado.includes(key.replace(/-/g, '')), false);
});

test('chave de 25: entrar com ela põe o aparelho novo na conta e o antigo continua valendo', async () => {
  const H = mk();
  await born(H, P1, S1);
  const key = (await rkNew(H, P1, S1)).json().key;
  const v = await call(H.a, { action: 'rk_login', key: key.toLowerCase().replace(/-/g, ' '), secret: SNEW });
  assert.equal(v.statusCode, 200, 'aceita minúsculas e sem hífens');
  assert.equal(v.json().code, P1);
  assert.equal((await call(H.l, { action: 'sync', code: P1, secret: S1 })).statusCode, 200);
  assert.equal((await call(H.l, { action: 'sync', code: P1, secret: SNEW })).statusCode, 200);
});

test('chave de 25: errada, curta ou com símbolo fora do alfabeto é recusada', async () => {
  const H = mk();
  await born(H, P1, S1);
  await rkNew(H, P1, S1);
  for (const k of ['AAAAA-AAAAA-AAAAA-AAAAA-AAAAA', 'ABC', '', 'OOOOO-OOOOO-OOOOO-OOOOO-OOOOO', 42, null]) {
    const r = await call(H.a, { action: 'rk_login', key: k, secret: SNEW });
    assert.ok([400, 403].includes(r.statusCode), String(k));
  }
  assert.equal((await call(H.l, { action: 'sync', code: P1, secret: S1 })).statusCode, 200, 'o dono continua dono');
});

test('chave de 25: gerar outra cancela a anterior', async () => {
  const H = mk();
  await born(H, P1, S1);
  const velha = (await rkNew(H, P1, S1)).json().key;
  const nova = (await rkNew(H, P1, S1)).json().key;
  assert.notEqual(velha, nova);
  assert.equal((await call(H.a, { action: 'rk_login', key: velha, secret: SNEW })).statusCode, 403);
  assert.equal((await call(H.a, { action: 'rk_login', key: nova, secret: SNEW })).statusCode, 200);
});

test('chave de 25: só o dono do perfil gera (segredo errado é recusado) e há limite por hora', async () => {
  const H = mk();
  await born(H, P1, S1);
  assert.equal((await rkNew(H, P1, S2)).statusCode, 403);
  for (let i = 0; i < 5; i++) assert.equal((await rkNew(H, P1, S1)).statusCode, 200);
  assert.equal((await rkNew(H, P1, S1)).statusCode, 429);
});

test('chave de 25: tentativas erradas seguidas da mesma origem são barradas', async () => {
  const H = mk();
  await born(H, P1, S1);
  await rkNew(H, P1, S1);
  let last = 0;
  for (let i = 0; i < 25; i++) last = (await call(H.a, { action: 'rk_login', key: 'AAAAA-AAAAA-AAAAA-AAAAA-AAAAA', secret: SNEW }, '5.5.5.5')).statusCode;
  assert.equal(last, 429);
});

test('chave de 25: perfil com chave nunca é apagado pela limpeza de abandonados', async () => {
  const H = mk();
  await born(H, P1, S1);
  const cmd = createCmd(H.cfg, async () => { throw new Error('sem rede'); }, { allowMemory: true });
  assert.equal(await isEmpty(cmd, P1), true);
  await rkNew(H, P1, S1);
  assert.equal(await isEmpty(cmd, P1), false);
});
