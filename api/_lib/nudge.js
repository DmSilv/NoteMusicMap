// Lembrete de estudo automático (recurso "lembrete_estudo"). Fica só entre o sistema e o aluno: o professor não vê nada.
//
// Como funciona sem varrer o banco: cada pessoa com notificação ligada tem no máximo UMA mensagem agendada no QStash
// ("confira daqui a 2 dias, às 18h dela"). Quando a mensagem chega, olhamos o último uso do app:
//   - usou há pouco, ou usa bastante (3 dias ou mais na última semana): NÃO manda nada, só confere de novo depois;
//   - está parada há 2 dias ou mais: manda uma notificação, no máximo 2 a cada 7 dias;
//   - ignorou 3 seguidas: para de vez. Volta a conferir só quando a pessoa abrir o app de novo.
// Custo por conferência: 1 mensagem do QStash e poucos comandos no Redis. Abrir o app com a conferência já marcada não gasta nada.
//
// Campos no perfil (u:<código>): ngp = tem notificação ligada; ngz = a pessoa desligou o lembrete de estudo;
// ngt = fuso (minutos); ngx = quando é a próxima conferência; ngv = versão (invalida mensagens antigas);
// ngn = lembretes seguidos sem a pessoa voltar; ngl = quando foram os últimos envios.
'use strict';

const { remindersEnabled, remindSig } = require('./agenda');
const { sendPush, validSubscription } = require('./webpush');
const { parseHist } = require('./profiles');

const HOUR = 3600000;
const DAY = 24 * HOUR;
const FEATURE = 'lembrete_estudo';
const CHECK_DAYS = 2; // de quanto em quanto tempo conferir
const AFTER_SEND_DAYS = 3; // depois de um envio, a próxima conferência
const IDLE_MS = 2 * DAY - 2 * HOUR; // "parada": sem abrir o app há cerca de 2 dias
const FREQUENT_DAYS = 3; // usou em 3 dias ou mais na última semana: não precisa de lembrete
const MAX_PER_WEEK = 2;
const MAX_UNANSWERED = 3;
const SEND_HOUR = 18; // hora local da pessoa (nunca de madrugada)
const DEFAULT_TZ = -180; // Brasília

const U = (c) => `u:${c}`, S = (c) => `us:${c}`, T = (c) => `ut:${c}`, PS = (c) => `ps:${c}`;

function cleanTz(v) {
  const n = Math.round(Number(v));
  return Number.isFinite(n) && n >= -840 && n <= 840 ? n : DEFAULT_TZ;
}

/** Quando conferir: [days] dias à frente, às 18h no fuso da pessoa (e sempre com pelo menos 12 h de folga). */
function nextCheckAt(now, tz, days) {
  const off = cleanTz(tz) * 60000;
  const local = new Date(now + off + days * DAY);
  let at = Date.UTC(local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate(), SEND_HOUR) - off;
  while (at < now + 12 * HOUR) at += DAY;
  return at;
}

/** Em quantos dos últimos 7 dias a pessoa usou o app. */
function activeDays(prof, now) {
  const from = new Date(now - 6 * DAY).toISOString().slice(0, 10);
  let n = 0;
  for (const [day, v] of parseHist(prof.uh)) if (day >= from && v[0] > 0) n++;
  return n;
}

const sentRecently = (prof, now) => String(prof.ngl || '').split(',').map(Number).filter((t) => t > 0 && now - t < 7 * DAY);

/**
 * A decisão, sem efeitos: { send, again, why }.
 * again = em quantos dias conferir de novo (0 = parar até a pessoa voltar).
 */
function decide(prof, now) {
  const last = Number(prof.pa) || 0;
  const sent = sentRecently(prof, now);
  const lastSent = Math.max(0, ...String(prof.ngl || '').split(',').map(Number).filter(Number.isFinite));
  const unanswered = last > lastSent ? 0 : Number(prof.ngn) || 0; // voltou depois do último aviso: zera
  if (!last) return { send: false, again: 0, why: 'sem uso registrado', unanswered };
  if (activeDays(prof, now) >= FREQUENT_DAYS) return { send: false, again: CHECK_DAYS, why: 'usa bastante', unanswered };
  if (now - last < IDLE_MS) return { send: false, again: CHECK_DAYS, why: 'usou há pouco', unanswered };
  if (unanswered >= MAX_UNANSWERED) return { send: false, again: 0, why: 'ignorou os últimos', unanswered };
  if (sent.length >= MAX_PER_WEEK) return { send: false, again: CHECK_DAYS, why: 'limite da semana', unanswered };
  return { send: true, again: AFTER_SEND_DAYS, why: 'parada', unanswered };
}

/** Agenda a conferência no QStash. Devolve true se foi aceita. */
async function publish(cfg, fetchImpl, code, at, ver) {
  const msg = { t: '', sc: code, id: 'nudge', o: at, u: ver, k: 'nudge' };
  msg.sig = remindSig(cfg, msg);
  try {
    const r = await fetchImpl(`${cfg.qstash.url}/v2/publish/${cfg.appBase}/api/remind`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${cfg.qstash.token}`,
        'Content-Type': 'application/json',
        'Upstash-Not-Before': String(Math.floor(at / 1000)),
        'Upstash-Retries': '1',
      },
      body: JSON.stringify(msg),
    });
    return r.status >= 200 && r.status < 300;
  } catch (_) {
    return false;
  }
}

async function scheduleCheck(cfg, fetchImpl, store, code, prof, now, days) {
  const ver = (Number(prof.ngv) || 0) + 1;
  const at = nextCheckAt(now, prof.ngt, days);
  const ok = await publish(cfg, fetchImpl, code, at, ver);
  await store.hset(U(code), 'ngv', String(ver));
  await store.hset(U(code), 'ngx', String(ok ? at : 0));
  prof.ngv = String(ver);
  prof.ngx = String(ok ? at : 0);
  return ok;
}

/**
 * Liga a conferência, se fizer sentido e ainda não houver uma marcada. Chamada quando a pessoa está usando o app
 * (ao ligar a notificação ou na sincronização). Sem nada para fazer, não gasta nenhum comando.
 */
async function arm(cfg, fetchImpl, store, code, prof, now, enabled) {
  if (!enabled || !remindersEnabled(cfg)) return false;
  if (prof.ngp !== '1' || prof.ngz === '1') return false;
  if (Number(prof.ngx) > now - HOUR) return false; // já tem uma marcada
  if (Number(prof.ngn) > 0) { await store.hset(U(code), 'ngn', '0'); prof.ngn = '0'; } // voltou: começa do zero
  return scheduleCheck(cfg, fetchImpl, store, code, prof, now, CHECK_DAYS);
}

async function stop(store, code) {
  await store.hset(U(code), 'ngx', '0');
}

/**
 * Chegou a hora de conferir [code] (mensagem do QStash com a versão [ver]).
 * [enabled] diz se o recurso está ligado para o perfil. Devolve um resumo do que foi feito (para o registro e os testes).
 */
async function fire(cfg, fetchImpl, store, code, ver, now, enabled) {
  const prof = await store.hgetall(U(code));
  if (!prof || !prof.h) return { ignored: 'perfil inexistente' };
  if (Number(prof.ngv) !== ver) return { ignored: 'mensagem antiga' };
  if (prof.bl === '1' || prof.ngz === '1' || prof.ngp !== '1' || !enabled(prof)) {
    await stop(store, code);
    return { ignored: 'desligado' };
  }
  const teachers = await store.hgetall(S(code));
  const names = [];
  let anyActive = false;
  for (const raw of Object.values(teachers)) {
    try {
      const j = JSON.parse(raw);
      if (!j.pz) { anyActive = true; if (j.n) names.push(String(j.n)); }
    } catch (_) { /* linha ruim */ }
  }
  // Quem só ensina não recebe cobrança de estudo.
  if (!Object.keys(teachers).length && (await store.hlen(T(code))) > 0) {
    await stop(store, code);
    return { ignored: 'professor' };
  }
  const d = decide(prof, now);
  let sent = 0;
  if (d.send) {
    const payload = { kind: 'study', who: anyActive && names.length === 1 ? names[0].slice(0, 40) : '' };
    const subs = await store.hgetall(PS(code));
    for (const [field, json] of Object.entries(subs)) {
      let sub = null;
      try { sub = validSubscription(JSON.parse(json)); } catch (_) { sub = null; }
      if (!sub) { await store.hdel(PS(code), field); continue; }
      const r = await sendPush(sub, payload, cfg.vapid, fetchImpl, Math.floor(now / 1000));
      if (r.ok) sent++;
      else if (r.gone) await store.hdel(PS(code), field);
    }
    if (!sent) {
      // nenhum aparelho recebe mais: para até a pessoa ligar a notificação de novo
      await store.hdel(U(code), 'ngp');
      await stop(store, code);
      return { ignored: 'sem aparelho' };
    }
    await store.hset(U(code), 'ngl', [...sentRecently(prof, now), now].join(','));
    await store.hset(U(code), 'ngn', String(d.unanswered + 1));
  }
  if (!d.again) {
    await stop(store, code);
    return { sent, stopped: true, why: d.why };
  }
  await scheduleCheck(cfg, fetchImpl, store, code, prof, now, d.again);
  return { sent, why: d.why };
}

module.exports = { FEATURE, arm, fire, decide, nextCheckAt, activeDays, cleanTz, MAX_PER_WEEK, MAX_UNANSWERED, FREQUENT_DAYS };
