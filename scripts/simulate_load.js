#!/usr/bin/env node
// Simulação de carga LÓGICA: roda os handlers de verdade (stats, link) com muitos usuários fictícios durante um "mês" e conta
// quantos COMANDOS do Redis e quantas CHAMADAS de função cada usuário ativo gasta. Serve para calibrar a projeção de custos
// do painel (api/_lib/cost_model.js). NÃO mede velocidade de rede nem limites reais da Vercel/Upstash.
//
// Uso: node scripts/simulate_load.js [usuarios=300] [--json]
// Contagem de comandos: cada operação do armazenamento conta o que gastaria no Upstash (INCR=2 ou 3, RPUSH+LTRIM=2, resto=1;
// cada comando de um pipeline conta 1).
'use strict';

const N = Math.max(60, Number(process.argv[2]) || 300);
const AS_JSON = process.argv.includes('--json');
const crypto = require('node:crypto');

// --- contadores (instalados ANTES de carregar os handlers) ---
const C = { cmds: 0, calls: 0, byAction: {} };
let current = 'outros';
const add = (n) => { C.cmds += n; C.byAction[current] = C.byAction[current] || { calls: 0, cmds: 0 }; C.byAction[current].cmds += n; };
const storeMod = require('../api/_lib/store');
const cmdMod = require('../api/_lib/store_cmd');
const origStore = storeMod.createStore;
const origCmd = cmdMod.createCmd;
storeMod.createStore = (...a) => {
  const st = origStore(...a);
  return new Proxy(st, {
    get(t, p) {
      const v = t[p];
      if (typeof v !== 'function') return v;
      return async (...args) => {
        const r = await v.apply(t, args);
        if (p === 'incr') add(r && r.n === 1 ? 3 : 2);
        else if (p === 'push') add(2);
        else if (['hgetall', 'hget', 'hset', 'hsetnx', 'hdel', 'hlen', 'get', 'set', 'recent', 'claimSlot', 'lastSlot'].includes(p)) add(1);
        return r;
      };
    },
  });
};
cmdMod.createCmd = (...a) => {
  const c = origCmd(...a);
  return { ...c, durable: c.durable, cmd: async (x) => { add(1); return c.cmd(x); }, pipeline: async (l) => { add(l.length); return c.pipeline(l); } };
};

const link = require('../api/link');
const stats = require('../api/stats');
const { config } = require('../api/_lib/config');
const { hashes, memory } = require('../api/_lib/store');
const { resetMem } = require('../api/_lib/store_cmd');

const DAY = 86400000;
let NOW = 1_800_000_000_000;
let ip = 0;
const A = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
function code(seed) {
  let p = ''; let x = seed;
  for (let i = 0; i < 7; i++) { p += A[x % 32]; x = Math.floor(x / 32) + 7 + i; }
  let s = 0; for (let i = 0; i < 7; i++) s += A.indexOf(p[i]) * (2 * i + 1);
  const c = p + A[s % 32]; return `${c.slice(0, 4)}-${c.slice(4)}`;
}
const sec = (c) => crypto.createHash('sha256').update('sim' + c).digest('hex');
hashes.clear(); memory.clear(); resetMem();
const deps = { config: () => config({}), allowMemory: true, fetch: async () => ({ ok: true, status: 200, json: async () => ({}) }), now: () => NOW, random: () => 0.5 };
const L = link.makeHandler(deps), S = stats.makeHandler(deps);
const fake = () => ({ headers: {}, statusCode: 0, body: '', setHeader(k, v) { this.headers[k] = v; }, end(b) { this.body = b; } });
async function callL(label, who, body) {
  current = label; C.calls++; C.byAction[label] = C.byAction[label] || { calls: 0, cmds: 0 }; C.byAction[label].calls++;
  const r = fake();
  await L({ method: 'POST', headers: { 'x-forwarded-for': `10.${(++ip >> 8) % 250}.${ip % 250}.1` }, body: { code: who, secret: sec(who), ...body }, socket: {} }, r);
  return r;
}
async function callS(label, body) {
  current = label; C.calls++; C.byAction[label] = C.byAction[label] || { calls: 0, cmds: 0 }; C.byAction[label].calls++;
  const r = fake();
  await S({ method: 'POST', headers: { 'x-forwarded-for': `11.${(++ip >> 8) % 250}.${ip % 250}.1` }, body, socket: {} }, r);
  return r;
}
// aleatório repetível
let seed = 12345;
const rnd = () => { seed = (seed * 1664525 + 1013904223) % 4294967296; return seed / 4294967296; };

// --- população: 15% professores, cada aluno com 1 professor ---
const nT = Math.max(4, Math.round(N * 0.15));
const teachers = Array.from({ length: nT }, (_, i) => code(1000 + i));
const students = Array.from({ length: N - nT }, (_, i) => ({ c: code(5000 + i), t: teachers[i % nT] }));
const devId = (c) => (c.replace('-', '') + 'abcdefghijklmnop').toLowerCase().slice(0, 20);

(async () => {
  // preparação (não entra na conta do mês: é o cadastro inicial)
  for (const t of teachers) await callL('setup', t, { action: 'sync', name: 'P' });
  for (const s of students) { await callL('setup', s.c, { action: 'sync', name: 'A' }); await callL('setup', s.t, { action: 'link', role: 'teacher', other: s.c }); }
  C.cmds = 0; C.calls = 0; C.byAction = {};
  const lessonWire = (id) => ({ id, t: NOW, d: 30, tasks: [{ id: 't1', title: 'Escala', k: 'scale', st: 0, pc: 7, oct: 1, goal: 0.8 }], notes: [] });
  let lessonN = 0, slotN = 0;

  for (let day = 0; day < 30; day++) {
    NOW += DAY;
    const todayBase = NOW;
    const people = [...teachers.map((c) => ({ c, role: 't' })), ...students.map((s) => ({ c: s.c, role: 's', t: s.t }))];
    for (const p of people) {
      if (rnd() > 0.35) continue; // DAU/MAU ~ 35%
      NOW = todayBase + Math.floor(rnd() * 12 * 3600 * 1000);
      await callS('abrir app (stats open)', { t: 'open', id: devId(p.c), d: { pl: 'web', in: 'browser', v: '1' } });
      await callL('sincronizar (sync)', p.c, { action: 'sync' });
      // sessão de ~12 min: 2 batidas de presença e ~8 consultas baratas (rev)
      for (let k = 0; k < 2; k++) await callS('batida (stats beat)', { t: 'beat', id: devId(p.c) });
      for (let k = 0; k < 8; k++) await callL('consulta barata (rev)', p.c, { action: 'rev' });
      if (p.role === 't') {
        if (rnd() < 0.30) await callL('marcar aula (sched_put)', p.c, { action: 'sched_put', other: students.find((s) => s.t === p.c)?.c || students[0].c, slot: { id: 's' + (++slotN).toString(36).padStart(4, '0'), s: NOW + 3 * DAY, d: 60, u: NOW, w: 1 } });
        if (rnd() < 0.25) await callL('enviar aula/tarefa (lesson)', p.c, { action: 'lesson', other: students.find((s) => s.t === p.c)?.c || students[0].c, lesson: lessonWire('l' + (++lessonN).toString(36).padStart(5, '0')) });
        if (rnd() < 0.04) await callL('publicar horário livre (avail_put)', p.c, { action: 'avail_put', slot: { id: 'h' + (++slotN).toString(36).padStart(4, '0'), s: NOW + 4 * DAY, d: 45, u: NOW, w: 1 } });
        if (rnd() < 0.15) await callL('buscar pegos/tarefas feitas (picks)', p.c, { action: 'picks' });
        if (rnd() < 0.10) await callL('ver o que os alunos fizeram (dones)', p.c, { action: 'dones' });
      } else {
        if (rnd() < 0.25) await callL('buscar aulas (lessons)', p.c, { action: 'lessons' });
        if (rnd() < 0.20) await callL('buscar agenda (sched)', p.c, { action: 'sched' });
        if (rnd() < 0.15) await callL('marcar tarefa feita (done)', p.c, { action: 'done', other: p.t, lesson: 'aula0001', task: 'k1', done: true });
        if (rnd() < 0.04) await callL('ver horários livres (avail)', p.c, { action: 'avail', other: p.t });
      }
    }
  }
  // lembretes (QStash): 1 mensagem e 1 chamada por aula, ~4 aulas/mês por aluno; cada chamada ~4 comandos
  const remind = students.length * 4;
  C.byAction['lembrete (remind, QStash)'] = { calls: remind, cmds: remind * 4 };
  C.calls += remind; C.cmds += remind * 4;

  const per = { users: N, commandsPerUserMonth: Math.round(C.cmds / N), callsPerUserMonth: Math.round(C.calls / N), remindersPerUserMonth: Math.round((remind / N) * 10) / 10 };
  const rows = Object.entries(C.byAction).map(([name, v]) => ({ name, calls: v.calls, cmds: v.cmds, cmdsPerCall: v.calls ? Math.round((v.cmds / v.calls) * 10) / 10 : 0 })).sort((a, b) => b.cmds - a.cmds);
  if (AS_JSON) { console.log(JSON.stringify({ ...per, rows }, null, 2)); return; }
  console.log(`Simulação: ${N} usuários (${nT} professores), 30 dias, DAU/MAU 35%`);
  console.log(`Por usuário no mês: ${per.commandsPerUserMonth} comandos do Redis, ${per.callsPerUserMonth} chamadas de função, ${per.remindersPerUserMonth} lembretes\n`);
  console.log('Ação'.padEnd(42), 'chamadas'.padStart(9), 'comandos'.padStart(9), 'cmd/chamada'.padStart(12));
  for (const r of rows) console.log(r.name.padEnd(42), String(r.calls).padStart(9), String(r.cmds).padStart(9), String(r.cmdsPerCall).padStart(12));
})().catch((e) => { console.error(e); process.exit(1); });
