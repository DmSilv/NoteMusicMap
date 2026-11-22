// Aluno desvincula e volta ao mesmo professor: `node --test api/relink.test.js`
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const link = require('./link');
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
const PROF = code(11), ALU = code(33);
const sec = (c) => crypto.createHash('sha256').update('s' + c).digest('hex');
let ip = 0;
const res = () => { const r = { statusCode: 0, body: '' }; r.setHeader = () => {}; r.end = (b) => { r.body = b; }; r.json = () => JSON.parse(r.body); return r; };
function mk() {
  hashes.clear(); memory.clear(); resetMem();
  const H = link.makeHandler({ config: () => config({}), allowMemory: true, fetch: async () => ({ status: 200 }), now: () => 1_800_000_000_000 });
  return async (who, body) => { const r = res(); await H({ method: 'POST', headers: { 'x-forwarded-for': '4.4.4.' + ++ip }, body: { code: who, secret: sec(who), ...body }, socket: {} }, r); return r; };
}

test('o aluno sai e o professor deixa de ver o vínculo; o aluno inicia o vínculo de novo e os dois voltam a se ver', async () => {
  const as = mk();
  await as(PROF, { action: 'sync', name: 'Prof' });
  await as(ALU, { action: 'sync', name: 'Ana' });
  assert.equal((await as(PROF, { action: 'link', role: 'teacher', other: ALU })).statusCode, 200);
  assert.equal((await as(ALU, { action: 'unlink', role: 'student', other: PROF })).statusCode, 200);
  assert.deepEqual((await as(PROF, { action: 'sync' })).json().asTeacher, []);
  assert.deepEqual((await as(ALU, { action: 'sync' })).json().asStudent, []);
  assert.equal((await as(ALU, { action: 'link', role: 'student', other: PROF })).statusCode, 200);
  assert.deepEqual((await as(PROF, { action: 'sync' })).json().asTeacher.map((x) => x.code), [ALU]);
  assert.deepEqual((await as(ALU, { action: 'sync' })).json().asStudent.map((x) => x.code), [PROF]);
});

test('o professor também consegue refazer o vínculo depois que o aluno saiu', async () => {
  const as = mk();
  await as(PROF, { action: 'sync', name: 'Prof' });
  await as(ALU, { action: 'sync', name: 'Ana' });
  await as(PROF, { action: 'link', role: 'teacher', other: ALU });
  await as(ALU, { action: 'unlink', role: 'student', other: PROF });
  assert.equal((await as(PROF, { action: 'link', role: 'teacher', other: ALU })).statusCode, 200);
  assert.deepEqual((await as(PROF, { action: 'sync' })).json().asTeacher.map((x) => x.code), [ALU]);
});
