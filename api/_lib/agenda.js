// Agenda de aulas no servidor: limpeza do que chega, cálculo da próxima aula e agendamento do
// lembrete (QStash), uma mensagem por vez (a aula semanal agenda a próxima ao disparar).
'use strict';

const crypto = require('node:crypto');

const MIN = 60 * 1000;
const DAY = 24 * 60 * MIN;
const WEEK = 7 * DAY;
const REMINDER_MIN = 15;
const MAX_SKIPS = 30;
const MAX_SLOTS = 400;
const MAX_DELAY = 6 * DAY; // o plano grátis do QStash limita o atraso (~7 dias): agenda em passos de até 6

// Caracteres que enganam a leitura (inversao de direcao, largura zero) e de controle somem.
const INVISIBLE = new RegExp('[\\u00ad\\u200b-\\u200f\\u2028-\\u202e\\u2060-\\u2064\\u2066-\\u2069\\ufeff]', 'g');
const CONTROL = new RegExp('[\\u0000-\\u001f\\u007f-\\u009f]', 'g');
const clean = (v, max) =>
  String(v == null ? '' : v).replace(INVISIBLE, '').replace(CONTROL, ' ').replace(/\s+/g, ' ').trim().slice(0, max);

/** Valida e limpa uma aula marcada vinda do app; null se não for válida. */
function cleanSlot(s, now) {
  if (!s || typeof s !== 'object' || Array.isArray(s)) return null;
  const id = String(s.id || '');
  if (!/^[a-z0-9]{2,40}$/.test(id)) return null;
  const start = Math.round(Number(s.s));
  if (!Number.isFinite(start) || start < 1577836800000 || start > 4102444800000) return null;
  const d = Math.min(240, Math.max(15, Math.round(Number(s.d)) || 60));
  const x = [];
  for (const v of (Array.isArray(s.x) ? s.x : []).slice(0, MAX_SKIPS)) {
    const n = Math.round(Number(v));
    if (Number.isFinite(n)) x.push(n);
  }
  const u = Math.round(Number(s.u));
  if (!Number.isFinite(u) || u < 0 || u > now + DAY) return null;
  const out = { id, s: start, d, u };
  if (s.w === 1 || s.w === true) out.w = 1;
  if (x.length) out.x = x;
  const n = clean(s.n, 200);
  if (n) out.n = n;
  if (s.c === 1 || s.c === true) out.c = 1;
  return out;
}

/** Início da primeira aula que começa em [after] ou depois e não foi cancelada (null se nenhuma). */
function nextStart(slot, after) {
  if (slot.c) return null;
  const skipped = new Set(slot.x || []);
  if (!slot.w) return slot.s >= after && !skipped.has(slot.s) ? slot.s : null;
  let k = after <= slot.s ? 0 : Math.ceil((after - slot.s) / WEEK);
  for (let i = 0; i < MAX_SKIPS + 2; i++, k++) {
    const s = slot.s + k * WEEK;
    if (!skipped.has(s)) return s;
  }
  return null;
}

/** Assinatura própria da mensagem de lembrete: só quem tem o segredo do servidor consegue criar uma. */
function remindSecret(cfg) {
  const base = cfg.qstash.token || cfg.qstash.currentKey || '';
  return base ? crypto.createHash('sha256').update('remind|' + base).digest() : null;
}
function remindSig(cfg, m) {
  const secret = remindSecret(cfg);
  if (!secret) return '';
  return crypto.createHmac('sha256', secret).update(`${m.t}|${m.sc}|${m.id}|${m.o}|${m.u}|${m.k}`).digest('hex');
}
function validRemindSig(cfg, m) {
  const want = remindSig(cfg, m);
  const got = String(m.sig || '');
  if (!want || want.length !== got.length) return false;
  return crypto.timingSafeEqual(Buffer.from(want), Buffer.from(got));
}

/** O lembrete está configurado (QStash + chaves VAPID)? */
function remindersEnabled(cfg) {
  return !!(cfg.qstash.token && cfg.vapid.publicKey && cfg.vapid.privateKey);
}

/**
 * Agenda no QStash a próxima mensagem desta aula (15 min antes da próxima ocorrência).
 * Devolve 'scheduled' | 'off' | 'none' (sem próxima aula) | 'error'.
 */
async function scheduleNext(cfg, fetchImpl, teacher, student, slot, nowMs, afterMs = nowMs) {
  if (!remindersEnabled(cfg)) return 'off';
  const occ = nextStart(slot, afterMs);
  if (occ == null) return 'none';
  const target = occ - REMINDER_MIN * MIN;
  let at = Math.max(target, nowMs + 5000);
  let kind = 'rem';
  if (at - nowMs > MAX_DELAY) {
    at = nowMs + MAX_DELAY;
    kind = 'wake'; // acorda mais perto da data e agenda de novo
  }
  const msg = { t: teacher, sc: student, id: slot.id, o: occ, u: slot.u, k: kind };
  msg.sig = remindSig(cfg, msg);
  try {
    const r = await fetchImpl(`${cfg.qstash.url}/v2/publish/${cfg.appBase}/api/remind`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${cfg.qstash.token}`,
        'Content-Type': 'application/json',
        'Upstash-Not-Before': String(Math.floor(at / 1000)),
        'Upstash-Retries': '2',
      },
      body: JSON.stringify(msg),
    });
    return r.status >= 200 && r.status < 300 ? 'scheduled' : 'error';
  } catch (_) {
    return 'error';
  }
}

/** Confere o JWT do QStash (assinatura HS256 com a chave atual ou a próxima, e validade). */
function verifyQstashJwt(cfg, token, nowSec) {
  const keys = [cfg.qstash.currentKey, cfg.qstash.nextKey].filter(Boolean);
  if (!keys.length) return true; // sem chaves de assinatura configuradas: vale só a assinatura própria
  const parts = String(token || '').split('.');
  if (parts.length !== 3) return false;
  const data = `${parts[0]}.${parts[1]}`;
  for (const k of keys) {
    const want = crypto.createHmac('sha256', k).update(data).digest();
    const got = Buffer.from(parts[2], 'base64url');
    if (want.length === got.length && crypto.timingSafeEqual(want, got)) {
      try {
        const c = JSON.parse(Buffer.from(parts[1], 'base64url').toString());
        if (c.iss !== 'Upstash') return false;
        if (c.exp && nowSec > c.exp) return false;
        if (c.nbf && nowSec + 60 < c.nbf) return false;
        return true;
      } catch (_) {
        return false;
      }
    }
  }
  return false;
}

module.exports = {
  MIN, DAY, WEEK, REMINDER_MIN, MAX_SLOTS,
  cleanSlot, nextStart, remindSig, validRemindSig, remindersEnabled, scheduleNext, verifyQstashJwt,
};
