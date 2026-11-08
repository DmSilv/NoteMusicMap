// POST /api/link: vínculo entre professor e aluno, registrado dos dois lados.
//
// Quem lê o QR (ou digita o código) do outro cria o vínculo; ele passa a valer
// para os dois, e cada um vê o outro na sua lista na próxima atualização.
//
// O servidor guarda só: o código de cada perfil, o apelido opcional, um hash do
// segredo (para provar que o código é seu) e a lista de vínculos com a data. Nenhum
// exercício, áudio, tarefa ou observação passa por aqui.
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
const MAX_BODY = 2048; // bytes: o pedido real tem ~200

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
const clean = (v, max) => String(v == null ? '' : v).replace(/[\u0000-\u001f\u007f]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, max);

function clientIp(req) {
  const xf = String(req.headers['x-forwarded-for'] || '').split(',')[0].trim();
  return xf || (req.socket && req.socket.remoteAddress) || 'ip-desconhecido';
}

function readBody(req) {
  // Pedido grande demais nunca é um pedido do app: nem tenta ler.
  const len = Number(req.headers && req.headers['content-length']);
  if (Number.isFinite(len) && len > MAX_BODY) return null;
  let b = null;
  if (req.body && typeof req.body === 'object') b = req.body;
  else if (typeof req.body === 'string') {
    if (req.body.length > MAX_BODY) return null;
    try { b = JSON.parse(req.body); } catch (_) { return null; }
  }
  if (!b || typeof b !== 'object' || Array.isArray(b)) return null;
  if (JSON.stringify(b).length > MAX_BODY) return null;
  return b;
}

const U = (code) => `u:${code}`; // hash do perfil: h (hash do segredo), n (apelido)
const T = (code) => `ut:${code}`; // alunos deste professor: aluno -> JSON
const S = (code) => `us:${code}`; // professores deste aluno: professor -> JSON

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
        return send(200, { ok: true, asTeacher: parseLinks(asTeacher), asStudent: parseLinks(asStudent) });
      }

      // As demais ações mudam dados: limite por hora para cada perfil.
      const mut = await store.incr(`lnkmut:${me}:${hour}`, 3600);
      if (mut.n > MUTATIONS_PER_HOUR) return send(429, { error: 'Muitas alterações. Tente mais tarde.' });

      const other = normCode(b.other);
      const role = b.role === 'teacher' ? 'teacher' : b.role === 'student' ? 'student' : '';
      if (!other || !role) return send(400, { error: 'Falta o código do outro ou o papel.' });
      if (other === me) return send(400, { error: 'Você não pode se vincular a si mesmo.' });

      // teacher/student desta ligação, conforme o papel de quem pede.
      const teacher = role === 'teacher' ? me : other;
      const student = role === 'teacher' ? other : me;

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
module.exports._internal = { normCode, parseLinks };
