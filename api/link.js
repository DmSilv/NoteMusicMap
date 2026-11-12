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
//   done     -> ALUNO avisa que fez (ou desmarcou) uma tarefa de um professor { other, lesson, task, done }
//   rev      -> só os contadores de novidade { lr, dr, kr } (1 comando): o app só baixa listas se mudou
//   sched_put-> PROFESSOR marca/muda/cancela uma aula { other, slot } e agenda o lembrete (QStash)
//   sched    -> ALUNO busca as aulas marcadas pelos professores
//   push_key / push_sub / push_unsub -> notificações (Web Push) deste aparelho
//   dones    -> PROFESSOR busca o que os alunos marcaram como feito (e a revisão dr no sync)
//
// Precisa do Upstash Redis. Sem ele devolve 503 e o app segue só neste aparelho.
'use strict';

const crypto = require('node:crypto');
const { config } = require('./_lib/config');
const { createStore } = require('./_lib/store');
const { cleanSlot, cleanMeetUrl, nextStart, slotsOverlap, scheduleNext, remindersEnabled } = require('./_lib/agenda');
const { validSubscription } = require('./_lib/webpush');
const { bump } = require('./_lib/metrics');
const { createCmd } = require('./_lib/store_cmd');
const profiles = require('./_lib/profiles');
const { sweepEmpty } = require('./_lib/sweep');
const { unlinkPair } = require('./_lib/unlink');
const { serverError } = require('./_lib/error_store');
const library = require('./_lib/library');
const features = require('./_lib/features');

const ALPHABET = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
const MAX_LINKS = 300;
const MUTATIONS_PER_HOUR = 60;
const BAD_AUTH_PER_HOUR = 20;
const NEW_PROFILES_PER_DAY = 100; // perfis novos por origem/dia (escola ou igreja com um Wi-Fi só cabe)
const NEW_PROFILES_ALERT = 30; // passou disso numa origem: o painel mostra um aviso
const MAX_BODY = 2048; // bytes: o pedido comum tem ~200
const MAX_LESSON_BODY = 40000; // pedido de publicar aula (30 tarefas com texto cheio cabem)
const MAX_LESSON_JSON = 30000; // aula já limpa
const LESSONS_KEPT = 60; // aulas guardadas por aluno
const PULLS_PER_HOUR = 240;
const DONES_KEPT = 1500; // marcações guardadas por professor
const ID_RE = /^[A-Za-z0-9_-]{1,40}$/;
const MAX_AVAIL = 100; // horários disponíveis por professor
const MAX_PICKS = 12; // aulas de um aluno com o mesmo professor
const PICK_LEAD = 60 * 60 * 1000; // antecedência mínima para pegar
const MAX_SLOTS = 400; // aulas marcadas por professor
const MAX_DEVICES = 4; // aparelhos com notificação por perfil
const TASK_KINDS = ['scale', 'method', 'repertoire', 'free', 'material'];

/** Código "XXXX-XXXX" válido (mesma verificação do app) ou null. */
function normCode(s) {
  if (typeof s !== 'string') return null; // só texto: lista ou objeto não viram código
  const t = s.toUpperCase().replace(/[\s-]/g, '');
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

/** Aviso deixado pelo suporte do painel: { t, k, x } ou null. Vai junto de sync e rev, sem comando extra. */
function parseNotice(raw) {
  if (!raw) return null;
  try {
    const j = JSON.parse(raw);
    const t = Number(j.t);
    if (!Number.isFinite(t) || !['unlink', 'agenda'].includes(j.k)) return null;
    return { t, k: j.k, x: clean(j.x, 60) };
  } catch (_) { return null; }
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
  const limit = b.action === 'lesson' ? MAX_LESSON_BODY : b.action === 'lib_put' ? 4096 : MAX_BODY;
  if (JSON.stringify(b).length > limit) return null;
  return b;
}

const U = (code) => `u:${code}`; // hash do perfil: h (hash do segredo), n (apelido)
const T = (code) => `ut:${code}`; // alunos deste professor: aluno -> JSON
const S = (code) => `us:${code}`; // professores deste aluno: professor -> JSON
const UL = (code) => `ul:${code}`; // aulas deste aluno: "professor:idAula" -> JSON
const SL = (code) => `sl:${code}`; // aulas marcadas pelo professor: idAula -> JSON
const SS = (code) => `ss:${code}`; // aulas marcadas para este aluno: "professor:idAula" -> JSON
const PS = (code) => `ps:${code}`; // aparelhos com notificação: hash do endereço -> inscrição
const AV = (code) => `av:${code}`; // horários disponíveis do professor: idHorário -> JSON
const TK = (code) => `tk:${code}`; // horários já pegos (trava contra dois alunos): idHorário -> aluno
const VD = (code) => `vd:${code}`; // decisões do professor sobre as tarefas deste aluno: "professor:idAula:idTarefa" -> JSON
const DN = (code) => `dn:${code}`;
const LB = (code) => `lb:${code}`; // acervo do professor: idItem -> JSON (só links)
const LBREP = 'lbrep'; // denúncias do acervo: "professor:idItem" -> JSON { n, t } // tarefas que os alunos deste professor marcaram: "aluno:idAula:idTarefa" -> JSON

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
    // Contadores de uso (métricas anônimas): nunca derrubam o pedido.
    const metric = (event, total) => bump(cfg, fetchImpl, clock, { allowMemory: !!deps.allowMemory }, event, { total });
    const cmd = createCmd(cfg, fetchImpl, { allowMemory: !!deps.allowMemory });
    if (!store.durable) {
      return send(503, { error: 'sync_unavailable', message: 'O vínculo online ainda não está configurado.' });
    }

    // Recursos liberados aos poucos (chaves no painel). LIBRARY_TESTERS continua valendo como ponto de partida do acervo.
    const legacy = new Set((cfg.libraryTesters || []).map(normCode).filter(Boolean));
    // Funil de ativação: a PRIMEIRA vez que cada perfil faz cada coisa (1 gravação no perfil + 1 contador por perfil, uma vez só).
    const MS = { linked: 1, klass: 2, task: 4, pick: 8, done: 16 };
    const mileFor = async (code, p, key) => {
      try {
        const bit = MS[key];
        const cur = Number(p && p.ms) || 0;
        if (cur & bit) return;
        if (p) p.ms = String(cur | bit);
        await store.hset(U(code), 'ms', String(cur | bit));
        await cmd.cmd(['HSETNX', 'fn:ms', 'since', String(clock())]);
        await cmd.cmd(['HINCRBY', 'fn:ms', key, '1']);
      } catch (_) { /* contador: nunca atrapalha a ação */ }
    };
    // Aula online: recurso liberado por chave (aba Recursos). Sem a chave o servidor ignora modo e link novos.
    const canOnline = async (c, p) => features.isOn(await features.loadCfg(store, clock()), 'aula_online', c, p, null);
    // Mantém modo e link já guardados quando o pedido veio de um app antigo (sem a chave m) ou sem o recurso ligado.
    const keepOnline = (slot, oldRaw, on) => {
      let old = null;
      try { old = oldRaw ? JSON.parse(oldRaw) : null; } catch (_) { old = null; }
      if (!on) { delete slot.m; delete slot.l; }
      if (old && (!on || slot.m === undefined)) { if (old.m) slot.m = old.m; if (old.l) slot.l = old.l; }
      return slot;
    };
    // Lembrete escolhido pelo professor (recurso por chave): sem a chave o servidor ignora r novo e mantém o que já havia.
    const canRemind = async (c, p) => features.isOn(await features.loadCfg(store, clock()), 'lembrete_escolha', c, p, null);
    const keepRemind = (slot, oldRaw, on) => {
      let old = null;
      try { old = oldRaw ? JSON.parse(oldRaw) : null; } catch (_) { old = null; }
      if (!on) delete slot.r;
      if (old && old.r !== undefined && (!on || slot.r === undefined)) slot.r = old.r;
      return slot;
    };
    const canLib = async (c) => (await features.many(cmd, store, 'acervo', [c], legacy, clock())).has(c);
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

      // Liberação pelo suporte: o aparelho novo prova que tem o código de uso único gerado no painel e
      // passa a ser o dono do perfil (o segredo antigo deixa de valer). Só a tentativa errada conta.
      if (b.action === 'claim') {
        const sup = String(b.support || '').toUpperCase().replace(/[^A-Z0-9]/g, '');
        const bad = async () => {
          const f = await store.incr(failKey, 3600);
          const g = await store.incr(`lnkclaim:${me}:${hour}`, 3600);
          if (f.n > BAD_AUTH_PER_HOUR || g.n > 10) return send(429, { error: 'Muitas tentativas. Tente mais tarde.' });
          return send(403, { error: 'Código de suporte inválido ou vencido.' });
        };
        if (sup.length !== 8) return bad();
        const target = await store.hgetall(U(me));
        if (!target.h || !target.sc || !(Number(target.sx) > clock())) return bad();
        const given = sha(`sup|${me}|${sup}`);
        if (given.length !== target.sc.length || !crypto.timingSafeEqual(Buffer.from(given), Buffer.from(target.sc))) return bad();
        await store.hset(U(me), 'h', sha('lnk|' + secret));
        await store.hdel(U(me), 'sc');
        await store.hdel(U(me), 'sx');
        await store.hset(U(me), 'kr', String(clock()));
        return send(200, { ok: true });
      }

      // Dono do código: o primeiro a usar registra o hash do segredo; depois só ele passa.
      const secretHash = sha('lnk|' + secret);
      let prof = await store.hgetall(U(me));
      if (!prof.h) {
        // Perfil novo: limite por origem e por dia, para ninguém encher o banco de códigos falsos.
        const day = Math.floor(clock() / 86400000);
        const nw = await store.incr(`lnknew:${ipKey}:${day}`, 86400);
        if (nw.n > NEW_PROFILES_PER_DAY) return send(429, { error: 'Muitos perfis novos desta origem hoje. Tente amanhã.' });
        if (nw.n === NEW_PROFILES_ALERT + 1) await profiles.hot(cmd, `${ipKey}:${day}`, clock());
        if (await store.hsetnx(U(me), 'h', secretHash)) {
          await metric(null, { field: 'profiles', by: 1 }); // primeira vez: este segredo passa a ser o dono
          await profiles.created(cmd, me, clock());
          await sweepEmpty(cmd, clock(), 5); // aproveita para limpar perfis abandonados (1 comando se não houver)
        }
        prof = await store.hgetall(U(me));
      }
      const okOwner = prof.h && crypto.timingSafeEqual(Buffer.from(prof.h), Buffer.from(secretHash));
      if (!okOwner) {
        const f = await store.incr(failKey, 3600);
        if (f.n > BAD_AUTH_PER_HOUR) return send(429, { error: 'Muitas tentativas. Tente mais tarde.' });
        return send(403, { error: 'Este código pertence a outro aparelho.' });
      }
      // Perfil bloqueado pelo administrador: nada do vínculo online funciona.
      if (prof.bl === '1') return send(403, { error: 'blocked', message: 'Este perfil foi bloqueado. Fale com o administrador.' });
      // Atividade para o painel (no máximo uma gravação a cada 6 h por perfil).
      if (await profiles.touch(cmd, prof, me, clock())) prof.la = String(clock());
      await profiles.seen(cmd, prof, me, clock()); // presença para o painel (1 gravação a cada 10 min)

      // Apelido opcional (aparece para quem está vinculado a você).
      const name = b.name === undefined ? null : clean(b.name, 40);
      let nameChanged = false;
      if (name !== null && name !== (prof.n || '')) {
        await store.hset(U(me), 'n', name);
        prof.n = name;
        nameChanged = true;
      }

      const action = String(b.action || 'sync');
      const noticeOf = (p) => { const n = parseNotice(p.sn); return n ? { sn: n } : {}; };

      if (action === 'sync') {
        // Mudou o apelido: avisa quem está vinculado (o nome fica dentro de cada vínculo).
        if (nameChanged) await propagateName(store, me, name);
        const [asTeacher, asStudent] = await Promise.all([store.hgetall(T(me)), store.hgetall(S(me))]);
        const stuList = parseLinks(asStudent);
        const feats = await features.forProfile(store, me, prof, legacy, clock());
        const libT = stuList.length ? await features.many(cmd, store, 'acervo', stuList.map((x) => x.code), legacy, clock()) : new Set();
        return send(200, { ok: true, asTeacher: parseLinks(asTeacher), asStudent: stuList, ff: feats, ...(feats.includes('aula_online') && prof.ml ? { ml: prof.ml } : {}), lb: feats.includes('acervo') ? 1 : 0, lbT: stuList.map((x) => x.code).filter((c) => libT.has(c)), lr: Number(prof.lr) || 0, dr: Number(prof.dr) || 0, kr: Number(prof.kr) || 0, sr: Number(prof.sr) || 0, vr: Number(prof.vr) || 0, ar: Number(prof.ar) || 0, ...noticeOf(prof) });
      }

      // Consulta barata: o perfil já foi lido na autenticação, então não custa nenhum comando a mais.
      // lr = aulas novas, dr = tarefas marcadas pelos alunos, kr = vínculos mudaram.
      if (action === 'rev') {
        // Conta 1 em cada 10 consultas (barato) para o painel estimar o custo do polling.
        if (Math.random() < 0.1) await metric('rev10');
        return send(200, { ok: true, lr: Number(prof.lr) || 0, dr: Number(prof.dr) || 0, kr: Number(prof.kr) || 0, sr: Number(prof.sr) || 0, vr: Number(prof.vr) || 0, ar: Number(prof.ar) || 0, ...noticeOf(prof) });
      }

      // O ALUNO vê os horários disponíveis de um professor a que está vinculado (só os que ainda dá para pegar).
      if (action === 'avail') {
        const pulls = await store.incr(`lnkpull:${me}:${hour}`, 3600);
        if (pulls.n > PULLS_PER_HOUR) return send(429, { error: 'Muitas consultas. Tente mais tarde.' });
        const teacher = normCode(b.other);
        if (!teacher || teacher === me) return send(400, { error: 'Falta o código do professor.' });
        if ((await store.hget(S(me), teacher)) === undefined) return send(403, { error: 'Este professor não está vinculado a você.' });
        const raw = await store.hgetall(AV(teacher));
        const now = clock();
        const slots = [];
        for (const json of Object.values(raw)) {
          try {
            const j = JSON.parse(json);
            if (nextStart(j, now + PICK_LEAD) !== null) slots.push(j);
          } catch (_) { /* linha ruim */ }
        }
        slots.sort((x, y) => x.s - y.s);
        return send(200, { ok: true, open: slots.slice(0, MAX_AVAIL) });
      }

      // O PROFESSOR vê as aulas que os alunos pegaram (para entrarem na agenda dele).
      if (action === 'picks') {
        const pulls = await store.incr(`lnkpull:${me}:${hour}`, 3600);
        if (pulls.n > PULLS_PER_HOUR) return send(429, { error: 'Muitas consultas. Tente mais tarde.' });
        const [mine, raw] = await Promise.all([store.hgetall(T(me)), store.hgetall(SL(me))]);
        const slots = [];
        for (const json of Object.values(raw)) {
          try {
            const j = JSON.parse(json);
            if (j.pk === 1 && j.sc && mine[j.sc] !== undefined) slots.push(j);
          } catch (_) { /* linha ruim */ }
        }
        return send(200, { ok: true, slots, ar: Number(prof.ar) || 0 });
      }

      // O ALUNO busca o que o professor decidiu (validou ou devolveu) sobre as suas tarefas.
      if (action === 'verdicts') {
        const pulls = await store.incr(`lnkpull:${me}:${hour}`, 3600);
        if (pulls.n > PULLS_PER_HOUR) return send(429, { error: 'Muitas consultas. Tente mais tarde.' });
        const [mine, raw] = await Promise.all([store.hgetall(S(me)), store.hgetall(VD(me))]);
        const out = [];
        for (const [field, json] of Object.entries(raw)) {
          const [te, les, tsk] = field.split(':');
          if (mine[te] === undefined) continue; // vínculo encerrado: a decisão não vale mais
          try { const j = JSON.parse(json); out.push({ te, l: les, k: tsk, v: j.v, t: j.t || 0 }); } catch (_) { /* linha ruim */ }
        }
        out.sort((a, b2) => b2.t - a.t);
        return send(200, { ok: true, verdicts: out.slice(0, DONES_KEPT), vr: Number(prof.vr) || 0 });
      }

      // O PROFESSOR busca o que os alunos marcaram como feito (só dos alunos ainda vinculados).
      if (action === 'dones') {
        const pulls = await store.incr(`lnkpull:${me}:${hour}`, 3600);
        if (pulls.n > PULLS_PER_HOUR) return send(429, { error: 'Muitas consultas. Tente mais tarde.' });
        const [mine, raw] = await Promise.all([store.hgetall(T(me)), store.hgetall(DN(me))]);
        const dones = [];
        for (const [field, json] of Object.entries(raw)) {
          const [stu, les, tsk] = field.split(':');
          if (mine[stu] === undefined) continue; // vínculo encerrado: a marcação não vale mais
          try { const j = JSON.parse(json); dones.push({ s: stu, l: les, k: tsk, t: j.t || 0 }); } catch (_) { /* linha ruim */ }
        }
        dones.sort((a, b2) => b2.t - a.t);
        return send(200, { ok: true, dones: dones.slice(0, DONES_KEPT), dr: Number(prof.dr) || 0 });
      }

      // Lembretes: o app pergunta se o servidor está pronto para enviar notificações.
      if (action === 'push_key') {
        return send(200, { ok: true, key: remindersEnabled(cfg) ? cfg.vapid.publicKey : '', enabled: remindersEnabled(cfg) });
      }

      // O ALUNO busca as aulas marcadas pelos professores a que ainda está vinculado.
      if (action === 'sched') {
        const pulls = await store.incr(`lnkpull:${me}:${hour}`, 3600);
        if (pulls.n > PULLS_PER_HOUR) return send(429, { error: 'Muitas consultas. Tente mais tarde.' });
        const [mine, raw] = await Promise.all([store.hgetall(S(me)), store.hgetall(SS(me))]);
        const slots = [];
        for (const [field, json] of Object.entries(raw)) {
          const teacher = field.split(':')[0];
          if (mine[teacher] === undefined) continue; // vínculo encerrado: a aula marcada não vale mais
          try { slots.push({ ...JSON.parse(json), by: teacher }); } catch (_) { /* linha ruim */ }
        }
        return send(200, { ok: true, slots, sr: Number(prof.sr) || 0 });
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

      // ---- Acervo e Repertório (só links): leitura. O professor vê tudo; o aluno vê o que é para ele ----
      if (action === 'lib_list') {
        const pulls = await store.incr(`lnkpull:${me}:${hour}`, 3600);
        if (pulls.n > PULLS_PER_HOUR) return send(429, { error: 'Muitas consultas. Tente mais tarde.' });
        const other = b.other === undefined || b.other === '' ? me : normCode(b.other);
        if (!other) return send(400, { error: 'Código inválido.' });
        if (!(await canLib(other))) return send(403, { error: 'library_off' });
        if (other !== me && (await store.hget(S(me), other)) === undefined) return send(403, { error: 'Este professor não está vinculado a você.' });
        const raw = await store.hgetall(LB(other));
        const items = [];
        for (const json of Object.values(raw)) {
          try {
            const it = JSON.parse(json);
            if (other === me || library.visibleTo(it, me)) items.push(it);
          } catch (_) { /* linha ruim */ }
        }
        items.sort((x, y) => (y.m || 0) - (x.m || 0));
        return send(200, { ok: true, items: items.slice(0, library.MAX_ITEMS), teacher: other });
      }

      // As demais ações mudam dados: limite por hora para cada perfil.
      const mut = await store.incr(`lnkmut:${me}:${hour}`, 3600);
      if (mut.n > MUTATIONS_PER_HOUR) return send(429, { error: 'Muitas alterações. Tente mais tarde.' });

      // ---- Acervo: o PROFESSOR liberado cadastra, muda ou apaga; o ALUNO denuncia ----
      if (action === 'lib_put') {
        if (!(await canLib(me))) return send(403, { error: 'library_off' });
        const r = library.cleanItem(b.item, clock(), normCode);
        if (r.error) return send(400, { error: r.error, message: r.message });
        const it = r.item;
        const old = await store.hget(LB(me), it.id);
        if (old === undefined && (await store.hlen(LB(me))) >= library.MAX_ITEMS) return send(400, { error: 'Limite de itens atingido.' });
        if (Array.isArray(it.to)) {
          const mine = await store.hgetall(T(me));
          it.to = it.to.filter((c) => mine[c] !== undefined); // só alunos vinculados
          if (!it.to.length) it.to = 'all';
        }
        if (old !== undefined) { try { const o = JSON.parse(old); if (o.x) it.x = 1; if (o.c) it.c = o.c; } catch (_) { /* ok */ } }
        await store.hset(LB(me), it.id, JSON.stringify(it));
        return send(200, { ok: true, item: it });
      }
      if (action === 'lib_del') {
        if (!(await canLib(me))) return send(403, { error: 'library_off' });
        const id = String(b.id || '');
        if (!/^[a-z0-9]{2,40}$/.test(id)) return send(400, { error: 'Item inválido.' });
        await store.hdel(LB(me), id);
        await store.hdel(LBREP, `${me}:${id}`);
        return send(200, { ok: true });
      }
      if (action === 'lib_report') {
        const teacher = normCode(b.other);
        const id = String(b.id || '');
        if (!teacher || teacher === me || !/^[a-z0-9]{2,40}$/.test(id) || !(await canLib(teacher))) return send(400, { error: 'Pedido inválido.' });
        if ((await store.hget(S(me), teacher)) === undefined) return send(403, { error: 'Este professor não está vinculado a você.' });
        const rawItem = await store.hget(LB(teacher), id);
        if (rawItem === undefined) return send(404, { error: 'Item não encontrado.' });
        let n = 0;
        try { n = (JSON.parse((await store.hget(LBREP, `${teacher}:${id}`)) || '{}').n) || 0; } catch (_) { /* ok */ }
        await store.hset(LBREP, `${teacher}:${id}`, JSON.stringify({ n: n + 1, t: clock() }));
        return send(200, { ok: true });
      }

      // ---- Notificações: inscrição do navegador deste aparelho ----
      if (action === 'push_sub') {
        const sub = validSubscription(b.sub);
        if (!sub) return send(400, { error: 'Inscrição de notificação inválida.' });
        const field = sha(sub.endpoint).slice(0, 24);
        if ((await store.hget(PS(me), field)) === undefined && (await store.hlen(PS(me))) >= MAX_DEVICES) {
          // Passou de 4 aparelhos: sai o mais antigo.
          const all = await store.hgetall(PS(me));
          const oldest = Object.entries(all)
            .map(([f, j]) => { let t = 0; try { t = JSON.parse(j).t || 0; } catch (_) { /* ruim */ } return [f, t]; })
            .sort((x, y) => x[1] - y[1])[0];
          if (oldest) await store.hdel(PS(me), oldest[0]);
        }
        await store.hset(PS(me), field, JSON.stringify({ ...sub, t: clock() }));
        return send(200, { ok: true });
      }
      if (action === 'push_unsub') {
        await store.hdel(PS(me), sha(String(b.endpoint || '')).slice(0, 24));
        return send(200, { ok: true });
      }

      // ---- Horários disponíveis: o PROFESSOR cria, muda ou apaga ----
      if (action === 'avail_put') {
        const slot = cleanSlot(b.slot, clock());
        if (!slot) return send(400, { error: 'Horário inválido.' });
        if (slot.c) {
          await store.hdel(AV(me), slot.id);
          return send(200, { ok: true });
        }
        const oldRaw = await store.hget(AV(me), slot.id);
        keepOnline(slot, oldRaw, await canOnline(me, prof));
        keepRemind(slot, oldRaw, await canRemind(me, prof));
        if (oldRaw === undefined) {
          if ((await store.hlen(AV(me))) >= MAX_AVAIL) return send(400, { error: 'Limite de horários disponíveis atingido.' });
          if ((await store.hget(TK(me), slot.id)) !== undefined) return send(409, { error: 'slot_taken', message: 'Este horário já foi pego.' });
        }
        await store.hset(AV(me), slot.id, JSON.stringify(slot));
        return send(200, { ok: true });
      }

      // ---- O ALUNO pega um horário disponível: o primeiro que pega leva ----
      if (action === 'avail_take') {
        const teacher = normCode(b.other);
        const sid = String(b.slot || '');
        if (!teacher || teacher === me) return send(400, { error: 'Falta o código do professor.' });
        if (!/^[a-z0-9]{2,40}$/.test(sid)) return send(400, { error: 'Horário inválido.' });
        if ((await store.hget(S(me), teacher)) === undefined) return send(403, { error: 'Este professor não está vinculado a você.' });
        const rawOpen = await store.hget(AV(teacher), sid);
        if (rawOpen === undefined) return send(409, { error: 'slot_gone', message: 'Este horário não está mais disponível.' });
        let open;
        try { open = JSON.parse(rawOpen); } catch (_) { return send(409, { error: 'slot_gone', message: 'Este horário não está mais disponível.' }); }
        const now = clock();
        if (nextStart(open, now) === null) return send(409, { error: 'slot_past', message: 'Este horário já passou.' });
        if (nextStart(open, now + PICK_LEAD) === null) return send(409, { error: 'slot_soon', message: 'Falta pouco para este horário: peça direto ao professor.' });
        // Limite de aulas deste aluno com este professor.
        const mineSS = await store.hgetall(SS(me));
        let upcoming = 0;
        for (const [f, j] of Object.entries(mineSS)) {
          if (!f.startsWith(`${teacher}:`)) continue;
          try { if (nextStart(JSON.parse(j), now) !== null) upcoming++; } catch (_) { /* ruim */ }
        }
        if (upcoming >= MAX_PICKS) return send(400, { error: 'pick_limit', message: 'Você já tem muitas aulas marcadas com este professor.' });
        // Não pode bater com outra aula do professor.
        const classes = await store.hgetall(SL(teacher));
        for (const j of Object.values(classes)) {
          let c; try { c = JSON.parse(j); } catch (_) { continue; }
          if (slotsOverlap(open, c, now)) return send(409, { error: 'slot_conflict', message: 'Este horário bate com outra aula do professor.' });
        }
        // Trava: só o primeiro leva.
        if (!(await store.hsetnx(TK(teacher), sid, me))) return send(409, { error: 'slot_taken', message: 'Alguém acabou de pegar este horário.' });
        await store.hdel(AV(teacher), sid);
        const cid = 'p' + crypto.randomBytes(6).toString('hex');
        const cls = { id: cid, s: open.s, d: open.d, u: now };
        if (open.w) cls.w = 1;
        if (open.n) cls.n = open.n;
        if (open.m) cls.m = open.m;
        if (open.r !== undefined) cls.r = open.r;
        if (open.m === 'o') {
          // sem link no horário: usa o link padrão do professor, se ele tiver
          const dl = open.l ? open.l : cleanMeetUrl(await store.hget(U(teacher), 'ml'));
          if (dl) cls.l = dl;
        }
        await store.hset(SL(teacher), cid, JSON.stringify({ ...cls, sc: me, pk: 1 }));
        const tp = await store.hgetall(U(teacher));
        await store.hset(SS(me), `${teacher}:${cid}`, JSON.stringify({ ...cls, tn: tp.n || '' }));
        await store.hset(U(me), 'sr', String(now));
        await store.hset(U(teacher), 'ar', String(now)); // o professor vê que um aluno pegou um horário
        await metric('pick');
        await mileFor(me, prof, 'pick');
        const reminder = await scheduleNext(cfg, fetchImpl, teacher, me, cls, now);
        await metric('slot');
        return send(200, { ok: true, slot: cls, reminder });
      }

      // ---- Link padrão da aula online do professor (vale para os horários livres sem link) ----
      if (action === 'meet_set') {
        if (!(await canOnline(me, prof))) return send(403, { error: 'feature_off' });
        const raw = String(b.link === undefined || b.link === null ? '' : b.link).trim();
        const link = raw ? cleanMeetUrl(raw) : '';
        if (raw && !link) return send(400, { error: 'link_invalid', message: 'Use um link https de uma sala (Meet, Zoom, Teams…).' });
        await store.hset(U(me), 'ml', link);
        return send(200, { ok: true, ml: link });
      }

      // ---- Agenda: o PROFESSOR marca, muda ou cancela uma aula (e agenda o lembrete) ----
      if (action === 'sched_put') {
        const student = normCode(b.other);
        if (!student || student === me) return send(400, { error: 'Falta o código do aluno.' });
        if ((await store.hget(T(me), student)) === undefined) {
          return send(403, { error: 'Este aluno não está vinculado a você.' });
        }
        // Como nas aulas: só entrega para um perfil que o aluno JÁ reivindicou.
        const sp = await store.hgetall(U(student));
        if (!sp.h) return send(409, { error: 'student_not_ready', message: 'O aluno ainda não abriu o app com o vínculo online ligado.' });
        const slot = cleanSlot(b.slot, clock());
        if (!slot) return send(400, { error: 'Aula marcada inválida.' });
        const oldRaw = await store.hget(SL(me), slot.id);
        keepOnline(slot, oldRaw, await canOnline(me, prof));
        keepRemind(slot, oldRaw, await canRemind(me, prof));
        if (oldRaw !== undefined) {
          let old = null;
          try { old = JSON.parse(oldRaw); } catch (_) { /* ruim */ }
          // Versão mais antiga que a guardada: ignora (um pedido atrasado não desfaz o mais novo).
          if (old && old.u > slot.u) return send(200, { ok: true, stale: true });
        } else if ((await store.hlen(SL(me))) >= MAX_SLOTS) {
          return send(400, { error: 'Limite de aulas marcadas atingido.' });
        }
        await store.hset(SL(me), slot.id, JSON.stringify({ ...slot, sc: student }));
        await store.hset(SS(student), `${me}:${slot.id}`, JSON.stringify({ ...slot, tn: prof.n || '' }));
        // Trocou o aluno da aula: o aluno anterior deixa de ver a aula e é avisado.
        let oldStudent = '';
        try { oldStudent = oldRaw ? String(JSON.parse(oldRaw).sc || '') : ''; } catch (_) { oldStudent = ''; }
        if (oldStudent && oldStudent !== student && /^[A-Z0-9]{4}-[A-Z0-9]{4}$/.test(oldStudent)) {
          await store.hdel(SS(oldStudent), `${me}:${slot.id}`);
          await store.hset(U(oldStudent), 'sr', String(clock()));
        }
        await store.hset(U(student), 'sr', String(clock())); // o aluno vê que a agenda mudou
        const reminder = await scheduleNext(cfg, fetchImpl, me, student, slot, clock());
        await metric('slot');
        await mileFor(me, prof, 'klass');
        return send(200, { ok: true, reminder });
      }

      const other = normCode(b.other);
      const role = b.role === 'teacher' ? 'teacher' : b.role === 'student' ? 'student' : '';
      if (!other || (!role && action !== 'lesson' && action !== 'done' && action !== 'verdict')) return send(400, { error: 'Falta o código do outro ou o papel.' });
      if (other === me) return send(400, { error: 'Você não pode se vincular a si mesmo.' });

      // teacher/student desta ligação, conforme o papel de quem pede.
      const teacher = role === 'teacher' ? me : other;
      const student = role === 'teacher' ? other : me;

      // O ALUNO marca (ou desmarca) como feita uma tarefa que recebeu de um professor vinculado.
      if (action === 'done') {
        const teacher = normCode(b.other);
        if (!teacher || teacher === me) return send(400, { error: 'Falta o código do professor.' });
        const lid = String(b.lesson || ''), tid = String(b.task || '');
        if (!/^[a-z0-9]{2,40}$/.test(lid) || !ID_RE.test(tid)) return send(400, { error: 'Tarefa inválida.' });
        if ((await store.hget(S(me), teacher)) === undefined) {
          return send(403, { error: 'Este professor não está vinculado a você.' });
        }
        const field = `${me}:${lid}:${tid}`;
        if (b.done === false) await store.hdel(DN(teacher), field);
        else {
          await store.hset(DN(teacher), field, JSON.stringify({ t: clock() }));
          // Só lê o hash todo (caro) no raro caso de passar do limite; o normal é 1 comando.
          if ((await store.hlen(DN(teacher))) > DONES_KEPT) {
            const all = await store.hgetall(DN(teacher));
            const fields = Object.keys(all);
            const byAge = fields.map((f) => { let tt = 0; try { tt = JSON.parse(all[f]).t || 0; } catch (_) { /* ruim */ } return [f, tt]; }).sort((x, y) => x[1] - y[1]);
            for (const [f] of byAge.slice(0, fields.length - DONES_KEPT)) await store.hdel(DN(teacher), f);
          }
        }
        await store.hset(U(teacher), 'dr', String(clock())); // o professor vê que há novidade
        await mileFor(me, prof, 'done');
        return send(200, { ok: true });
      }

      // O PROFESSOR decide sobre uma tarefa de um aluno vinculado: 'ok' valida, 'back' devolve,
      // vazio apaga a decisão. O aluno vê isso como o status oficial.
      if (action === 'verdict') {
        const student = normCode(b.other);
        if (!student || student === me) return send(400, { error: 'Falta o código do aluno.' });
        const lid = String(b.lesson || ''), tid = String(b.task || '');
        if (!/^[a-z0-9]{2,40}$/.test(lid) || !ID_RE.test(tid)) return send(400, { error: 'Tarefa inválida.' });
        const v = b.verdict === 'ok' ? 'ok' : b.verdict === 'back' ? 'back' : '';
        if (b.verdict !== undefined && b.verdict !== null && b.verdict !== '' && !v) return send(400, { error: 'Decisão inválida.' });
        if ((await store.hget(T(me), student)) === undefined) {
          return send(403, { error: 'Este aluno não está vinculado a você.' });
        }
        const field = `${me}:${lid}:${tid}`;
        if (!v) await store.hdel(VD(student), field);
        else {
          await store.hset(VD(student), field, JSON.stringify({ v, t: clock() }));
          if ((await store.hlen(VD(student))) > DONES_KEPT) {
            const all = await store.hgetall(VD(student));
            const fields = Object.keys(all);
            const byAge = fields.map((f) => { let tt = 0; try { tt = JSON.parse(all[f]).t || 0; } catch (_) { /* ruim */ } return [f, tt]; }).sort((x, y) => x[1] - y[1]);
            for (const [f] of byAge.slice(0, fields.length - DONES_KEPT)) await store.hdel(VD(student), f);
          }
        }
        // Devolvida: a marcação "fiz" do aluno cai, senão o professor a receberia de novo no próximo envio.
        if (v === 'back') await store.hdel(DN(me), `${student}:${lid}:${tid}`);
        await store.hset(U(student), 'vr', String(clock())); // o aluno vê que há decisão nova
        await metric('verdict');
        return send(200, { ok: true });
      }

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
        await metric('lesson');
        await mileFor(me, prof, 'task');
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
          await store.hset(U(teacher), 'kr', String(now)); // os dois lados veem que os vínculos mudaram
          await store.hset(U(student), 'kr', String(now));
          await profiles.setRole(cmd, teacher, 't', true, now);
          await profiles.setRole(cmd, student, 's', true, now);
          await metric('link', { field: 'links', by: 1 });
        }
        await mileFor(me, prof, 'linked');
        await mileFor(other, otherProf, 'linked');
        return send(200, { ok: true, created: !existed, other: { code: other, name: theirName } });
      }

      if (action === 'unlink') {
        const hadLink = await unlinkPair(store, cmd, teacher, student, clock());
        if (hadLink) await metric(null, { field: 'links', by: -1 });
        return send(200, { ok: true });
      }

      return send(400, { error: 'Ação desconhecida.' });
    } catch (e) {
      if (String(e.message) === 'no-redis') return send(503, { error: 'sync_unavailable' });
      console.error('link error', e && e.message);
      await serverError({ cfg, fetchImpl, clock, allowMemory: !!deps.allowMemory }, 'link', e);
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
module.exports._internal = { normCode, parseLinks, cleanLesson, parseNotice };
