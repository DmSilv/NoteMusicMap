// Regras dos relatórios de erro (iguais às do app, em `afina_core/errors.dart`): higienização,
// impressão digital do bug, validação do pacote e nomes das chaves no Redis.
'use strict';

const crypto = require('node:crypto');

const MAX_DETAIL = 600;
const MAX_WHERE = 120;

const SHARE_CODE = /\b[23456789A-HJ-NP-Za-hj-np-z]{4}-[23456789A-HJ-NP-Za-hj-np-z]{4}\b/g;
const EMAIL = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g;
const HEX_SECRET = /\b[0-9a-fA-F]{24,}\b/g;
const URL_RE = /https?:\/\/[^\s)]+/g;
const LONG_DIGITS = /\b\d{6,}\b/g;
// eslint-disable-next-line no-control-regex
const INVISIBLE = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F\u200B-\u200F\u202A-\u202E\u2060-\u2064\uFEFF]/g;

/** Tira do texto tudo o que identifica alguém ou dá acesso (mesma regra do app). */
function sanitize(s, max = MAX_DETAIL) {
  if (s == null) return '';
  let t = String(s).replace(/\r/g, '');
  t = t.replace(URL_RE, (u) => {
    try { return `https://${new URL(u).host}/…`; } catch (_) { return '[endereço]'; }
  });
  t = t.replace(EMAIL, '[e-mail]').replace(HEX_SECRET, '[segredo]').replace(SHARE_CODE, '[código]').replace(LONG_DIGITS, '[número]');
  t = t.replace(INVISIBLE, '').trim();
  return Array.from(t).slice(0, max).join('').trimEnd();
}

const firstLine = (s) => String(s || '').split('\n')[0];

/**
 * 1ª linha do detalhe sem o que varia de uma ocorrência para outra (endereços de memória, índices,
 * tamanhos, linhas e colunas): "índice 3 fora de 10" e "índice 4 fora de 12" são o MESMO bug.
 */
function stableLine(detail) {
  return firstLine(detail).replace(/0x[0-9a-fA-F]+/g, '0x#').replace(/\d+/g, '#');
}

/** Impressão digital: o mesmo bug dá sempre a mesma (código + onde + 1ª linha estável do detalhe). */
function fingerprint(code, where, detail) {
  return crypto.createHash('sha256').update(`${code}|${where}|${stableLine(detail)}`).digest('hex').slice(0, 12);
}

const SEVERITIES = ['critical', 'action', 'info'];
const CODE_RE = /^[A-Z]{2,4}-\d{2}$/;
const ID_RE = /^[a-z0-9]{16,40}$/;
const BUILD_RE = /^[A-Za-z0-9._-]{1,16}$/;
const PLAT_RE = /^[a-z0-9-]{1,24}$/;
const CRUMB_RE = /^[\p{L}\p{N} ›._:-]{1,40}$/u;

/** Valida e limpa o pacote vindo do app; devolve null se for inválido. */
function cleanReport(b) {
  if (!b || typeof b !== 'object' || Array.isArray(b)) return null;
  const id = String(b.id || '');
  const c = String(b.c || '');
  const s = String(b.s || '');
  if (!ID_RE.test(id) || !CODE_RE.test(c) || !SEVERITIES.includes(s)) return null;
  const v = BUILD_RE.test(String(b.v || '')) ? String(b.v) : 'dev';
  const pl = PLAT_RE.test(String(b.pl || '')) ? String(b.pl) : 'outro';
  const inst = ['app', 'pwa', 'browser'].includes(b.in) ? b.in : 'browser';
  const lk = /^[a-z]{1,12}$/.test(String(b.lk || '')) ? String(b.lk) : '';
  const vw = ['student', 'teacher'].includes(b.vw) ? b.vw : '';
  const bc = (Array.isArray(b.bc) ? b.bc : []).slice(0, 10).map((x) => String(x)).filter((x) => CRUMB_RE.test(x));
  const w = sanitize(b.w, MAX_WHERE);
  const d = sanitize(b.d, MAX_DETAIL);
  return { id, c, s, w, d, v, pl, in: inst, lk, vw, bc, fp: fingerprint(c, w, d) };
}

const day = (ms) => new Date(ms - 3 * 3600 * 1000).toISOString().slice(0, 10); // dia no Brasil
const hour = (ms) => new Date(ms - 3 * 3600 * 1000).toISOString().slice(11, 13);

/** Nomes das chaves no Redis (um só lugar). */
const K = {
  bug: (fp) => `er:f:${fp}`, // hash: n, st (status), first, last, c, s, w, msg + contadores v:/p:/i:
  devices: (fp) => `er:fd:${fp}`, // HyperLogLog de aparelhos afetados
  trend: (fp) => `er:t:${fp}`, // hash: dia -> quantas vezes
  recent: (fp) => `er:o:${fp}`, // lista: últimas ocorrências
  idx: 'er:idx', // zset: fp -> última vez
  resolved: 'er:rs', // hash: fp -> JSON { at, build }
  notes: 'er:n', // hash: fp -> anotação do admin
  builds: 'er:b', // hash: build -> primeira vez visto
  daily: (d) => `er:d:${d}`, // hash do dia: total, critical, action, info, hHH
  rateDevice: (id, h) => `er:rl:${id}:${h}`,
  rateGlobal: (d) => `er:cap:${d}`,
};

module.exports = { sanitize, fingerprint, stableLine, cleanReport, day, hour, K, MAX_DETAIL, SEVERITIES };
