// Índice dos perfis anônimos (código + apelido) para o painel do administrador: quando entrou,
// última atividade, papel (professor / aluno) e bloqueio. NÃO há cadastro nem login.
//
// Custo: 3 comandos quando o perfil nasce; depois, no máximo 1 gravação a cada 6 h por perfil
// ativo (a leitura do perfil já acontece em toda chamada, então checar é de graça).
// Falhar aqui nunca pode derrubar o que o usuário estava fazendo.
'use strict';

const { dayKey } = require('./metrics');

const Z = {
  last: 'pf:last', // código -> última atividade (ms)
  born: 'pf:new', // código -> quando entrou (ms)
  teach: 'pf:t', // código -> última atividade, só quem tem alunos
  stud: 'pf:s', // código -> última atividade, só quem tem professor
  on: 'pf:on', // código -> último sinal de vida (presença), de 10 em 10 minutos
  hot: 'pf:hot', // origem+dia -> quando passou de 30 perfis novos (aviso no painel)
};
const TOUCH_EVERY = 6 * 3600 * 1000;
const PRESENCE_EVERY = 10 * 60 * 1000; // no máximo 1 gravação de presença a cada 10 min por perfil
const ONLINE_WINDOW = 12 * 60 * 1000; // "online" = sinal nos últimos 12 min
const PRESENCE_KEEP = 2 * 24 * 3600 * 1000; // quem some há 2 dias sai do índice
const U = (code) => `u:${code}`;

/** Perfil acabou de nascer. */
async function created(cmd, code, now) {
  try {
    await cmd.pipeline([
      ['HSET', U(code), 'ca', String(now)],
      ['HSET', U(code), 'la', String(now)],
      ['ZADD', Z.born, String(now), code],
      ['ZADD', Z.last, String(now), code],
    ]);
  } catch (_) { /* índice não derruba nada */ }
}

/** Registra atividade (no máximo a cada 6 h). Devolve true se gravou. */
async function touch(cmd, prof, code, now) {
  const la = Number(prof.la) || 0;
  if (la && now - la < TOUCH_EVERY) return false;
  try {
    const list = [['HSET', U(code), 'la', String(now)], ['ZADD', Z.last, String(now), code]];
    if (!prof.ca) { // perfil antigo (de antes do índice): conta como visto pela primeira vez agora
      list.push(['HSET', U(code), 'ca', String(now)], ['ZADD', Z.born, String(now), code]);
    }
    if (prof.rt === '1') list.push(['ZADD', Z.teach, String(now), code]);
    if (prof.rs === '1') list.push(['ZADD', Z.stud, String(now), code]);
    await cmd.pipeline(list);
    return true;
  } catch (_) { return false; }
}

/**
 * Sinal de vida: o app à frente com o vínculo ligado consulta o servidor a cada ~30 s; aqui isso vira
 * "visto agora" com no máximo 1 gravação (2 comandos) a cada 10 min por perfil. A leitura do perfil já
 * acontece em toda chamada, então checar é de graça.
 *
 * Na MESMA gravação (um HSET com vários campos, sem comando a mais) entram:
 *  - tempo de uso estimado: minutos e sessões dos últimos 14 dias (campos uh, tm, ns);
 *  - ficha do aparelho (campo dv, em JSON curto) quando mudou ou passou 1 dia (no máximo 1 gravação por dia).
 * Só categorias curtas e o que o navegador já envia; nunca IP, áudio, nome do aparelho ou o que a pessoa toca.
 */
const SESSION_GAP = 12 * 60 * 1000; // sinal em até 12 min do anterior = mesma sessão
const HIST_DAYS = 14;
const DV_KEYS = ['pl', 'in', 'v', 'os', 'sc', 'lg', 'th', 'tc', 'mic', 'nt', 'tz', 'mem', 'cpu', 'net', 'dpr'];
const DV_SERVER = ['br', 'ou', 'mob', 'g']; // o que o servidor deduz sozinho (navegador, sistema, celular, região)
const DV_STABLE = ['pl', 'in', 'v', 'os', 'sc', 'lg', 'th', 'tc', 'tz', 'mem', 'cpu', 'dpr', 'br', 'ou', 'g']; // mudou isto = aparelho/versão mudou
const DV_RE = /^[A-Za-z0-9._-]{1,16}$/;

/** Histórico "AAAA-MM-DD:min:sessões;..." em mapa. */
function parseHist(s) {
  const m = new Map();
  for (const p of String(s || '').split(';')) {
    const [d, mi, se] = p.split(':');
    if (/^\d{4}-\d\d-\d\d$/.test(d || '')) m.set(d, [Number(mi) || 0, Number(se) || 0]);
  }
  return m;
}

/** Soma o tempo desta batida ao histórico. Devolve os campos novos do perfil (uh, tm, ns). */
function usageUpdate(prof, now) {
  const pa = Number(prof.pa) || 0;
  const gap = pa ? now - pa : Infinity;
  const same = gap <= SESSION_GAP;
  const credit = same ? Math.max(1, Math.min(12, Math.round(gap / 60000))) : 1; // sessão nova vale ao menos 1 min
  const day = dayKey(now);
  const h = parseHist(prof.uh);
  const cur = h.get(day) || [0, 0];
  cur[0] += credit;
  if (!same) cur[1] += 1;
  h.set(day, cur);
  const keys = [...h.keys()].sort().slice(-HIST_DAYS);
  return {
    uh: keys.map((k) => k + ':' + h.get(k)[0] + ':' + h.get(k)[1]).join(';'),
    tm: String((Number(prof.tm) || 0) + credit),
    ns: String((Number(prof.ns) || 0) + (same ? 0 : 1)),
  };
}

/** Navegador, sistema e se é celular, lidos do User-Agent (só famílias e versão principal). */
function uaInfo(ua) {
  const s = String(ua || '').slice(0, 300);
  let br = '', m;
  if ((m = /EdgA?\/(\d+)|EdgiOS\/(\d+)|Edg\/(\d+)/.exec(s))) br = 'edge' + (m[1] || m[2] || m[3]);
  else if ((m = /SamsungBrowser\/(\d+)/.exec(s))) br = 'samsung' + m[1];
  else if ((m = /(?:Firefox|FxiOS)\/(\d+)/.exec(s))) br = 'firefox' + m[1];
  else if ((m = /(?:Chrome|CriOS)\/(\d+)/.exec(s))) br = 'chrome' + m[1];
  else if ((m = /Version\/(\d+)[^]*Safari/.exec(s))) br = 'safari' + m[1];
  let ou = '';
  if (/iPhone|iPad|iPod/.test(s)) ou = 'ios';
  else if (/Android/.test(s)) ou = 'android';
  else if (/Windows/.test(s)) ou = 'windows';
  else if (/Mac OS X|Macintosh/.test(s)) ou = 'mac';
  else if (/Linux|X11/.test(s)) ou = 'linux';
  return { br, ou, mob: /Mobi|iPhone|iPod/.test(s) ? '1' : '0' };
}

/** Ficha do aparelho: o que o app mandou (só categorias curtas) + o que o servidor deduz (navegador e região aproximada). */
function deviceInfo(dv, headers) {
  const out = {};
  const src = dv && typeof dv === 'object' && !Array.isArray(dv) ? dv : {};
  for (const k of DV_KEYS) if (typeof src[k] === 'string' && DV_RE.test(src[k])) out[k] = src[k];
  const h = headers || {};
  Object.assign(out, uaInfo(h['user-agent']));
  const country = String(h['x-vercel-ip-country'] || '').toLowerCase();
  const region = String(h['x-vercel-ip-country-region'] || '').toLowerCase();
  if (/^[a-z]{2}$/.test(country)) out.g = country + (/^[a-z0-9]{1,3}$/.test(region) ? '-' + region : '');
  for (const k of DV_SERVER) if (!out[k]) delete out[k];
  return out;
}

async function seen(cmd, prof, code, now, info) {
  const pa = Number(prof.pa) || 0;
  const due = !pa || now - pa >= PRESENCE_EVERY;
  const fields = {};
  const dv = info && info.dv && Object.keys(info.dv).length ? info.dv : null;
  if (dv) {
    let old = {};
    try { old = JSON.parse(prof.dv || '{}'); } catch (_) { old = {}; }
    const stable = (o) => DV_STABLE.map((k) => o[k] || '').join('|');
    const changed = !prof.dv || stable(old) !== stable(dv);
    const stale = now - (Number(prof.dt) || 0) > 24 * 3600 * 1000;
    if (changed || stale) {
      fields.dv = JSON.stringify(dv);
      fields.dt = String(now);
      if (!prof.dv) fields.df = String(now); // primeira ficha
      else if (changed) { fields.dp = prof.dv; fields.dn = String((Number(prof.dn) || 0) + 1); }
    }
  }
  if (!due && !Object.keys(fields).length) return false;
  try {
    if (due) Object.assign(fields, { pa: String(now) }, usageUpdate(prof, now));
    const list = [['HSET', U(code), ...Object.entries(fields).flat()]];
    if (due) list.push(['ZADD', Z.on, String(now), code]);
    await cmd.pipeline(list);
    return due;
  } catch (_) { return false; }
}

/** Uma origem passou de 30 perfis novos no dia: guarda para o painel avisar (7 dias). */
async function hot(cmd, key, now) {
  try {
    await cmd.pipeline([['ZADD', Z.hot, String(now), key], ['ZREMRANGEBYSCORE', Z.hot, '-inf', String(now - 7 * 86400000)]]);
  } catch (_) { /* aviso não derruba nada */ }
}

/** Liga ou desliga o papel: kind 't' (tem alunos) ou 's' (tem professor). */
async function setRole(cmd, code, kind, on, now) {
  try {
    const field = kind === 't' ? 'rt' : 'rs';
    const zs = kind === 't' ? Z.teach : Z.stud;
    await cmd.pipeline([
      ['HSET', U(code), field, on ? '1' : '0'],
      on ? ['ZADD', zs, String(now), code] : ['ZREM', zs, code],
    ]);
  } catch (_) { /* ok */ }
}

/** Tira o perfil de todos os índices. */
async function forget(cmd, code) {
  await cmd.pipeline([['ZREM', Z.last, code], ['ZREM', Z.born, code], ['ZREM', Z.teach, code], ['ZREM', Z.stud, code], ['ZREM', Z.on, code]]);
}

module.exports = { Z, TOUCH_EVERY, PRESENCE_EVERY, ONLINE_WINDOW, PRESENCE_KEEP, SESSION_GAP, created, touch, seen, setRole, forget, hot, parseHist, usageUpdate, uaInfo, deviceInfo };
