// /api/stats: métricas ANÔNIMAS de uso do app.
//
//  POST (o app, sem chave): { t: 'open'|'beat', id, d?: { pl, in, v }, tabs?: [...] }
//        id = código aleatório do aparelho (NÃO é o código de professor/aluno). Nada de IP,
//        nome, áudio ou o que a pessoa toca é guardado.
//  GET  (só o admin, com "Authorization: Bearer <chave>"): ?part=live (online agora) ou ?part=full.
//
// Custo no Redis por aparelho por dia: ~10 comandos ao abrir (4 quando já abriu hoje) e 1 por
// batida (a cada ~5 min, só com o app à frente). Nenhum comando lê listas grandes.
'use strict';

const crypto = require('node:crypto');
const { config } = require('./_lib/config');
const { createCmd } = require('./_lib/store_cmd');
const { K, TABS, dayKey } = require('./_lib/metrics');
const { serverError } = require('./_lib/error_store');

const sha = (s) => crypto.createHash('sha256').update(String(s)).digest('hex');
const ONLINE_WINDOW = 5 * 60 * 1000;
const STALE = 15 * 60 * 1000; // quem não bate há 15 min sai do conjunto "online"
const ID_RE = /^[a-z0-9]{16,40}$/;
const OPENS_PER_HOUR = 200; // por origem (muita gente atrás do mesmo IP é comum)

const hourBr = (ms) => new Date(ms - 3 * 3600 * 1000).toISOString().slice(11, 13);
const clip = (v, re) => (typeof v === 'string' && re.test(v) ? v : '');

function clientIp(req) {
  const xf = String((req.headers && req.headers['x-forwarded-for']) || '').split(',')[0].trim();
  return xf || (req.socket && req.socket.remoteAddress) || 'ip';
}

function makeHandler(deps = {}) {
  const fetchImpl = deps.fetch || globalThis.fetch;
  const getCfg = deps.config || (() => config());
  const clock = deps.now || Date.now;
  const rnd = deps.random || Math.random;
  return async function handler(req, res) {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('X-Robots-Tag', 'noindex');
    const send = (code, obj) => { res.statusCode = code; res.end(JSON.stringify(obj)); };

    const cfg = getCfg();
    const m = createCmd(cfg, fetchImpl, { allowMemory: !!deps.allowMemory });
    if (!m.durable) return send(503, { error: 'sync_unavailable' });
    const now = clock();
    const today = dayKey(now);

    try {
      // ---------------- Admin: ler ----------------
      if (req.method === 'GET') {
        const adminKey = cfg.adminKey;
        if (!adminKey) return send(404, { error: 'Painel não configurado (falta a chave de admin).' });
        const ip = sha(clientIp(req)).slice(0, 16);
        const [bad] = await m.pipeline([['INCR', `st:bad:${ip}:${Math.floor(now / 3600000)}`], ['EXPIRE', `st:bad:${ip}:${Math.floor(now / 3600000)}`, '3600', 'NX']]);
        // Só conta tentativa errada contra o limite (a certa não gasta a cota).
        const given = String((req.headers && (req.headers.authorization || req.headers.Authorization)) || '').replace(/^Bearer\s+/i, '');
        const ok = crypto.timingSafeEqual(Buffer.from(sha(given)), Buffer.from(sha(adminKey)));
        if (!ok) {
          if (Number(bad) > 10) return send(429, { error: 'Muitas tentativas. Tente mais tarde.' });
          return send(401, { error: 'Chave inválida.' });
        }
        const part = String((req.query && req.query.part) || (new URL(req.url || '/', 'http://x').searchParams.get('part')) || 'full');
        const [, on5, on1] = await m.pipeline([
          ['ZREMRANGEBYSCORE', K.online, '-inf', String(now - STALE)],
          ['ZCOUNT', K.online, String(now - ONLINE_WINDOW), '+inf'],
          ['ZCOUNT', K.online, String(now - 60 * 1000), '+inf'],
        ]);
        if (part === 'live') return send(200, { ok: true, now, online5: Number(on5) || 0, online1: Number(on1) || 0 });

        const days = [];
        for (let i = 29; i >= 0; i--) days.push(dayKey(now - i * 86400000));
        const cmds = [];
        for (const d of days) { cmds.push(['PFCOUNT', K.day(d)]); cmds.push(['HGETALL', K.ct(d)]); }
        cmds.push(['PFCOUNT', ...days.slice(-7).map(K.day)]);
        cmds.push(['PFCOUNT', ...days.map(K.day)]);
        cmds.push(['PFCOUNT', K.all]);
        // Período anterior (mesma duração) para comparar: 7 dias antes dos últimos 7 e 30 antes dos últimos 30.
        const prevDays = [];
        for (let i = 59; i >= 30; i--) prevDays.push(dayKey(now - i * 86400000)); // dias -59..-30
        cmds.push(['PFCOUNT', ...days.slice(-14, -7).map(K.day)]);
        cmds.push(['PFCOUNT', ...prevDays.map(K.day)]);
        cmds.push(['HGETALL', K.total]);
        cmds.push(['HGETALL', K.dim(today)]);
        for (const t of TABS) cmds.push(['PFCOUNT', K.tab(today, t)]);
        const r = await m.pipeline(cmds);

        const hash = (flat) => {
          const o = {};
          for (let i = 0; i + 1 < (flat || []).length; i += 2) o[flat[i]] = Number(flat[i + 1]) || 0;
          return o;
        };
        const series = days.map((d, i) => {
          const ct = hash(r[i * 2 + 1]);
          return { day: d, hours: Array.from({ length: 24 }, (_, hh) => ct['h' + String(hh).padStart(2, '0')] || 0), verdicts: ct.verdict || 0, picks: ct.pick || 0, users: Number(r[i * 2]) || 0, opens: ct.open || 0, news: ct.new || 0, lessons: ct.lesson || 0, slots: ct.slot || 0, reminders: ct.remind || 0, links: ct.link || 0 };
        });
        let k = days.length * 2;
        const wau = Number(r[k++]) || 0;
        const mau = Number(r[k++]) || 0;
        const total = Number(r[k++]) || 0;
        const wauPrev = Number(r[k++]) || 0;
        const mauPrev = Number(r[k++]) || 0;
        const totals = hash(r[k++]);
        const dimRaw = hash(r[k++]);
        const dims = { pl: {}, in: {}, v: {}, o: {} };
        for (const [f, n] of Object.entries(dimRaw)) {
          const [kind, ...rest] = f.split(':');
          if (dims[kind]) dims[kind][rest.join(':')] = n;
        }
        const tabs = {};
        for (const t of TABS) tabs[t] = Number(r[k++]) || 0;
        return send(200, {
          ok: true, now, today, online5: Number(on5) || 0, online1: Number(on1) || 0,
          total, wau, mau, wauPrev, mauPrev, series, dims, tabs, totals, generatedAt: now,
        });
      }

      // ---------------- App: gravar ----------------
      if (req.method !== 'POST') return send(405, { error: 'Use POST.' });
      let b = req.body;
      if (typeof b === 'string') { try { b = JSON.parse(b); } catch (_) { b = null; } }
      if (!b || typeof b !== 'object' || JSON.stringify(b).length > 1024) return send(400, { error: 'Corpo inválido.' });
      const id = String(b.id || '');
      if (!ID_RE.test(id)) return send(400, { error: 'Identificador inválido.' });
      const kind = b.t === 'open' ? 'open' : b.t === 'beat' ? 'beat' : '';
      if (!kind) return send(400, { error: 'Evento inválido.' });

      if (kind === 'beat') {
        // XX: só atualiza quem já abriu (batida solta não cria aparelho "online" do nada).
        const list = [['ZADD', K.online, 'XX', String(now), id]];
        for (const t of (Array.isArray(b.tabs) ? b.tabs : []).slice(0, TABS.length)) {
          if (TABS.includes(t)) list.push(['PFADD', K.tab(today, t), id]);
        }
        if (rnd() < 0.02) list.push(['ZREMRANGEBYSCORE', K.online, '-inf', String(now - STALE)]);
        await m.pipeline(list);
        return send(200, { ok: true });
      }

      // open: limite por origem (barato, só uma vez por sessão).
      const ip = sha(clientIp(req)).slice(0, 16);
      const hk = `st:open:${ip}:${Math.floor(now / 3600000)}`;
      const [n] = await m.pipeline([['INCR', hk], ['EXPIRE', hk, '3600', 'NX']]);
      if (Number(n) > OPENS_PER_HOUR) return send(429, { error: 'Muitos acessos desta origem.' });

      const list = [
        ['PFADD', K.all, id], // 1 = aparelho novo
        ['PFADD', K.day(today), id],
        ['HINCRBY', K.ct(today), 'open', '1'],
        ['HINCRBY', K.ct(today), 'h' + hourBr(now), '1'], // aberturas por hora (mapa de calor)
        ['ZADD', K.online, String(now), id],
      ];
      const d = b.d && typeof b.d === 'object' ? b.d : null;
      if (d) {
        const pl = clip(d.pl, /^[a-z0-9-]{1,24}$/);
        const inst = ['app', 'pwa', 'browser'].includes(d.in) ? d.in : '';
        const v = clip(d.v, /^[A-Za-z0-9._-]{1,16}$/);
        const o = clip(d.o, /^[a-z0-9]{1,8}$/); // origem do link (?o=yt, ?o=ig…)
        if (pl) list.push(['HINCRBY', K.dim(today), `pl:${pl}`, '1']);
        if (inst) list.push(['HINCRBY', K.dim(today), `in:${inst}`, '1']);
        if (v) list.push(['HINCRBY', K.dim(today), `v:${v}`, '1']);
        if (o) list.push(['HINCRBY', K.dim(today), `o:${o}`, '1']);
      }
      for (const t of (Array.isArray(b.tabs) ? b.tabs : []).slice(0, TABS.length)) {
        if (TABS.includes(t)) list.push(['PFADD', K.tab(today, t), id]);
      }
      const out = await m.pipeline(list);
      if (Number(out[0]) === 1) await m.cmd(['HINCRBY', K.ct(today), 'new', '1']); // aparelho novo
      return send(200, { ok: true });
    } catch (e) {
      if (String(e.message) === 'no-redis') return send(503, { error: 'sync_unavailable' });
      console.error('stats error', e && e.message);
      await serverError({ cfg, fetchImpl, clock, allowMemory: !!deps.allowMemory }, 'stats', e);
      return send(200, { ok: false }); // métrica nunca atrapalha o app
    }
  };
}

module.exports = makeHandler();
module.exports.makeHandler = makeHandler;
