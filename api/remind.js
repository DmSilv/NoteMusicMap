// POST /api/remind: chamado pelo QStash 15 minutos antes de uma aula. Envia a notificação ao
// professor e ao aluno (Web Push) e agenda o lembrete da próxima aula (se a aula é semanal).
//
// Só aceita mensagens que o próprio servidor criou: assinatura própria (HMAC com um segredo
// derivado da chave do QStash) e, se as chaves de assinatura estão configuradas, o JWT do QStash.
// Mensagem velha (aula mudada, cancelada, dia pulado, vínculo desfeito) é ignorada.
'use strict';

const { config } = require('./_lib/config');
const { createStore } = require('./_lib/store');
const { nextStart, validRemindSig, remindersEnabled, scheduleNext, verifyQstashJwt, MIN } = require('./_lib/agenda');
const { sendPush, validSubscription } = require('./_lib/webpush');
const { serverError } = require('./_lib/error_store');
const { bump } = require('./_lib/metrics');

const ALPHABET = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
function normCode(s) {
  const t = String(s || '').toUpperCase().replace(/[\s-]/g, '');
  if (t.length !== 8) return null;
  for (const c of t) if (!ALPHABET.includes(c)) return null;
  let sum = 0;
  for (let i = 0; i < 7; i++) sum += ALPHABET.indexOf(t[i]) * (2 * i + 1);
  if (ALPHABET[sum % 32] !== t[7]) return null;
  return `${t.slice(0, 4)}-${t.slice(4)}`;
}

const U = (c) => `u:${c}`;
const T = (c) => `ut:${c}`;
const SL = (c) => `sl:${c}`;
const PS = (c) => `ps:${c}`;

function makeHandler(deps = {}) {
  const fetchImpl = deps.fetch || globalThis.fetch;
  const getCfg = deps.config || (() => config());
  const clock = deps.now || Date.now;
  return async function handler(req, res) {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.setHeader('Cache-Control', 'no-store');
    const send = (code, obj) => { res.statusCode = code; res.end(JSON.stringify(obj)); };
    if (req.method !== 'POST') return send(405, { error: 'Use POST.' });

    const cfg = getCfg();
    if (!remindersEnabled(cfg)) return send(503, { error: 'reminders_unavailable' });
    const store = createStore(cfg, fetchImpl, clock, { allowMemory: !!deps.allowMemory });
    if (!store.durable) return send(503, { error: 'sync_unavailable' });

    let m = req.body;
    if (typeof m === 'string') { try { m = JSON.parse(m); } catch (_) { m = null; } }
    if (!m || typeof m !== 'object') return send(400, { error: 'Corpo inválido.' });

    // 1) Autenticidade.
    const jwt = String((req.headers && (req.headers['upstash-signature'] || req.headers['Upstash-Signature'])) || '');
    if (!validRemindSig(cfg, m) || !verifyQstashJwt(cfg, jwt, Math.floor(clock() / 1000))) {
      return send(401, { error: 'Assinatura inválida.' });
    }
    const t = normCode(m.t), sc = normCode(m.sc);
    const id = String(m.id || '');
    const o = Number(m.o), u = Number(m.u);
    if (!t || !sc || !/^[a-z0-9]{2,40}$/.test(id) || !Number.isFinite(o) || !Number.isFinite(u) || !['rem', 'wake'].includes(m.k)) {
      return send(400, { error: 'Mensagem inválida.' });
    }

    try {
      // 2) Mensagem repetida (o QStash tenta de novo se não respondermos 2xx): só uma vez.
      const dup = await store.incr(`lnkrem:${t}:${id}:${o}:${m.k}`, 86400);
      if (dup.n > 1) return send(200, { ok: true, ignored: 'duplicada' });

      // 3) A aula ainda vale desse jeito?
      const raw = await store.hget(SL(t), id);
      if (raw === undefined) return send(200, { ok: true, ignored: 'aula inexistente' });
      let slot;
      try { slot = JSON.parse(raw); } catch (_) { return send(200, { ok: true, ignored: 'aula ilegível' }); }
      if (slot.c || slot.u !== u || slot.sc !== sc) return send(200, { ok: true, ignored: 'aula mudou' });
      if ((await store.hget(T(t), sc)) === undefined) return send(200, { ok: true, ignored: 'vínculo desfeito' });
      if (nextStart(slot, o) !== o) return send(200, { ok: true, ignored: 'dia cancelado' });

      const now = clock();
      if (m.k === 'wake') {
        const r = await scheduleNext(cfg, fetchImpl, t, sc, slot, now);
        return send(200, { ok: true, rescheduled: r });
      }

      // 4) Lembrete: avisa os dois (se ainda dá tempo: não manda aviso de aula que já começou há muito).
      let sent = 0;
      if (now <= o + 5 * MIN) {
        const [tn, sn] = await Promise.all([store.hget(U(t), 'n'), store.hget(U(sc), 'n')]);
        const targets = [
          [t, { kind: 'lesson', role: 'teacher', start: o, who: sn || '' }],
          [sc, { kind: 'lesson', role: 'student', start: o, who: tn || '' }],
        ];
        for (const [who, payload] of targets) {
          const subs = await store.hgetall(PS(who));
          for (const [field, json] of Object.entries(subs)) {
            let sub = null;
            try { sub = validSubscription(JSON.parse(json)); } catch (_) { /* ruim */ }
            if (!sub) { await store.hdel(PS(who), field); continue; }
            const r = await sendPush(sub, payload, cfg.vapid, fetchImpl, Math.floor(now / 1000));
            if (r.ok) sent++;
            else if (r.gone) await store.hdel(PS(who), field); // aparelho desinstalou/negou: limpa
          }
        }
      }

      // 5) Aula semanal: agenda o lembrete da próxima.
      const next = slot.w ? await scheduleNext(cfg, fetchImpl, t, sc, slot, now, o + 1) : 'none';
      if (sent > 0) await bump(cfg, fetchImpl, clock, { allowMemory: !!deps.allowMemory }, 'remind');
      return send(200, { ok: true, sent, next });
    } catch (e) {
      if (String(e.message) === 'no-redis') return send(503, { error: 'sync_unavailable' });
      console.error('remind error', e && e.message);
      await serverError({ cfg, fetchImpl, clock, allowMemory: !!deps.allowMemory }, 'remind', e);
      return send(500, { error: 'Erro ao enviar o lembrete.' }); // o QStash tenta de novo
    }
  };
}

module.exports = makeHandler();
module.exports.makeHandler = makeHandler;
