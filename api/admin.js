// /api/admin: painel do administrador (indicadores e gestão de perfis anônimos).
//
//  POST { action, ... } com "Authorization: Bearer <chave de admin>". Ações:
//   kpis                       indicadores (total, ativos x inativos, professores, crescimento, retenção)
//   list {offset?, q?, by?}    perfis, do mais recente ao mais antigo (busca por trecho do código; by:'name' busca pelo apelido nos 100 mais recentes)
//   detail {code}              um perfil: papel, vínculos, volume de dados (NUNCA o segredo)
//   block / unblock {code}     impede / libera o vínculo online do perfil
//   delete {code, confirm}     apaga os dados e vínculos do perfil (confirm tem que ser o código)
//   bugs {days,sev,status,ver,plat,code,q,offset}  bugs agrupados (relatórios de erro do app), com filtros
//   bug {fp}                   um bug: pilha, trilha, ambiente, últimas ocorrências, tendência
//   bug_status {fp,status,note?}  marca como seen | resolved | ignored | new (e anota)
//   system                     banco (teste de conexão, tamanho), servidor (versão, erros), variáveis configuradas e limites
//   log                        últimas ações do administrador
//  Suporte (tudo registrado no log e avisado ao usuário no app):
//   unlink {code, other, as}   encerra um vínculo; "as" é o papel de {code}: teacher | student
//   agenda {code}              agenda do perfil: aulas que marcou, horários livres, aulas que recebeu
//   agenda_del {code, kind, id, other?}  apaga um item travado (kind: class | avail | mine; mine pede other = professor)
//   support_code {code}        gera o código de uso único (24 h) para liberar a conta em outro aparelho
//   support_cancel {code}      cancela o código pendente
//   indicators                 saúde do uso: notificações negadas, versões antigas, cota de IA, bloqueados, online
//   push {op}                  avisos de bug grave neste navegador: status | sub {sub} | unsub {endpoint} | test
//   presence                   quem está online agora (sinal nos últimos 12 min) e quem esteve há pouco
//  Recursos liberados aos poucos (docs/PLANO_AULA_ONLINE_AGENDA_ADMIN.md, seção 6):
//   features                   um cartão por recurso: estado, % e quem está na lista
//   feature_set {id, mode, pct?}        off | list | pct | all
//   feature_grant {id, code, students?} libera um código (e, se students, os alunos vinculados a ele)
//   feature_revoke {id, code, students?} tira da lista
//
// Não há cadastro nem login no app: "usuário" = perfil anônimo (código + apelido). O apelido pertence
// ao usuário (volta a cada sincronização), por isso o painel não o edita.
// Custo: só quando o admin abre o painel (kpis ~35 comandos; lista de 25 = ~27; detalhe = ~12).
'use strict';

const crypto = require('node:crypto');
const { config } = require('./_lib/config');
const { createStore } = require('./_lib/store');
const { createCmd } = require('./_lib/store_cmd');
const { K, dayKey, BR_OFFSET } = require('./_lib/metrics');
const profiles = require('./_lib/profiles');
const { sweepEmpty, STALE_MS } = require('./_lib/sweep');
const { serverError } = require('./_lib/error_store');
const { unlinkPair } = require('./_lib/unlink');
const adminPush = require('./_lib/admin_push');
const { validSubscription } = require('./_lib/webpush');
const { K: EK, day: errDay, hour: errHour, sanitize } = require('./_lib/errors_lib');
const features = require('./_lib/features');

const { Z } = profiles;
const sha = (s) => crypto.createHash('sha256').update(String(s)).digest('hex');
const DAY = 86400000;
const PAGE = 25;
const SEARCH_SCAN = 500; // a busca olha os 500 perfis mais recentes (1 comando)
const NAME_SCAN = 100; // a busca por apelido lê o apelido dos 100 mais recentes (100 comandos)
const COHORT = 300; // amostra máxima para a retenção
const U = (c) => `u:${c}`, T = (c) => `ut:${c}`, S = (c) => `us:${c}`, SL = (c) => `sl:${c}`, SS = (c) => `ss:${c}`;
const LB = (c) => `lb:${c}`; // acervo do professor (só links)
const UL = (c) => `ul:${c}`, DN = (c) => `dn:${c}`, VD = (c) => `vd:${c}`, AV = (c) => `av:${c}`, TK = (c) => `tk:${c}`, PS = (c) => `ps:${c}`;
const CODE_RE = /^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}-[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}$/;
const LOG = 'adm:log';
const BLOCKED = 'pf:bl'; // conjunto dos perfis bloqueados (para contar sem varrer)
const BUDGET = 500000; // comandos por mês no plano gratuito do Upstash
// Comandos do Redis por ação (aproximado; ver docs/CUSTOS_E_REGRESSAO.md).
const COST = { open: 11, new: 1, rev: 1, lesson: 6, slot: 8, remind: 4, link: 12, verdict: 4, pick: 12, error: 23, beatsPerUser: 6 };
const SCAN_BUGS = 60; // quantos bugs (do mais recente) a lista examina por consulta
const BUG_PAGE = 25;
const SUPPORT_TTL = 24 * 3600 * 1000;
const ALPHA = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
const ID_RE = /^[A-Za-z0-9_-]{1,40}$/;
const FP_RE = /^[0-9a-f]{12}$/;

function clientIp(req) {
  const xf = String((req.headers && req.headers['x-forwarded-for']) || '').split(',')[0].trim();
  return xf || (req.socket && req.socket.remoteAddress) || 'ip';
}

const pairs = (flat) => {
  const out = [];
  for (let i = 0; i + 1 < (flat || []).length; i += 2) out.push([flat[i], Number(flat[i + 1]) || 0]);
  return out;
};

function parseLinks(h) {
  const out = [];
  for (const [code, json] of Object.entries(h || {})) {
    let n = '';
    try { n = String(JSON.parse(json).n || ''); } catch (_) { /* ruim */ }
    let t = 0;
    try { t = Number(JSON.parse(json).t) || 0; } catch (_) { /* ruim */ }
    out.push({ code, name: n, since: t });
  }
  return out;
}

function makeHandler(deps = {}) {
  const fetchImpl = deps.fetch || globalThis.fetch;
  const getCfg = deps.config || (() => config());
  const clock = deps.now || Date.now;
  return async function handler(req, res) {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('X-Robots-Tag', 'noindex');
    const send = (code, obj) => { res.statusCode = code; res.end(JSON.stringify(obj)); };
    if (req.method !== 'POST') return send(405, { error: 'Use POST.' });

    const cfg = getCfg();
    const opts = { allowMemory: !!deps.allowMemory };
    const cmd = createCmd(cfg, fetchImpl, opts);
    const store = createStore(cfg, fetchImpl, clock, opts);
    if (!cmd.durable) return send(503, { error: 'sync_unavailable' });
    if (!cfg.adminKey) return send(404, { error: 'Painel não configurado (falta a chave de admin).' });
    const now = clock();

    let b = req.body;
    if (typeof b === 'string') { try { b = JSON.parse(b); } catch (_) { b = null; } }
    if (!b || typeof b !== 'object' || JSON.stringify(b).length > 2048) return send(400, { error: 'Corpo inválido.' });

    try {
      // Chave de admin; só a tentativa errada conta contra o limite.
      const ip = sha(clientIp(req)).slice(0, 16);
      const hk = `adm:bad:${ip}:${Math.floor(now / 3600000)}`;
      const [bad] = await cmd.pipeline([['INCR', hk], ['EXPIRE', hk, '3600', 'NX']]);
      const given = String((req.headers && (req.headers.authorization || req.headers.Authorization)) || '').replace(/^Bearer\s+/i, '');
      const ok = crypto.timingSafeEqual(Buffer.from(sha(given)), Buffer.from(sha(cfg.adminKey)));
      if (!ok) {
        if (Number(bad) > 10) return send(429, { error: 'Muitas tentativas. Tente mais tarde.' });
        return send(401, { error: 'Chave inválida.' });
      }

      const action = String(b.action || '');
      const code = String(b.code || '').toUpperCase();
      const needCode = () => {
        if (CODE_RE.test(code)) return false;
        send(400, { error: 'Código inválido.' });
        return true;
      };
      const log = (a, c, x) => cmd.pipeline([['LPUSH', LOG, JSON.stringify(x ? { t: now, a, c, x } : { t: now, a, c })], ['LTRIM', LOG, '0', '199']]);
      // Aviso que o app mostra ao usuário na próxima atualização (viaja junto da sincronização).
      const notify = (c, k, x) => store.hset(U(c), 'sn', JSON.stringify({ t: now, k, x: String(x || '').slice(0, 60) }));

      // ---------------- Indicadores ----------------
      if (action === 'kpis') {
        const d1 = now - DAY, d7 = now - 7 * DAY, d30 = now - 30 * DAY;
        const days = [];
        for (let i = 13; i >= 0; i--) days.push(dayKey(now - i * DAY));
        const dayRange = (d) => {
          const start = Date.parse(`${d}T00:00:00Z`) + BR_OFFSET;
          return [String(start), String(start + DAY - 1)];
        };
        const list = [
          ['ZCARD', Z.last], ['ZCOUNT', Z.last, String(d1), '+inf'], ['ZCOUNT', Z.last, String(d7), '+inf'], ['ZCOUNT', Z.last, String(d30), '+inf'],
          ['ZCOUNT', Z.born, String(d7), '+inf'], ['ZCOUNT', Z.born, String(d30), '+inf'],
          ['ZCARD', Z.teach], ['ZCOUNT', Z.teach, String(d30), '+inf'], ['ZCARD', Z.stud], ['ZCOUNT', Z.stud, String(d30), '+inf'],
          ['HGETALL', K.total],
          ['ZRANGEBYSCORE', Z.born, String(now - 90 * DAY), String(d1), 'WITHSCORES', 'LIMIT', '0', String(COHORT)],
          ...days.map((d) => ['ZCOUNT', Z.born, ...dayRange(d)]),
        ];
        const r = await cmd.pipeline(list);
        const totalsFlat = r[10] || [];
        const totals = Object.fromEntries(pairs(totalsFlat));
        const cohort = pairs(r[11]).map(([c, ca]) => ({ c: String(c), ca }));
        // Retenção: dos que entraram há pelo menos N dias, quantos voltaram a partir do dia N.
        let retention = { d1: null, d7: null, d30: null, sample: cohort.length };
        let cohorts = [];
        if (cohort.length) {
          const lasts = await cmd.cmd(['ZMSCORE', Z.last, ...cohort.map((x) => x.c)]);
          const rows = cohort.map((x, i) => ({ ca: x.ca, la: Number(lasts[i]) || 0 }));
          const calc = (n) => {
            const el = rows.filter((x) => x.ca <= now - n * DAY);
            if (!el.length) return null;
            const back = el.filter((x) => x.la >= x.ca + n * DAY).length;
            return { pct: Math.round((back / el.length) * 100), back, of: el.length };
          };
          retention = { d1: calc(1), d7: calc(7), d30: calc(30), sample: cohort.length };
          // Coortes por semana de entrada (segunda-feira, horário do Brasil): quantos voltaram em D1, D7 e D30.
          const weeks = new Map();
          for (const x of rows) {
            const dt = new Date(x.ca - 3 * 3600 * 1000);
            const dow = (dt.getUTCDay() + 6) % 7; // segunda = 0
            const wk = new Date(Date.UTC(dt.getUTCFullYear(), dt.getUTCMonth(), dt.getUTCDate() - dow)).toISOString().slice(0, 10);
            (weeks.get(wk) || weeks.set(wk, []).get(wk)).push(x);
          }
          cohorts = [...weeks.entries()].sort((p, q) => (p[0] < q[0] ? 1 : -1)).slice(0, 8).map(([week, rs]) => {
            const at = (n) => {
              const el = rs.filter((x) => x.ca <= now - n * DAY);
              if (!el.length) return null;
              const back = el.filter((x) => x.la >= x.ca + n * DAY).length;
              return { pct: Math.round((back / el.length) * 100), back, of: el.length };
            };
            return { week, size: rs.length, d1: at(1), d7: at(7), d30: at(30) };
          });
        }
        const total = Number(r[0]) || 0;
        const active30 = Number(r[3]) || 0;
        return send(200, {
          ok: true, now,
          profiles: { total, active1: Number(r[1]) || 0, active7: Number(r[2]) || 0, active30, inactive: Math.max(0, total - active30), new7: Number(r[4]) || 0, new30: Number(r[5]) || 0 },
          teachers: { total: Number(r[6]) || 0, active30: Number(r[7]) || 0 },
          students: { total: Number(r[8]) || 0, active30: Number(r[9]) || 0 },
          links: totals.links || 0,
          growth: days.map((d, i) => ({ day: d, news: Number(r[12 + i]) || 0 })),
          retention, cohorts,
        });
      }

      // ---------------- Lista ----------------
      if (action === 'list') {
        const offset = Math.max(0, Math.min(100000, Math.round(Number(b.offset)) || 0));
        const byName = b.by === 'name';
        const nameQ = byName ? String(b.q || '').replace(/[\u0000-\u001f]/g, ' ').trim().toLowerCase().slice(0, 40) : '';
        const q = byName ? '' : String(b.q || '').toUpperCase().replace(/[^A-Z0-9-]/g, '').slice(0, 9);
        let rows; // [[code, la]]
        let total = null;
        if (byName && nameQ) {
          const scan = pairs(await cmd.cmd(['ZREVRANGE', Z.last, '0', String(NAME_SCAN - 1), 'WITHSCORES']));
          const names = scan.length ? await cmd.pipeline(scan.map(([c]) => ['HGET', U(String(c)), 'n'])) : [];
          const hit = scan.filter((_, i) => String(names[i] || '').toLowerCase().includes(nameQ));
          total = hit.length;
          rows = hit.slice(offset, offset + PAGE);
        } else if (q) {
          const scan = pairs(await cmd.cmd(['ZREVRANGE', Z.last, '0', String(SEARCH_SCAN - 1), 'WITHSCORES'])).filter(([c]) => String(c).includes(q));
          total = scan.length;
          rows = scan.slice(offset, offset + PAGE);
        } else {
          const [rng, card] = await cmd.pipeline([['ZREVRANGE', Z.last, String(offset), String(offset + PAGE - 1), 'WITHSCORES'], ['ZCARD', Z.last]]);
          rows = pairs(rng);
          total = Number(card) || 0;
        }
        const infos = rows.length ? await cmd.pipeline(rows.map(([c]) => ['HMGET', U(String(c)), 'n', 'ca', 'rt', 'rs', 'bl'])) : [];
        const items = rows.map(([c, la], i) => {
          const [n, ca, rt, rs, bl] = infos[i] || [];
          return { code: String(c), name: n || '', la, ca: Number(ca) || 0, teacher: rt === '1', student: rs === '1', blocked: bl === '1', inactive: la < now - 30 * DAY };
        });
        return send(200, { ok: true, items, total, offset, page: PAGE, scanned: byName && nameQ ? NAME_SCAN : (q ? SEARCH_SCAN : null) });
      }

      // ---------------- Detalhe ----------------
      if (action === 'detail') {
        if (needCode()) return;
        const prof = await store.hgetall(U(code));
        if (!prof.h) return send(404, { error: 'Perfil não encontrado.' });
        const [students, teachers] = await Promise.all([store.hgetall(T(code)), store.hgetall(S(code))]);
        const stuList = parseLinks(students), teaList = parseLinks(teachers);
        const linked = [...stuList, ...teaList].map((x) => x.code).slice(0, 200);
        const lasts = linked.length ? await cmd.cmd(['ZMSCORE', Z.last, ...linked]) : [];
        const lastOf = Object.fromEntries(linked.map((c, i) => [c, Number(lasts && lasts[i]) || 0]));
        for (const x of [...stuList, ...teaList]) x.last = lastOf[x.code] || 0;
        const counts = await cmd.pipeline([SL, SS, UL, DN, VD, AV, TK, PS].map((f) => ['HLEN', f(code)]));
        const [classesMade, classesIn, lessonsIn, doneMarks, verdicts, openSlots, taken, devices] = counts.map((x) => Number(x) || 0);
        return send(200, {
          ok: true,
          profile: { code, name: prof.n || '', created: Number(prof.ca) || 0, last: Number(prof.la) || 0, blocked: prof.bl === '1' },
          students: stuList,
          teachers: teaList,
          alsoStudent: stuList.length > 0 && teaList.length > 0,
          support: { pendingUntil: Number(prof.sx) > now ? Number(prof.sx) : 0 },
          data: { classesMade, classesIn, lessonsIn, doneMarks, verdicts, openSlots, taken, pushDevices: devices },
        });
      }

      // ---------------- Bloquear / liberar ----------------
      if (action === 'block' || action === 'unblock') {
        if (needCode()) return;
        if ((await store.hget(U(code), 'h')) === undefined) return send(404, { error: 'Perfil não encontrado.' });
        await store.hset(U(code), 'bl', action === 'block' ? '1' : '0');
        await cmd.cmd([action === 'block' ? 'SADD' : 'SREM', BLOCKED, code]);
        await log(action, code);
        return send(200, { ok: true, blocked: action === 'block' });
      }

      // ---------------- Excluir ----------------
      if (action === 'delete') {
        if (needCode()) return;
        if (String(b.confirm || '').toUpperCase() !== code) return send(400, { error: 'confirm_required', message: 'Para excluir, repita o código do perfil.' });
        if ((await store.hget(U(code), 'h')) === undefined) return send(404, { error: 'Perfil não encontrado.' });
        const [students, teachers] = await Promise.all([store.hgetall(T(code)), store.hgetall(S(code))]);
        const wipePrefix = async (key, prefix) => {
          for (const f of Object.keys(await store.hgetall(key))) if (f.startsWith(prefix)) await store.hdel(key, f);
        };
        for (const st of Object.keys(students)) { // este perfil era o professor deles
          await store.hdel(S(st), code);
          await wipePrefix(SS(st), `${code}:`);
          await wipePrefix(UL(st), `${code}:`);
          await wipePrefix(VD(st), `${code}:`);
          await store.hset(U(st), 'kr', String(now));
          if ((await store.hlen(S(st))) === 0) await profiles.setRole(cmd, st, 's', false, now);
        }
        for (const te of Object.keys(teachers)) { // este perfil era o aluno deles
          await store.hdel(T(te), code);
          await wipePrefix(DN(te), `${code}:`);
          const sl = await store.hgetall(SL(te));
          for (const [id, json] of Object.entries(sl)) {
            try { if (JSON.parse(json).sc === code) await store.hdel(SL(te), id); } catch (_) { /* ruim */ }
          }
          await store.hset(U(te), 'kr', String(now));
          if ((await store.hlen(T(te))) === 0) await profiles.setRole(cmd, te, 't', false, now);
        }
        for (const key of [T, S, SL, SS, UL, DN, VD, AV, TK, PS, LB, U]) {
          for (const f of Object.keys(await store.hgetall(key(code)))) await store.hdel(key(code), f);
        }
        await profiles.forget(cmd, code);
        await cmd.cmd(['SREM', BLOCKED, code]);
        await cmd.cmd(['HINCRBY', K.total, 'profiles', '-1']);
        await log('delete', code);
        return send(200, { ok: true });
      }

      // ---------------- Indicadores de saúde do uso ----------------
      // Custo: 3 comandos + 7 leituras (um hash por dia). Só quando o admin abre ou toca em Atualizar.
      if (action === 'indicators') {
        const dayKeys = [];
        for (let i = 6; i >= 0; i--) dayKeys.push(dayKey(now - i * DAY));
        const aiDay = new Date(now).toISOString().slice(0, 10);
        const [blocked, onlineNow, aiRaw, hotOrigins, staleProfiles, ...dims] = await cmd.pipeline([
          ['SCARD', BLOCKED], ['ZCOUNT', Z.on, String(now - profiles.ONLINE_WINDOW), '+inf'], ['GET', `gd:${aiDay}`],
          ['ZCOUNT', Z.hot, String(now - 7 * DAY), '+inf'], ['ZCOUNT', Z.last, '-inf', String(now - STALE_MS)],
          ...dayKeys.map((d2) => ['HGETALL', K.dim(d2)]),
        ]);
        const commit = ((cfg.env || {}).VERCEL_GIT_COMMIT_SHA || '').slice(0, 7) || null;
        const nt = { sim: 0, nao: 0, nd: 0, na: 0 };
        let devices = 0, onCurrent = 0, withVersion = 0;
        for (const flat of dims) {
          for (let i = 0; i + 1 < (flat || []).length; i += 2) {
            const f = String(flat[i]);
            if (!f.startsWith('x:')) continue;
            const n = Number(flat[i + 1]) || 0;
            const p = f.slice(2).split('|'); // ordem: ver DEV_FIELDS em api/stats.js (nt = 8, v = 9)
            devices += n;
            if (nt[p[8]] !== undefined) nt[p[8]] += n;
            if (p[9] && p[9] !== '-') { withVersion += n; if (commit && p[9] === commit) onCurrent += n; }
          }
        }
        const asked = nt.sim + nt.nao + nt.nd;
        const pct = (a, b2) => (b2 > 0 ? Math.round((a / b2) * 1000) / 10 : null);
        return send(200, {
          ok: true, now, days: 7, devices,
          notifications: { granted: nt.sim, denied: nt.nao, notAsked: nt.nd, unsupported: nt.na, deniedPct: pct(nt.nao, nt.sim + nt.nao), notAskedPct: pct(nt.nd, asked) },
          versions: { current: commit, withVersion, outdated: commit ? withVersion - onCurrent : null, outdatedPct: commit ? pct(withVersion - onCurrent, withVersion) : null },
          ai: { today: Number(aiRaw) || 0, limit: cfg.rpd || 0, pct: cfg.rpd ? pct(Number(aiRaw) || 0, cfg.rpd) : null },
          blockedProfiles: Number(blocked) || 0, onlineProfiles: Number(onlineNow) || 0,
          hotOrigins: Number(hotOrigins) || 0, staleProfiles: Number(staleProfiles) || 0,
        });
      }

      // ---------------- Acervo e Repertório (professores de teste) ----------------
      if (action === 'library') {
        const codes = (cfg.libraryTesters || []).map((c) => String(c).toUpperCase()).filter((c) => CODE_RE.test(c));
        const list = [];
        for (const c of codes) list.push(['HLEN', LB(c)], ['HGET', U(c), 'n']);
        const r = list.length ? await cmd.pipeline(list) : [];
        const testers = codes.map((c, i) => ({ code: c, items: Number(r[i * 2]) || 0, name: r[i * 2 + 1] || '' }));
        const reps = await store.hgetall('lbrep');
        const reports = [];
        for (const [f, json] of Object.entries(reps).slice(0, 50)) {
          const [teacher, id] = f.split(':');
          let n = 0, t = 0; try { const j = JSON.parse(json); n = j.n; t = j.t; } catch (_) { /* ok */ }
          let item = null; try { item = JSON.parse((await store.hget(LB(teacher), id)) || 'null'); } catch (_) { /* ok */ }
          if (item) reports.push({ teacher, id, n, t, title: item.t, url: item.u, hidden: !!item.x });
        }
        return send(200, { ok: true, testers, reports, hosts: require('./_lib/library').HOSTS });
      }
      if (action === 'library_hide') {
        const teacher = String(b.teacher || '').toUpperCase();
        const id = String(b.id || '');
        if (!CODE_RE.test(teacher) || !ID_RE.test(id)) return send(400, { error: 'Pedido inválido.' });
        const raw = await store.hget(LB(teacher), id);
        if (raw === undefined) return send(404, { error: 'Item não encontrado.' });
        const it = JSON.parse(raw);
        if (b.hide === false) delete it.x; else it.x = 1;
        await store.hset(LB(teacher), id, JSON.stringify(it));
        await log(b.hide === false ? 'lib_show' : 'lib_hide', teacher, id);
        return send(200, { ok: true });
      }

      // ---------------- Visitantes (quem usa sem cadastro): divulgação e engajamento ----------------
      // Custo: ~35 comandos por abertura da aba (7 dias de contadores + abas de hoje + 4 contagens).
      if (action === 'visitors') {
        const VT = ['tuner', 'metronome', 'grid', 'scales', 'study', 'pedal'];
        const dl = [];
        for (let i = 6; i >= 0; i--) dl.push(dayKey(now - i * DAY));
        const today = dl[6], yesterday = dl[5];
        const dayStart = Date.parse(`${today}T00:00:00Z`) + BR_OFFSET;
        const list = [];
        for (const d of dl) { list.push(['PFCOUNT', K.day(d)], ['HGETALL', K.ct(d)], ['HGETALL', K.dim(d)]); }
        for (const t of VT) list.push(['PFCOUNT', K.tab(today, t)]);
        list.push(['PFCOUNT', K.day(today), K.day(yesterday)]);
        list.push(['PFCOUNT', K.day(dl[0]), K.day(dl[1]), K.day(dl[2]), K.day(dl[3]), K.day(dl[4]), K.day(dl[5]), K.day(dl[6])]);
        list.push(['ZCOUNT', Z.last, String(dayStart), '+inf'], ['ZCOUNT', Z.born, String(dayStart), '+inf'], ['ZCOUNT', K.online, String(now - 5 * 60 * 1000), '+inf']);
        const r = await cmd.pipeline(list);
        const hash = (flat) => { const o = {}; for (let i = 0; i + 1 < (flat || []).length; i += 2) o[flat[i]] = Number(flat[i + 1]) || 0; return o; };
        const days = dl.map((d, i) => {
          const dim = hash(r[i * 3 + 2]);
          const origins = {};
          for (const [f, n] of Object.entries(dim)) if (f.startsWith('o:')) origins[f.slice(2)] = n;
          const ct = hash(r[i * 3 + 1]);
          return { day: d, users: Number(r[i * 3]) || 0, news: ct.new || 0, opens: ct.open || 0, origins, hours: Array.from({ length: 24 }, (_, h) => ct['h' + String(h).padStart(2, '0')] || 0) };
        });
        let k = 21;
        const tabs = {};
        for (const t of VT) tabs[t] = Number(r[k++]) || 0;
        const union2 = Number(r[k++]) || 0;
        const union7 = Number(r[k++]) || 0;
        const profActive = Number(r[k++]) || 0, profNew = Number(r[k++]) || 0, online5 = Number(r[k++]) || 0;
        const td = days[6], yd = days[5];
        const back = Math.max(0, Math.min(td.users, yd.users, td.users + yd.users - union2)); // aparelhos de ontem que voltaram hoje
        // Fichas de hoje: instalação, microfone, notificações e região (ver DEV_FIELDS em api/stats.js).
        const dimToday = hash(r[2 + 6 * 3]);
        const perms = { mic: {}, nt: {}, in: {} };
        const geo = {};
        let ficha = 0;
        for (const [f, n] of Object.entries(dimToday)) {
          if (!f.startsWith('x:')) continue;
          const p = f.slice(2).split('|');
          ficha += n;
          const add = (o, key) => { o[key] = (o[key] || 0) + n; };
          add(perms.in, p[1] || '-'); add(perms.mic, p[7] || '-'); add(perms.nt, p[8] || '-');
          if (p[10] && p[10] !== '-') add(geo, p[10]);
        }
        const topGeo = Object.entries(geo).sort((a, b) => b[1] - a[1]).slice(0, 6);
        return send(200, {
          ok: true, now, today, days,
          users: td.users, news: td.news, returning: Math.max(0, td.users - td.news), opens: td.opens,
          noProfileEst: Math.max(0, td.users - profActive), profilesActive: profActive, profilesNew: profNew, online5,
          yesterday: { users: yd.users, news: yd.news }, backFromYesterday: back, uniq7: union7,
          tabs, perms, ficha, geo: topGeo,
        });
      }

      // Limpa agora os perfis abandonados (sem vínculo, sem dados e parados há 60 dias). Até 30 por toque.
      // ---------------- Recursos liberados aos poucos ----------------
      if (action === 'features') {
        const legacy = new Set((cfg.libraryTesters || []).map((c) => String(c).toUpperCase()));
        return send(200, { ok: true, items: await features.overview(store, cmd, legacy, now), modes: features.MODES });
      }
      if (action === 'feature_set') {
        const id = String(b.id || '');
        const mode = String(b.mode || '');
        if (!features.known(id)) return send(400, { error: 'Recurso desconhecido.' });
        if (!features.MODES.includes(mode)) return send(400, { error: 'Estado inválido.' });
        const pct = Math.round(Number(b.pct));
        if (mode === 'pct' && !(pct >= 1 && pct <= 99)) return send(400, { error: 'Escolha de 1% a 99%.' });
        const before = (await features.loadCfg(store, 0))[id];
        await features.setMode(store, id, mode, mode === 'pct' ? pct : 0, now);
        await log('feature_set', id, `${before.m}${before.m === 'pct' ? ':' + before.p : ''} -> ${mode}${mode === 'pct' ? ':' + pct : ''}`);
        return send(200, { ok: true });
      }
      if (action === 'feature_grant' || action === 'feature_revoke') {
        const id = String(b.id || '');
        if (!features.known(id)) return send(400, { error: 'Recurso desconhecido.' });
        if (needCode()) return;
        if ((await store.hget(U(code), 'h')) === undefined) return send(404, { error: 'Perfil não encontrado.' });
        const on = action === 'feature_grant';
        const targets = [code];
        if (b.students === true && features.FEATURES[id].students) {
          const mine = Object.keys(await store.hgetall(T(code))).filter((c) => CODE_RE.test(c)).slice(0, features.MAX_GRANT);
          targets.push(...mine);
        }
        for (const c of targets) await (on ? features.grant : features.revoke)(store, cmd, id, c);
        await log(action, code, `${id}${targets.length > 1 ? ' +' + (targets.length - 1) + ' alunos' : ''}`);
        return send(200, { ok: true, changed: targets.length });
      }

      if (action === 'sweep') {
        let removed = 0;
        for (let i = 0; i < 3; i++) {
          const n = await sweepEmpty(cmd, now, 10);
          removed += n;
          if (n < 10) break;
        }
        await log('sweep', String(removed));
        return send(200, { ok: true, removed });
      }

      // ---------------- Avisos de bug grave neste navegador ----------------
      if (action === 'push') {
        const op = String(b.op || 'status');
        const on = adminPush.enabled(cfg);
        if (op === 'status') {
          return send(200, { ok: true, enabled: on, key: on ? cfg.vapid.publicKey : '', devices: await store.hlen(adminPush.KEY), maxPerHour: adminPush.MAX_PER_HOUR });
        }
        if (!on) return send(503, { error: 'push_unavailable', message: 'Faltam as chaves VAPID (VAPID_PUBLIC_KEY e VAPID_PRIVATE_KEY) na Vercel.' });
        if (op === 'sub') {
          const sub = validSubscription(b.sub);
          if (!sub) return send(400, { error: 'Inscrição de notificação inválida.' });
          const field = adminPush.fieldOf(sub.endpoint);
          if ((await store.hget(adminPush.KEY, field)) === undefined && (await store.hlen(adminPush.KEY)) >= adminPush.MAX_DEVICES) {
            const all = await store.hgetall(adminPush.KEY);
            const oldest = Object.entries(all).map(([f, j]) => { let t = 0; try { t = JSON.parse(j).t || 0; } catch (_) { /* ruim */ } return [f, t]; }).sort((x, y) => x[1] - y[1])[0];
            if (oldest) await store.hdel(adminPush.KEY, oldest[0]);
          }
          await store.hset(adminPush.KEY, field, JSON.stringify({ ...sub, t: now }));
          await log('push_on', 'admin');
          return send(200, { ok: true });
        }
        if (op === 'unsub') {
          const ep = String(b.endpoint || '');
          if (ep.length < 20 || ep.length > 600) return send(400, { error: 'Endereço inválido.' });
          await store.hdel(adminPush.KEY, adminPush.fieldOf(ep));
          await log('push_off', 'admin');
          return send(200, { ok: true });
        }
        if (op === 'test') {
          const hk = `adm:pt:${Math.floor(now / 3600000)}`;
          const t = await store.incr(hk, 3600);
          if (t.n > 5) return send(429, { error: 'Muitos testes. Tente mais tarde.' });
          const sent = await adminPush.broadcast(cfg, fetchImpl, cmd, { kind: 'admin', body: 'Teste: os avisos de bug grave estão funcionando.', tag: 'teste' }, now);
          return send(200, { ok: true, sent });
        }
        return send(400, { error: 'Operação desconhecida.' });
      }

      // ---------------- Presença: perfis com vínculo ligado e o app à frente ----------------
      if (action === 'presence') {
        const since = now - profiles.ONLINE_WINDOW;
        const [, online, recent, cnt] = await cmd.pipeline([
          ['ZREMRANGEBYSCORE', Z.on, '-inf', String(now - profiles.PRESENCE_KEEP)],
          ['ZREVRANGEBYSCORE', Z.on, '+inf', String(since), 'WITHSCORES', 'LIMIT', '0', '40'],
          ['ZREVRANGEBYSCORE', Z.on, String(since - 1), '-inf', 'WITHSCORES', 'LIMIT', '0', '15'],
          ['ZCOUNT', Z.on, String(since), '+inf'],
        ]);
        const rows = [...pairs(online), ...pairs(recent)];
        const infos = rows.length ? await cmd.pipeline(rows.map(([c]) => ['HMGET', U(String(c)), 'n', 'rt', 'rs'])) : [];
        const items = rows.map(([c, t], i) => {
          const [n, rt, rs] = infos[i] || [];
          return { code: String(c), name: n || '', last: t, online: t >= since, teacher: rt === '1', student: rs === '1' };
        });
        return send(200, { ok: true, now, windowMin: profiles.ONLINE_WINDOW / 60000, onlineCount: Number(cnt) || 0, items });
      }

      // ---------------- Suporte: encerrar um vínculo ----------------
      if (action === 'unlink') {
        if (needCode()) return;
        const other = String(b.other || '').toUpperCase();
        if (!CODE_RE.test(other) || other === code) return send(400, { error: 'Código do outro lado inválido.' });
        if (b.as !== 'teacher' && b.as !== 'student') return send(400, { error: 'Informe o papel (teacher ou student).' });
        const teacher = b.as === 'teacher' ? code : other, student = b.as === 'teacher' ? other : code;
        if ((await store.hget(U(code), 'h')) === undefined) return send(404, { error: 'Perfil não encontrado.' });
        if ((await store.hget(T(teacher), student)) === undefined) return send(404, { error: 'Esse vínculo não existe.' });
        const nameOf = async (c) => String((await store.hget(U(c), 'n')) || '') || c;
        const [tn, sn] = await Promise.all([nameOf(teacher), nameOf(student)]);
        await unlinkPair(store, cmd, teacher, student, now);
        await cmd.cmd(['HINCRBY', K.total, 'links', '-1']);
        await notify(teacher, 'unlink', sn);
        await notify(student, 'unlink', tn);
        await log('unlink', code, other);
        return send(200, { ok: true });
      }

      // ---------------- Suporte: agenda do perfil ----------------
      if (action === 'agenda') {
        if (needCode()) return;
        if ((await store.hget(U(code), 'h')) === undefined) return send(404, { error: 'Perfil não encontrado.' });
        const [made, avail, taken, mine, links] = await Promise.all([store.hgetall(SL(code)), store.hgetall(AV(code)), store.hgetall(TK(code)), store.hgetall(SS(code)), store.hgetall(T(code))]);
        const parse = (j) => { try { return JSON.parse(j); } catch (_) { return null; } };
        const names = Object.fromEntries(parseLinks(links).map((x) => [x.code, x.name]));
        const classes = Object.entries(made).map(([id, j]) => ({ id, j: parse(j) })).filter((x) => x.j)
          .map(({ id, j }) => ({ id, start: j.s || 0, mins: j.d || 0, weekly: !!j.w, canceled: !!j.c, student: j.sc || '', studentName: names[j.sc] || '', picked: !!j.pk }))
          .sort((a, b2) => a.start - b2.start).slice(0, 60);
        const free = Object.entries(avail).map(([id, j]) => ({ id, j: parse(j) })).filter((x) => x.j)
          .map(({ id, j }) => ({ id, start: j.s || 0, mins: j.d || 0, weekly: !!j.w }))
          .sort((a, b2) => a.start - b2.start).slice(0, 60);
        const received = Object.entries(mine).map(([f, j]) => ({ f, j: parse(j) })).filter((x) => x.j)
          .map(({ f, j }) => ({ id: f.slice(f.indexOf(':') + 1), teacher: f.slice(0, f.indexOf(':')), teacherName: j.tn || '', start: j.s || 0, mins: j.d || 0, weekly: !!j.w, canceled: !!j.c }))
          .sort((a, b2) => a.start - b2.start).slice(0, 60);
        return send(200, { ok: true, classes, free, received, locks: Object.keys(taken).length });
      }

      // ---------------- Suporte: apagar item de agenda travado ----------------
      if (action === 'agenda_del') {
        if (needCode()) return;
        const id = String(b.id || '');
        const kind = String(b.kind || '');
        if (!ID_RE.test(id) || !['class', 'avail', 'mine'].includes(kind)) return send(400, { error: 'Item inválido.' });
        if ((await store.hget(U(code), 'h')) === undefined) return send(404, { error: 'Perfil não encontrado.' });
        if (kind === 'avail') {
          if ((await store.hget(AV(code), id)) === undefined) return send(404, { error: 'Item não encontrado.' });
          await store.hdel(AV(code), id);
          await store.hdel(TK(code), id);
          await notify(code, 'agenda', 'um horário livre');
        } else {
          const teacher = kind === 'class' ? code : String(b.other || '').toUpperCase();
          if (!CODE_RE.test(teacher)) return send(400, { error: 'Falta o código do professor.' });
          const raw = await store.hget(SL(teacher), id);
          let student = kind === 'mine' ? code : '';
          if (kind === 'class' && raw !== undefined) { try { student = String(JSON.parse(raw).sc || ''); } catch (_) { /* ruim */ } }
          const mineRaw = student && CODE_RE.test(student) ? await store.hget(SS(student), `${teacher}:${id}`) : undefined;
          if (raw === undefined && mineRaw === undefined) return send(404, { error: 'Item não encontrado.' });
          await store.hdel(SL(teacher), id);
          if (student && CODE_RE.test(student)) {
            await store.hdel(SS(student), `${teacher}:${id}`);
            await store.hset(U(student), 'sr', String(now));
            await notify(student, 'agenda', 'uma aula marcada');
          }
          await store.hset(U(teacher), 'ar', String(now));
          await notify(teacher, 'agenda', 'uma aula marcada');
        }
        await log('agenda_del', code, `${kind}:${id}`);
        return send(200, { ok: true });
      }

      // ---------------- Suporte: código para liberar a conta em outro aparelho ----------------
      if (action === 'support_code') {
        if (needCode()) return;
        if ((await store.hget(U(code), 'h')) === undefined) return send(404, { error: 'Perfil não encontrado.' });
        const bytes = crypto.randomBytes(8);
        let plain = '';
        for (const x of bytes) plain += ALPHA[x % 32];
        const until = now + SUPPORT_TTL;
        await store.hset(U(code), 'sc', sha(`sup|${code}|${plain}`));
        await store.hset(U(code), 'sx', String(until));
        await log('support_code', code);
        return send(200, { ok: true, supportCode: `${plain.slice(0, 4)}-${plain.slice(4)}`, until });
      }
      if (action === 'support_cancel') {
        if (needCode()) return;
        await store.hdel(U(code), 'sc');
        await store.hdel(U(code), 'sx');
        await log('support_cancel', code);
        return send(200, { ok: true });
      }

      // ---------------- Bugs (relatórios de erro do app) ----------------
      if (action === 'bugs') {
        const days = [1, 7, 30, 90].includes(Number(b.days)) ? Number(b.days) : 7;
        const offset = Math.max(0, Math.min(1000, Math.round(Number(b.offset)) || 0));
        const f = {
          sev: ['critical', 'action', 'info'].includes(b.sev) ? b.sev : '',
          status: ['new', 'seen', 'resolved', 'ignored', 'reopened', 'open'].includes(b.status) ? b.status : '',
          ver: String(b.ver || '').replace(/[^A-Za-z0-9._-]/g, '').slice(0, 16),
          plat: String(b.plat || '').replace(/[^a-z0-9-]/g, '').slice(0, 24),
          code: String(b.code || '').toUpperCase().replace(/[^A-Z0-9-]/g, '').slice(0, 8),
          q: sanitize(b.q, 60).toLowerCase(),
          cur: b.cur === true || b.cur === '1',
        };
        const current = ((cfg.env || {}).VERCEL_GIT_COMMIT_SHA || '').slice(0, 7) || null;
        // Limpeza: bugs sem ocorrência há mais de 90 dias saem do Redis (poucos por consulta).
        const old = (await cmd.cmd(['ZRANGEBYSCORE', EK.idx, '-inf', String(now - 90 * DAY), 'LIMIT', '0', '10'])) || [];
        for (const ofp of old.map(String)) {
          await cmd.pipeline([['DEL', EK.bug(ofp), EK.devices(ofp), EK.trend(ofp), EK.recent(ofp)], ['ZREM', EK.idx, ofp], ['HDEL', EK.resolved, ofp], ['HDEL', EK.notes, ofp]]);
        }
        const today = errDay(now);
        const [fps, dayHash, opensToday] = await cmd.pipeline([
          ['ZREVRANGEBYSCORE', EK.idx, '+inf', String(now - days * DAY), 'LIMIT', '0', String(SCAN_BUGS)],
          ['HGETALL', EK.daily(today)],
          ['HGET', K.ct(today), 'open'],
        ]);
        const ids = (fps || []).map(String);
        const raws = ids.length ? await cmd.pipeline(ids.map((fp) => ['HGETALL', EK.bug(fp)])) : [];
        const rows = ids.map((fp, i) => {
          const h = {};
          for (let j = 0; j + 1 < (raws[i] || []).length; j += 2) h[raws[i][j]] = raws[i][j + 1];
          const count = (prefix) => Object.fromEntries(Object.keys(h).filter((k) => k.startsWith(prefix)).map((k) => [k.slice(prefix.length), Number(h[k]) || 0]));
          return {
            fp, code: h.c || '', sev: h.s || 'action', where: h.w || '', msg: h.msg || '', status: h.st || 'new',
            n: Number(h.n) || 0, first: Number(h.first) || 0, last: Number(h.last) || 0,
            versions: count('v:'), platforms: count('p:'), installs: count('i:'),
          };
        }).map((r) => ({ ...r, onCurrent: current ? !!r.versions[current] : null }));
        const match = rows.filter((r) =>
          (!f.sev || r.sev === f.sev) &&
          (!f.status || (f.status === 'open' ? ['new', 'seen', 'reopened'].includes(r.status) : r.status === f.status)) &&
          (!f.cur || !current || r.onCurrent) && (!f.ver || r.versions[f.ver]) && (!f.plat || r.platforms[f.plat]) && (!f.code || r.code === f.code) &&
          (!f.q || (r.where + ' ' + r.msg + ' ' + r.code).toLowerCase().includes(f.q)));
        const page = match.slice(offset, offset + BUG_PAGE);
        const extra = page.length ? await cmd.pipeline(page.flatMap((r) => [['PFCOUNT', EK.devices(r.fp)], ['HGETALL', EK.trend(r.fp)]])) : [];
        const dayKeys = [];
        for (let i = 13; i >= 0; i--) dayKeys.push(errDay(now - i * DAY));
        const items = page.map((r, i) => {
          const t = {};
          const flat = extra[i * 2 + 1] || [];
          for (let j = 0; j + 1 < flat.length; j += 2) t[flat[j]] = Number(flat[j + 1]) || 0;
          return { ...r, devices: Number(extra[i * 2]) || 0, trend: dayKeys.map((d2) => t[d2] || 0) };
        });
        const dh = {};
        for (let j = 0; j + 1 < (dayHash || []).length; j += 2) dh[dayHash[j]] = Number(dayHash[j + 1]) || 0;
        const hours = Array.from({ length: 24 }, (_, i) => dh['h' + String(i).padStart(2, '0')] || 0);
        const open = rows.filter((r) => ['new', 'seen', 'reopened'].includes(r.status));
        return send(200, {
          ok: true, current, days, offset, page: BUG_PAGE, gc: old.length, total: match.length, scanned: ids.length, scanLimit: SCAN_BUGS,
          items,
          filters: {
            versions: [...new Set(rows.flatMap((r) => Object.keys(r.versions)))].sort(),
            platforms: [...new Set(rows.flatMap((r) => Object.keys(r.platforms)))].sort(),
            codes: [...new Set(rows.map((r) => r.code).filter(Boolean))].sort(),
          },
          summary: {
            open: open.length,
            newToday: rows.filter((r) => r.first && errDay(r.first) === today).length,
            criticalOpen: open.filter((r) => r.sev === 'critical').length,
            reopened: rows.filter((r) => r.status === 'reopened').length,
            today: { total: dh.total || 0, critical: dh.critical || 0, action: dh.action || 0, info: dh.info || 0 },
            last2h: [0, 1].reduce((a, k) => a + (hours[(Number(errHour(now)) - k + 24) % 24] || 0), 0),
            opensToday: Number(opensToday) || 0,
            hours,
          },
        });
      }

      // ---------------- Saúde (semáforo do painel) ----------------
      if (action === 'health') {
        const dayKeys = [];
        for (let i = 13; i >= 0; i--) dayKeys.push(errDay(now - i * DAY));
        const [opensRaw, ...hashes] = await cmd.pipeline([['HGET', K.ct(errDay(now)), 'open'], ...dayKeys.map((d2) => ['HGETALL', EK.daily(d2)])]);
        const parse = (flat) => { const o = {}; for (let j = 0; j + 1 < (flat || []).length; j += 2) o[flat[j]] = Number(flat[j + 1]) || 0; return o; };
        const days = hashes.map(parse);
        const today = days[days.length - 1];
        const opens = Number(opensRaw) || 0;
        const hoursNow = Number(errHour(now));
        const last2h = (today['h' + String(hoursNow).padStart(2, '0')] || 0) + (today['h' + String((hoursNow + 23) % 24).padStart(2, '0')] || 0);
        let clean = 0;
        for (let i = days.length - 2; i >= 0 && !days[i].critical; i--) clean++; // dias seguidos sem erro grave (até ontem)
        const per100 = opens >= 20 ? Math.round((((today.total || 0) / opens) * 100) * 10) / 10 : null;
        const reasons = [];
        let level = 'green';
        if ((today.critical || 0) > 0) { level = 'red'; reasons.push('Erro grave hoje'); }
        if (last2h >= 5 && last2h > ((today.total || 0) / 24) * 4) { level = 'red'; reasons.push('Pico de erros nas últimas 2 horas'); }
        if (level !== 'red') {
          if (per100 !== null && per100 > 5) { level = 'yellow'; reasons.push('Muitos erros por abertura'); }
          if ((today.srv || 0) > 0) { level = 'yellow'; reasons.push('Falha no servidor hoje'); }
        }
        return send(200, {
          ok: true, level, reasons, errorsToday: today.total || 0, criticalToday: today.critical || 0, serverToday: today.srv || 0,
          opensToday: opens, per100, last2h, cleanDays: clean, cleanCapped: clean >= days.length - 1,
        });
      }

      // ---------------- Sistema: banco, servidor, variáveis e limites ----------------
      // Custo: 3 comandos de teste + 14 leituras de erros (só quando o admin abre a aba Sistema).
      if (action === 'system') {
        const t0 = process.hrtime.bigint();
        let pong = null;
        try { pong = await cmd.cmd(['PING']); } catch (_) { pong = null; }
        const ms = Math.round(Number(process.hrtime.bigint() - t0) / 1e5) / 10;
        let keys = null;
        const info = {};
        try { const n = Number(await cmd.cmd(['DBSIZE'])); keys = Number.isFinite(n) ? n : null; } catch (_) { /* sem DBSIZE */ }
        try {
          const raw = await cmd.cmd(['INFO']);
          if (typeof raw === 'string') {
            for (const line of raw.split(/\r?\n/)) {
              const mm = /^(used_memory|maxmemory|total_commands_processed|uptime_in_seconds):(\d+)/.exec(line);
              if (mm) info[mm[1]] = Number(mm[2]);
            }
          }
        } catch (_) { /* o plano pode não expor INFO */ }
        const dk = [];
        for (let i = 13; i >= 0; i--) dk.push(errDay(now - i * DAY));
        let srv = [];
        try {
          const hs = await cmd.pipeline(dk.map((d2) => ['HGETALL', EK.daily(d2)]));
          srv = hs.map((flat, i) => { let n = 0, tot = 0; for (let j = 0; j + 1 < (flat || []).length; j += 2) { if (flat[j] === 'srv') n = Number(flat[j + 1]) || 0; if (flat[j] === 'total') tot = Number(flat[j + 1]) || 0; } return { day: dk[i], srv: n, total: tot }; });
        } catch (_) { srv = []; }
        let fnCount = null;
        try {
          fnCount = require('node:fs').readdirSync(__dirname).filter((f) => f.endsWith('.js') && !f.endsWith('.test.js')).length;
        } catch (_) { fnCount = null; }
        const env = cfg.env || {};
        const providers = Object.keys(cfg.keys || {});
        const checks = [
          { id: 'admin', label: 'Chave do painel', ok: !!cfg.adminKey, required: true, hint: 'ADMIN_KEY', warn: !env.ADMIN_KEY && env.FEEDBACK_ADMIN_KEY ? 'Usando a chave do feedback (FEEDBACK_ADMIN_KEY). Defina uma ADMIN_KEY própria na Vercel.' : '' },
          { id: 'redis', label: 'Banco de dados (Redis)', ok: !!(cfg.redisUrl && cfg.redisToken), required: true, hint: 'UPSTASH_REDIS_REST_URL e UPSTASH_REDIS_REST_TOKEN' },
          { id: 'qstash', label: 'Lembretes agendados (QStash)', ok: !!(cfg.qstash && cfg.qstash.token && cfg.qstash.currentKey && cfg.qstash.nextKey), required: false, hint: 'QSTASH_TOKEN, QSTASH_CURRENT_SIGNING_KEY e QSTASH_NEXT_SIGNING_KEY' },
          { id: 'vapid', label: 'Notificações no celular (VAPID)', ok: !!(cfg.vapid && cfg.vapid.publicKey && cfg.vapid.privateKey), required: false, hint: 'VAPID_PUBLIC_KEY e VAPID_PRIVATE_KEY' },
          { id: 'ai', label: 'Inteligência artificial', ok: providers.length > 0, required: false, hint: 'ao menos uma chave: GEMINI_API_KEY, OPENAI_API_KEY, ANTHROPIC_API_KEY…' },
          { id: 'errors', label: 'Relatórios de erro ligados', ok: cfg.errorsEnabled !== false, required: false, hint: 'ERRORS_DISABLED não pode ser 1' },
        ];
        const ai = Object.keys(cfg.rpm || {}).map((id) => ({ id, label: (require('./_lib/config').LABELS || {})[id] || id, on: providers.includes(id), rpm: cfg.rpm[id] }));
        return send(200, {
          ok: true, now,
          db: { ok: pong === 'PONG', ms, keys, usedMemory: info.used_memory ?? null, maxMemory: info.maxmemory ?? null, commandsProcessed: info.total_commands_processed ?? null, memoryMode: !(cfg.redisUrl && cfg.redisToken) },
          server: {
            functions: { used: fnCount, max: 12 },
            node: process.version,
            region: env.VERCEL_REGION || null,
            env: env.VERCEL_ENV || null,
            commit: env.VERCEL_GIT_COMMIT_SHA ? String(env.VERCEL_GIT_COMMIT_SHA).slice(0, 7) : null,
            serverErrors: srv,
          },
          checks, ai,
          limits: { redisMonth: BUDGET, functions: 12, qstashDay: 500, errorsDay: cfg.errorsDailyCap },
        });
      }

      // ---------------- Custos (estimativa de comandos do Redis) ----------------
      if (action === 'costs') {
        const dayKeys = [];
        for (let i = 29; i >= 0; i--) dayKeys.push(errDay(now - i * DAY));
        const res = await cmd.pipeline([...dayKeys.map((d2) => ['HGETALL', K.ct(d2)]), ...dayKeys.map((d2) => ['HGETALL', EK.daily(d2)]), ...dayKeys.map((d2) => ['PFCOUNT', K.day(d2)])]);
        const parse = (flat) => { const o = {}; for (let j = 0; j + 1 < (flat || []).length; j += 2) o[flat[j]] = Number(flat[j + 1]) || 0; return o; };
        const kinds = {};
        const daysOut = dayKeys.map((d2, i) => {
          const ct = parse(res[i]);
          const er = parse(res[30 + i]);
          const users = Number(res[60 + i]) || 0;
          const parts = {
            'Aberturas': (ct.open || 0) * COST.open + (ct.new || 0) * COST.new,
            'Consultas de vínculo': (ct.rev10 || 0) * 10 * COST.rev,
            'Aulas enviadas': (ct.lesson || 0) * COST.lesson,
            'Aulas marcadas': (ct.slot || 0) * COST.slot,
            'Lembretes': (ct.remind || 0) * COST.remind,
            'Vínculos': (ct.link || 0) * COST.link,
            'Tarefas validadas': (ct.verdict || 0) * COST.verdict,
            'Horários pegos': (ct.pick || 0) * COST.pick,
            'Relatórios de erro': (er.total || 0) * COST.error,
            'Batidas (online agora)': users * COST.beatsPerUser,
          };
          let total = 0;
          for (const [k2, v] of Object.entries(parts)) { kinds[k2] = (kinds[k2] || 0) + v; total += v; }
          return { day: d2, total };
        });
        const month = daysOut.reduce((a, x) => a + x.total, 0);
        const last7 = daysOut.slice(-7).reduce((a, x) => a + x.total, 0);
        return send(200, {
          ok: true, budget: BUDGET, month, pct: Math.round((month / BUDGET) * 1000) / 10,
          projection: Math.round((last7 / 7) * 30), perDay: daysOut,
          kinds: Object.entries(kinds).map(([name, n]) => ({ name, n })).sort((a, b) => b.n - a.n),
          note: 'Estimativa: contadores do app × custo por ação (ver docs/CUSTOS_E_REGRESSAO.md). A consulta de vínculo é amostrada (1 em 10).',
        });
      }

      if (action === 'bug') {
        const fp = String(b.fp || '');
        if (!FP_RE.test(fp)) return send(400, { error: 'Bug inválido.' });
        const [raw, devices, recent, trend, note, resolved] = await cmd.pipeline([
          ['HGETALL', EK.bug(fp)], ['PFCOUNT', EK.devices(fp)], ['LRANGE', EK.recent(fp), '0', '9'],
          ['HGETALL', EK.trend(fp)], ['HGET', EK.notes, fp], ['HGET', EK.resolved, fp],
        ]);
        const h = {};
        for (let j = 0; j + 1 < (raw || []).length; j += 2) h[raw[j]] = raw[j + 1];
        if (!h.c) return send(404, { error: 'Bug não encontrado.' });
        const count = (prefix) => Object.fromEntries(Object.keys(h).filter((k) => k.startsWith(prefix)).map((k) => [k.slice(prefix.length), Number(h[k]) || 0]));
        const t = {};
        for (let j = 0; j + 1 < (trend || []).length; j += 2) t[trend[j]] = Number(trend[j + 1]) || 0;
        const dayKeys = [];
        for (let i = 29; i >= 0; i--) dayKeys.push(errDay(now - i * DAY));
        const occurrences = [];
        for (const x of recent || []) { try { occurrences.push(JSON.parse(x)); } catch (_) { /* ruim */ } }
        let res = null;
        try { res = resolved ? JSON.parse(resolved) : null; } catch (_) { /* ruim */ }
        return send(200, {
          ok: true, fp, code: h.c, sev: h.s || 'action', where: h.w || '', msg: h.msg || '', status: h.st || 'new',
          n: Number(h.n) || 0, first: Number(h.first) || 0, last: Number(h.last) || 0, devices: Number(devices) || 0,
          versions: count('v:'), platforms: count('p:'), installs: count('i:'),
          trend: dayKeys.map((d2) => ({ day: d2, n: t[d2] || 0 })),
          occurrences, note: note || '', resolved: res,
        });
      }

      if (action === 'bug_status') {
        const fp = String(b.fp || '');
        const status = String(b.status || '');
        if (!FP_RE.test(fp)) return send(400, { error: 'Bug inválido.' });
        if (!['new', 'seen', 'resolved', 'ignored'].includes(status)) return send(400, { error: 'Status inválido.' });
        if ((await cmd.cmd(['HGET', EK.bug(fp), 'c'])) == null) return send(404, { error: 'Bug não encontrado.' });
        const list = [['HSET', EK.bug(fp), 'st', status]];
        if (status === 'resolved') list.push(['HSET', EK.resolved, fp, JSON.stringify({ at: now })]);
        else list.push(['HDEL', EK.resolved, fp]);
        if (b.note !== undefined) {
          const note = sanitize(b.note, 300);
          list.push(note ? ['HSET', EK.notes, fp, note] : ['HDEL', EK.notes, fp]);
        }
        await cmd.pipeline(list);
        await log('bug_' + status, fp);
        return send(200, { ok: true, status });
      }

      if (action === 'log') {
        const l = await cmd.cmd(['LRANGE', LOG, '0', '49']);
        const items = [];
        for (const x of l || []) { try { items.push(JSON.parse(x)); } catch (_) { /* ruim */ } }
        return send(200, { ok: true, items });
      }

      return send(400, { error: 'Ação desconhecida.' });
    } catch (e) {
      if (String(e.message) === 'no-redis') return send(503, { error: 'sync_unavailable' });
      console.error('admin error', e && e.message);
      await serverError({ cfg, fetchImpl, clock, allowMemory: !!deps.allowMemory }, 'admin', e);
      return send(500, { error: 'Erro no painel.' });
    }
  };
}

module.exports = makeHandler();
module.exports.makeHandler = makeHandler;
