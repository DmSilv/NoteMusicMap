// Foto de perfil mostrada a quem está vinculado, sem rede: `node --test api/photo.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { makeHandler } = require('./link');
const { config } = require('./_lib/config');
const { hashes, memory } = require('./_lib/store');

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
const PROF = code(11111), ALU = code(22222), OUTRO = code(44444);
const sec = (ch) => ch.repeat(64).slice(0, 64);
const S_PROF = sec('a'), S_ALU = sec('b'), S_OUTRO = sec('c');

function fakeRes() {
  const r = { headers: {}, statusCode: 0, body: '' };
  r.setHeader = (k, v) => { r.headers[k] = v; };
  r.end = (b) => { r.body = b; };
  r.json = () => JSON.parse(r.body);
  return r;
}
let NOW = Date.UTC(2026, 10, 14, 15, 0, 0);
function mk() {
  hashes.clear();
  memory.clear();
  NOW = Date.UTC(2026, 10, 14, 15, 0, 0);
  return makeHandler({ config: () => config({}), allowMemory: true, now: () => NOW, fetch: async () => { throw new Error('sem rede'); } });
}
let n = 0;
async function call(h, body) {
  const res = fakeRes();
  await h({ method: 'POST', headers: { 'x-forwarded-for': '7.7.7.' + ++n }, body, socket: {} }, res);
  return res;
}
const jpegB64 = (len = 200, fill = 7) => Buffer.from([0xff, 0xd8, 0xff, 0xe0, ...Array(len).fill(fill)]).toString('base64');
const pngB64 = () => Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3]).toString('base64');
const as = (h, c, s, body) => call(h, { code: c, secret: s, ...body });
const sync = (h, c, s) => as(h, c, s, { action: 'sync' }).then((r) => r.json());

async function linked() {
  const h = mk();
  await as(h, PROF, S_PROF, { action: 'link', role: 'teacher', other: ALU, name: 'Profa. Ana' });
  await sync(h, ALU, S_ALU);
  return h;
}

test('o aluno põe a foto e o professor a vê; a versão aparece no vínculo', async () => {
  const h = await linked();
  const put = await as(h, ALU, S_ALU, { action: 'photo_put', photo: jpegB64() });
  assert.equal(put.statusCode, 200);
  const pv = put.json().pv;
  assert.match(pv, /^[0-9a-f]{8}$/);
  const t = await sync(h, PROF, S_PROF);
  assert.equal(t.asTeacher.find((x) => x.code === ALU).pv, pv, 'a versão chega na lista do professor');
  const got = await as(h, PROF, S_PROF, { action: 'photo_get', other: ALU });
  assert.equal(got.statusCode, 200);
  assert.equal(got.json().photo, jpegB64());
  assert.equal(got.json().pv, pv);
});

test('trocar a foto muda a versão e avisa os dois lados (kr)', async () => {
  const h = await linked();
  const a = (await as(h, ALU, S_ALU, { action: 'photo_put', photo: jpegB64(200, 7) })).json().pv;
  const krBefore = (await as(h, PROF, S_PROF, { action: 'rev' })).json().kr;
  NOW += 5000;
  const b = (await as(h, ALU, S_ALU, { action: 'photo_put', photo: jpegB64(200, 9) })).json().pv;
  assert.notEqual(a, b);
  assert.ok((await as(h, PROF, S_PROF, { action: 'rev' })).json().kr > krBefore, 'o professor vê que algo mudou');
  assert.equal((await sync(h, PROF, S_PROF)).asTeacher[0].pv, b);
});

test('o professor também põe a foto e o aluno a vê', async () => {
  const h = await linked();
  await as(h, PROF, S_PROF, { action: 'photo_put', photo: pngB64() });
  const s = await sync(h, ALU, S_ALU);
  assert.ok(s.asStudent[0].pv);
  const got = await as(h, ALU, S_ALU, { action: 'photo_get', other: PROF });
  assert.equal(got.json().photo, pngB64());
});

test('quem não está vinculado não vê a foto', async () => {
  const h = await linked();
  await as(h, ALU, S_ALU, { action: 'photo_put', photo: jpegB64() });
  await sync(h, OUTRO, S_OUTRO);
  const r = await as(h, OUTRO, S_OUTRO, { action: 'photo_get', other: ALU });
  assert.equal(r.statusCode, 403);
  assert.equal(r.body.includes(jpegB64()), false);
});

test('remover a foto apaga e tira a versão dos vínculos', async () => {
  const h = await linked();
  await as(h, ALU, S_ALU, { action: 'photo_put', photo: jpegB64() });
  const r = await as(h, ALU, S_ALU, { action: 'photo_put', photo: '' });
  assert.equal(r.statusCode, 200);
  assert.equal(r.json().pv, '');
  assert.equal((await sync(h, PROF, S_PROF)).asTeacher[0].pv, undefined);
  assert.equal((await as(h, PROF, S_PROF, { action: 'photo_get', other: ALU })).statusCode, 404);
});

test('vínculo feito depois da foto já nasce com a versão', async () => {
  const h = mk();
  const pv = (await as(h, ALU, S_ALU, { action: 'photo_put', photo: jpegB64() })).json().pv;
  await as(h, PROF, S_PROF, { action: 'link', role: 'teacher', other: ALU, name: 'Profa. Ana' });
  assert.equal((await sync(h, PROF, S_PROF)).asTeacher[0].pv, pv);
});

test('recusa o que não é imagem pequena', async () => {
  const h = await linked();
  const bad = [
    Buffer.from('<svg onload=alert(1)>').toString('base64'),
    jpegB64(24000), // passa do limite
    'isto não é base64!',
    jpegB64() + '<',
  ];
  for (const photo of bad) {
    const r = await as(h, ALU, S_ALU, { action: 'photo_put', photo });
    assert.ok([400].includes(r.statusCode), String(photo).slice(0, 20) + ' -> ' + r.statusCode);
  }
  assert.equal((await as(h, PROF, S_PROF, { action: 'photo_get', other: ALU })).statusCode, 404);
});

test('pedido grande demais é recusado antes de ler e há limite de trocas por hora', async () => {
  const h = await linked();
  const huge = 'A'.repeat(50000);
  assert.equal((await as(h, ALU, S_ALU, { action: 'photo_put', photo: huge })).statusCode, 400);
  let last = 0;
  for (let i = 0; i < 12; i++) last = (await as(h, ALU, S_ALU, { action: 'photo_put', photo: jpegB64(100 + i) })).statusCode;
  assert.equal(last, 429);
});

test('a foto não vai na sincronização comum (só a versão, para o polling continuar leve)', async () => {
  const h = await linked();
  await as(h, ALU, S_ALU, { action: 'photo_put', photo: jpegB64(5000) });
  const r = await as(h, PROF, S_PROF, { action: 'sync' });
  assert.equal(r.body.includes(jpegB64(5000)), false);
  assert.ok(r.body.length < 1500);
});
