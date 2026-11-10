// /api/admin: painel do administrador (indicadores e gestão de perfis anônimos).
//
//  POST { action, ... } com "Authorization: Bearer <chave de admin>". Ações:
//   kpis                       indicadores (total, ativos x inativos, professores, crescimento, retenção)
//   list {offset?, q?}         perfis, do mais recente ao mais antigo (busca por trecho do código)
//   detail {code}              um perfil: papel, vínculos, volume de dados (NUNCA o segredo)
//   block / unblock {code}     impede / libera o vínculo online do perfil
//   delete {code, confirm}     apaga os dados e vínculos do perfil (confirm tem que ser o código)
//   log                        últimas ações do administrador
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

const { Z } = profiles;
const sha = (s) => crypto.createHash('sha256').update(String(s)).digest('hex');
const DAY = 86400000;
const PAGE = 25;
const SEARCH_SCAN = 500; // a busca olha os 500 perfis mais recentes (1 comando)
const COHORT = 300; // amostra máxima para a retenção
const U = (c) => `u:${c}`, T = (c) => `ut:${c}`, S = (c) => `us:${c}`, SL = (c) => `sl:${c}`, SS = (c) => `ss:${c}`;
const UL = (c) => `ul:${c}`, DN = (c) => `dn:${c}`, VD = (c) => `vd:${c}`, AV = (c) => `av:${c}`, TK = (c) => `tk:${c}`, PS = (c) => `ps:${c}`;
const CODE_RE = /^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}-[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}$/;
const LOG = 'adm:log';

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
    out.push({ code, name: n });
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
      const log = (a, c) => cmd.pipeline([['LPUSH', LOG, JSON.stringify({ t: now, a, c })], ['LTRIM', LOG, '0', '199']]);

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
          retention,
        });
      }

      // ---------------- Lista ----------------
      if (action === 'list') {
        const offset = Math.max(0, Math.min(100000, Math.round(Number(b.offset)) || 0));
        const q = String(b.q || '').toUpperCase().replace(/[^A-Z0-9-]/g, '').slice(0, 9);
        let rows; // [[code, la]]
        let total = null;
        if (q) {
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
        return send(200, { ok: true, items, total, offset, page: PAGE, scanned: q ? SEARCH_SCAN : null });
      }

      // ---------------- Detalhe ----------------
      if (action === 'detail') {
        if (needCode()) return;
        const prof = await store.hgetall(U(code));
        if (!prof.h) return send(404, { error: 'Perfil não encontrado.' });
        const [students, teachers] = await Promise.all([store.hgetall(T(code)), store.hgetall(S(code))]);
        const counts = await cmd.pipeline([SL, SS, UL, DN, VD, AV, TK, PS].map((f) => ['HLEN', f(code)]));
        const [classesMade, classesIn, lessonsIn, doneMarks, verdicts, openSlots, taken, devices] = counts.map((x) => Number(x) || 0);
        return send(200, {
          ok: true,
          profile: { code, name: prof.n || '', created: Number(prof.ca) || 0, last: Number(prof.la) || 0, blocked: prof.bl === '1' },
          students: parseLinks(students),
          teachers: parseLinks(teachers),
          data: { classesMade, classesIn, lessonsIn, doneMarks, verdicts, openSlots, taken, pushDevices: devices },
        });
      }

      // ---------------- Bloquear / liberar ----------------
      if (action === 'block' || action === 'unblock') {
        if (needCode()) return;
        if ((await store.hget(U(code), 'h')) === undefined) return send(404, { error: 'Perfil não encontrado.' });
        await store.hset(U(code), 'bl', action === 'block' ? '1' : '0');
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
        for (const key of [T, S, SL, SS, UL, DN, VD, AV, TK, PS, U]) {
          for (const f of Object.keys(await store.hgetall(key(code)))) await store.hdel(key(code), f);
        }
        await profiles.forget(cmd, code);
        await cmd.cmd(['HINCRBY', K.total, 'profiles', '-1']);
        await log('delete', code);
        return send(200, { ok: true });
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
      return send(500, { error: 'Erro no painel.' });
    }
  };
}

module.exports = makeHandler();
module.exports.makeHandler = makeHandler;
