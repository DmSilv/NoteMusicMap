// POST /api/link: vínculo entre professor e aluno, registrado dos dois lados.
//
// Quem lê o QR (ou digita o código) do outro cria o vínculo; ele passa a valer
// para os dois, e cada um vê o outro na sua lista na próxima atualização.
//
// O servidor guarda: o código de cada perfil, o apelido opcional, um hash do segredo
// (para provar que o código é seu), a lista de vínculos com a data e, quando o professor
// ENCERRA uma aula, o pacote dela (tarefas e observações daquela aula) para o aluno
// vinculado buscar. Nunca áudio, nem o histórico de exercícios.
//
// Ações (todas POST, com { code, secret }):
//   sync     -> listas de vínculos e a revisão das aulas (lr)
//   link     -> cria o vínculo (role + other)
//   unlink   -> desfaz o vínculo (e apaga as aulas desse professor para esse aluno)
//   lesson   -> PROFESSOR publica uma aula encerrada para um aluno vinculado { other, lesson }
//   lessons  -> ALUNO busca as aulas dos professores a que está vinculado
//
// Precisa do Upstash Redis. Sem ele devolve 503 e o app segue só neste aparelho.
'use strict';

const crypto = require('node:crypto');
const { config } = require('./_lib/config');
const { createStore } = require('./_lib/store');

const ALPHABET = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
const MAX_LINKS = 300;
const MUTATIONS_PER_HOUR = 60;
const BAD_AUTH_PER_HOUR = 20;
const NEW_PROFILES_PER_DAY = 30; // perfis novos por origem/dia (evita encher o banco com códigos falsos)
const MAX_BODY = 2048; // bytes: o pedido comum tem ~200
const MAX_LESSON_BODY = 40000; // pedido de publicar aula (30 tarefas com texto cheio cabem)
const MAX_LESSON_JSON = 30000; // aula já limpa
const LESSONS_KEPT = 60; // aulas guardadas por aluno
const PULLS_PER_HOUR = 240;
const TASK_KINDS = ['scale', 'method', 'repertoire', 'free'];

/** Código "XXXX-XXXX" válido (mesma verificação do app) ou null. */
function normCode(s) {
  const t = String(s || '').toUpperCase().replace(/[\s-]/g, '');
  if (t.length !== 8) return null;
  for (const c of t) if (!ALPHABET.includes(c)) return null;
  let sum = 0;
  for (let i = 0; i < 7; i++) sum += ALPHABET.indexOf(t[i]) * (2 * i + 1);
  if (ALPHABET[sum % 32] !== t[7]) return null;
  return `${t.slice(0, 4)}-${t.slice(4)}`;
}

const sha = (s) => crypto.createHash('sha256').update(s).digest('hex');
// Caracteres que enganam a leitura (inversão de direção, largura zero) somem.
const INVISIBLE = /[\u00ad\u200b-\u200f\u2028-\u202e\u2060-\u2064\u2066-\u2069\ufeff]/g;
const clean = (v, max) =>
  String(v == null ? '' : v).replace(INVISIBLE, '').replace(/[\u0000-\u001f\u007f-\u009f]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, max);
/** Texto de várias linhas: mantém as quebras de linha, tira o resto como em clean. */
const cleanMulti = (v, max) =>
  String(v == null ? '' : v)
    .replace(INVISIBLE, '')
    .replace(/\r/g, '')
    .replace(/[\u0000-\u0009\u000b-\u001f\u007f-\u009f]/g, ' ')
    .split('\n').map((l) => l.replace(/ {2,}/g, ' ').trim()).join('\n')
    .replace(/\n{3,}/g, '\n\n').trim().slice(0, max);
const int = (v, lo, hi, d) => { const n = Math.round(Number(v)); return Number.isFinite(n) ? Math.min(hi, Math.max(lo, n)) : d; };

/** Valida e limpa o pacote de uma aula; null se não for uma aula válida. */
function cleanLesson(l, now) {
  if (!l || typeof l !== 'object' || Array.isArray(l)) return null;
  const id = String(l.id || '');
  if (!/^[a-z0-9]{2,40}$/.test(id)) return null;
  const t = Number(l.t);
  if (!Number.isFinite(t) || t < 1577836800000 || t > now + 86400000) return null;
  if (!Array.isArray(l.tasks) && l.tasks !== undefined) return null;
  if (!Array.isArray(l.notes) && l.notes !== undefined) return null;
  const tasks = [];
  for (const x of (l.tasks || []).slice(0, 30)) {
    if (!x || typeof x !== 'object') continue;
    const tid = String(x.id || '');
    if (!/^[A-Za-z0-9_-]{1,40}$/.test(tid)) continue;
    const created = new Date(String(x.c || ''));
    tasks.push({
      id: tid,
      title: clean(x.title, 80) || 'Tarefa',
      kind: TASK_KINDS.includes(x.kind) ? x.kind : 'scale',
      sub: clean(x.sub, 80),
      det: clean(x.det, 160),
      note: cleanMulti(x.note, 500),
      st: int(x.st, 0, 40, 0),
      pc: int(x.pc, 0, 11, 0),
      oct: int(x.oct, 1, 3, 1),
      goal: Math.round(Math.min(1, Math.max(0, Number(x.goal) || 0)) * 100) / 100,
      done: false,
      c: Number.isNaN(created.getTime()) ? new Date(now).toISOString() : created.toISOString(),
    });
  }
  const notes = (l.notes || []).slice(0, 10).map((n) => cleanMulti(n, 500)).filter(Boolean);
  return { id, t: Math.round(t), d: int(l.d, 0, 86400, 0), tasks, notes, tn: clean(l.tn, 40) };
}

function clientIp(req) {
  const xf = String(req.headers['x-forwarded-for'] || '').split(',')[0].trim();
  return xf || (req.socket && req.socket.remoteAddress) || 'ip-desconhecido';
}

function readBody(req) {
  // Pedido grande demais nunca é um pedido do app: nem tenta ler.
  const len = Number(req.headers && req.headers['content-length']);
  if (Number.isFinite(len) && len > MAX_LESSON_BODY) return null;
  let b = null;
  if (req.body && typeof req.body === 'object') b = req.body;
  else if (typeof req.body === 'string') {
    if (req.body.length > MAX_LESSON_BODY) return null;
    try { b = JSON.parse(req.body); } catch (_) { return null; }
  }
  if (!b || typeof b !== 'object' || Array.isArray(b)) return null;
  // Só 'lesson' pode ser grande; os demais pedidos têm ~200 bytes.
  const limit = b.action === 'lesson' ? MAX_LESSON_BODY : MAX_BODY;
  if (JSON.stringify(b).length > limit) return null;
  return b;
}

const U = (code) => `u:${code}`; // hash do perfil: h (hash do segredo), n (apelido)
const T = (code) => `ut:${code}`; // alunos deste professor: aluno -> JSON
const S = (code) => `us:${code}`; // professores deste aluno: professor -> JSON
const UL = (code) => `ul:${code}`; // aulas deste aluno: "professor:idAula" -> JSON

function parseLinks(h) {
  const out = [];
  for (const [code, raw] of Object.entries(h)) {
    try {
      const j = JSON.parse(raw);
      out.push({ code, name: j.n || '', since: j.t || 0, by: j.by || '' });
    } catch (_) { /* linha ruim */ }
  }
  return out.sort((a, b) => a.since - b.since);
}

function makeHandler(deps = {}) {
  const fetchImpl = deps.fetch || globalThis.fetch;
  const getCfg = deps.config || (() => config());
  const clock = deps.now || Date.now;
  return async function handler(req, res) {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    const send = (code, obj) => {
      res.statusCode = code;
      res.end(JSON.stringify(obj));
    };
    if (req.method !== 'POST') return send(405, { error: 'Use POST.' });

    const cfg = getCfg();
    const store = createStore(cfg, fetchImpl, clock, { allowMemory: !!deps.allowMemory });
    if (!store.durable) {
      return send(503, { error: 'sync_unavailable', message: 'O vínculo online ainda não está configurado.' });
    }

    const b = readBody(req);
    if (!b) return send(400, { error: 'Corpo inválido.' });
    const me = normCode(b.code);
    const secret = String(b.secret || '');
    if (!me || !/^[0-9a-f]{64}$/.test(secret)) return send(400, { error: 'Código ou segredo inválido.' });

    try {
      // Limite de tentativas erradas por origem (contra quem tenta adivinhar segredos).
      const ipKey = sha(clientIp(req)).slice(0, 16);
      const hour = Math.floor(clock() / 3600000);
      const failKey = `lnkbad:${ipKey}:${hour}`;

      // Dono do código: o primeiro a usar registra o hash do segredo; depois só ele passa.
      const secretHash = sha('lnk|' + secret);
      let prof = await store.hgetall(U(me));
      if (!prof.h) {
        // Perfil novo: limite por origem e por dia, para ninguém encher o banco de códigos falsos.
        const day = Math.floor(clock() / 86400000);
        const nw = await store.incr(`lnknew:${ipKey}:${day}`, 86400);
        if (nw.n > NEW_PROFILES_PER_DAY) return send(429, { error: 'Muitos perfis novos desta origem hoje. Tente amanhã.' });
        await store.hsetnx(U(me), 'h', secretHash); // primeira vez: este segredo passa a ser o dono
        prof = await store.hgetall(U(me));
      }
      const okOwner = prof.h && crypto.timingSafeEqual(Buffer.from(prof.h), Buffer.from(secretHash));
      if (!okOwner) {
        const f = await store.incr(failKey, 3600);
        if (f.n > BAD_AUTH_PER_HOUR) return send(429, { error: 'Muitas tentativas. Tente mais tarde.' });
        return send(403, { error: 'Este código pertence a outro aparelho.' });
      }

      // Apelido opcional (aparece para quem está vinculado a você).
      const name = b.name === undefined ? null : clean(b.name, 40);
      let nameChanged = false;
      if (name !== null && name !== (prof.n || '')) {
        await store.hset(U(me), 'n', name);
        prof.n = name;
        nameChanged = true;
      }

      const action = String(b.action || 'sync');

      if (action === 'sync') {
        // Mudou o apelido: avisa quem está vinculado (o nome fica dentro de cada vínculo).
        if (nameChanged) await propagateName(store, me, name);
        const [asTeacher, asStudent] = await Promise.all([store.hgetall(T(me)), store.hgetall(S(me))]);
        return send(200, { ok: true, asTeacher: parseLinks(asTeacher), asStudent: parseLinks(asStudent), lr: Number(prof.lr) || 0 });
      }

      // O aluno busca as aulas dos professores a que ainda está vinculado.
      if (action === 'lessons') {
        const pulls = await store.incr(`lnkpull:${me}:${hour}`, 3600);
        if (pulls.n > PULLS_PER_HOUR) return send(429, { error: 'Muitas consultas. Tente mais tarde.' });
        const [mine, raw] = await Promise.all([store.hgetall(S(me)), store.hgetall(UL(me))]);
        const lessons = [];
        for (const [field, json] of Object.entries(raw)) {
          const teacher = field.split(':')[0];
          if (mine[teacher] === undefined) continue; // vínculo encerrado: a aula não vale mais
          try { lessons.push({ ...JSON.parse(json), by: teacher }); } catch (_) { /* linha ruim */ }
        }
        lessons.sort((a, b2) => b2.t - a.t);
        return send(200, { ok: true, lessons: lessons.slice(0, LESSONS_KEPT), lr: Number(prof.lr) || 0 });
      }

      // As demais ações mudam dados: limite por hora para cada perfil.
      const mut = await store.incr(`lnkmut:${me}:${hour}`, 3600);
      if (mut.n > MUTATIONS_PER_HOUR) return send(429, { error: 'Muitas alterações. Tente mais tarde.' });

      const other = normCode(b.other);
      const role = b.role === 'teacher' ? 'teacher' : b.role === 'student' ? 'student' : '';
      if (!other || (!role && action !== 'lesson')) return send(400, { error: 'Falta o código do outro ou o papel.' });
      if (other === me) return send(400, { error: 'Você não pode se vincular a si mesmo.' });

      // teacher/student desta ligação, conforme o papel de quem pede.
      const teacher = role === 'teacher' ? me : other;
      const student = role === 'teacher' ? other : me;

      if (action === 'lesson') {
        // O PROFESSOR publica uma aula encerrada para um aluno vinculado a ele.
        const student = normCode(b.other);
        if (!student || student === me) return send(400, { error: 'Falta o código do aluno.' });
        if ((await store.hgetall(T(me)))[student] === undefined) {
          return send(403, { error: 'Este aluno não está vinculado a você.' });
        }
        // Só entrega para um perfil que o aluno JÁ reivindicou (abriu o app com o vínculo ligado):
        // senão quem conhecesse o código poderia reivindicá-lo antes e ler as aulas.
        const sp = await store.hgetall(U(student));
        if (!sp.h) return send(409, { error: 'student_not_ready', message: 'O aluno ainda não abriu o app com o vínculo online ligado.' });
        const lesson = cleanLesson(b.lesson, clock());
        if (!lesson) return send(400, { error: 'Aula inválida.' });
        const rec = { ...lesson, tn: lesson.tn || prof.n || '' };
        const json = JSON.stringify(rec);
        if (json.length > MAX_LESSON_JSON) return send(400, { error: 'Aula grande demais.' });
        const key = UL(student);
        await store.hset(key, `${me}:${lesson.id}`, json);
        // Guarda só as mais recentes: apaga as mais antigas se passar do limite.
        const all = await store.hgetall(key);
        const fields = Object.keys(all);
        if (fields.length > LESSONS_KEPT) {
          const byAge = fields
            .map((fld) => { let tt = 0; try { tt = JSON.parse(all[fld]).t || 0; } catch (_) { /* ruim */ } return [fld, tt]; })
            .sort((x, y) => x[1] - y[1]);
          for (const [fld] of byAge.slice(0, fields.length - LESSONS_KEPT)) await store.hdel(key, fld);
        }
        await store.hset(U(student), 'lr', String(clock())); // o aluno vê que há novidade
        return send(200, { ok: true });
      }

      if (action === 'link') {
        const count = (await store.hlen(T(teacher))) + (await store.hlen(S(student)));
        if (count > MAX_LINKS * 2) return send(400, { error: 'Limite de vínculos atingido.' });
        const existed = (await store.hgetall(T(teacher)))[student] !== undefined;
        const otherProf = await store.hgetall(U(other));
        const now = clock();
        const myName = prof.n || '';
        const theirName = otherProf.n || '';
        // Cada lado guarda o apelido do outro, para listar sem consultas extras.
        const nameOfStudent = role === 'student' ? myName : theirName;
        const nameOfTeacher = role === 'teacher' ? myName : theirName;
        if (!existed) {
          await store.hset(T(teacher), student, JSON.stringify({ n: nameOfStudent, t: now, by: role }));
          await store.hset(S(student), teacher, JSON.stringify({ n: nameOfTeacher, t: now, by: role }));
        }
        return send(200, { ok: true, created: !existed, other: { code: other, name: theirName } });
      }

      if (action === 'unlink') {
        await store.hdel(T(teacher), student);
        await store.hdel(S(student), teacher);
        // As aulas desse professor deixam de existir para esse aluno.
        const lk = UL(student);
        for (const fld of Object.keys(await store.hgetall(lk))) {
          if (fld.startsWith(`${teacher}:`)) await store.hdel(lk, fld);
        }
        return send(200, { ok: true });
      }

      return send(400, { error: 'Ação desconhecida.' });
    } catch (e) {
      if (String(e.message) === 'no-redis') return send(503, { error: 'sync_unavailable' });
      console.error('link error', e && e.message);
      return send(500, { error: 'Erro ao registrar o vínculo. Tente de novo.' });
    }
  };
}

/** Atualiza o apelido de [me] dentro dos vínculos dos outros. */
async function propagateName(store, me, name) {
  const asTeacher = await store.hgetall(T(me)); // meus alunos: neles eu sou o professor
  for (const student of Object.keys(asTeacher)) {
    const raw = (await store.hgetall(S(student)))[me];
    if (raw) await store.hset(S(student), me, JSON.stringify({ ...JSON.parse(raw), n: name }));
  }
  const asStudent = await store.hgetall(S(me)); // meus professores: neles eu sou o aluno
  for (const teacher of Object.keys(asStudent)) {
    const raw = (await store.hgetall(T(teacher)))[me];
    if (raw) await store.hset(T(teacher), me, JSON.stringify({ ...JSON.parse(raw), n: name }));
  }
}

module.exports = makeHandler();
module.exports.makeHandler = makeHandler;
module.exports._internal = { normCode, parseLinks, cleanLesson };
