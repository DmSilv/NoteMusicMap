// POST /api/account: e-mail da conta, SEM senha. O e-mail serve para recuperar o perfil e entrar em outro aparelho.
//
// O perfil continua nascendo sem cadastro (código + segredo do aparelho). Aqui a pessoa pode, se quiser, ligar um e-mail
// a ele: o servidor manda um código de 6 dígitos para o e-mail, ela digita no app e pronto. Depois, num aparelho novo,
// "Entrar com e-mail" manda outro código e, ao confirmar, este aparelho passa a ser o dono do perfil (o segredo antigo
// deixa de valer, como na liberação pelo suporte do painel).
//
// O servidor guarda só um HASH do e-mail (com pepper) e uma versão mascarada para mostrar ("d***@gmail.com"). O código
// de 6 dígitos vale 10 minutos, aceita 5 tentativas e só é guardado como hash. Nunca registra o conteúdo do e-mail.
//
// Ações (todas POST):
//   status        { code, secret }                      -> { ok, enabled, linked, hint }
//   bind_start    { code, secret, email, lang? }        -> manda o código ao e-mail
//   bind_verify   { code, secret, email, otp }          -> liga o e-mail ao perfil
//   unbind        { code, secret }                      -> desliga o e-mail do perfil
//   login_start   { email, lang? }                      -> manda o código (sempre { ok } para não revelar quem tem conta)
//   login_verify  { email, otp, secret }                -> { ok, code, name }: este aparelho (segredo novo) vira o dono
//
// Precisa do Upstash Redis e das variáveis de e-mail (MAIL_API_KEY e MAIL_FROM). Sem e-mail configurado: 503 mail_unavailable.
// Custo: ~6 comandos por pedido de código, ~8 ao confirmar; só quando a pessoa usa o recurso.
'use strict';

const crypto = require('node:crypto');
const { config } = require('./_lib/config');
const { createStore } = require('./_lib/store');
const { mailEnabled, sendMail } = require('./_lib/mail');
const { serverError } = require('./_lib/error_store');
const { _internal } = require('./link');

const { normCode } = _internal;
const OTP_TTL = 600; // segundos
const OTP_TRIES = 5;
const CALLS_PER_HOUR = 40; // por origem
const BAD_PER_HOUR = 20; // tentativas erradas por origem
const SENDS_PER_HOUR = 5; // códigos por perfil e por e-mail
const LOGIN_STARTS_PER_HOUR = 10; // por origem

const sha = (s) => crypto.createHash('sha256').update(s).digest('hex');
const EM = 'acct:em'; // hash: hash do e-mail -> código do perfil
const U = (code) => `u:${code}`;
const OTP = (eh) => `acct:otp:${eh}`;

function clientIp(req) {
  const xf = String((req.headers && req.headers['x-forwarded-for']) || '').split(',')[0].trim();
  return xf || (req.socket && req.socket.remoteAddress) || 'ip-desconhecido';
}

function readBody(req) {
  let b = null;
  if (req.body && typeof req.body === 'object') b = req.body;
  else if (typeof req.body === 'string') {
    if (req.body.length > 1024) return null;
    try { b = JSON.parse(req.body); } catch (_) { return null; }
  }
  if (!b || typeof b !== 'object' || Array.isArray(b) || JSON.stringify(b).length > 1024) return null;
  return b;
}

/** E-mail em minúsculas e sem espaços, ou null se não parecer um e-mail. */
function normEmail(v) {
  if (typeof v !== 'string') return null;
  const t = v.trim().toLowerCase();
  if (t.length < 6 || t.length > 120 || /[\u0000-\u001f\u007f\s,;<>()[\]\\"]/.test(t)) return null;
  if (!/^[^@]+@[^@]+\.[^@.]{2,}$/.test(t)) return null;
  return t;
}

/** "d***@gmail.com": o suficiente para a pessoa reconhecer o próprio e-mail. */
function maskEmail(e) {
  const [u, d] = e.split('@');
  return `${u.slice(0, 1)}***@${d}`;
}

function mailText(kind, otp, lang) {
  const en = lang === 'en';
  if (kind === 'notice') {
    return en
      ? { subject: 'New sign-in to your Notemusic account', text: 'Your Notemusic account was just opened on a new device using this email.\n\nIf it was you, nothing to do. If it was not, open Notemusic on your usual device and remove the email under My account.' }
      : { subject: 'Novo acesso à sua conta do Notemusic', text: 'A sua conta do Notemusic acabou de ser aberta em um aparelho novo usando este e-mail.\n\nSe foi você, não precisa fazer nada. Se não foi, abra o Notemusic no seu aparelho de costume e remova o e-mail em Minha conta.' };
  }
  return en
    ? { subject: `Your Notemusic code: ${otp}`, text: `Your Notemusic code is ${otp}.\n\nIt works for 10 minutes. If you did not ask for it, you can ignore this message.` }
    : { subject: `Seu código do Notemusic: ${otp}`, text: `Seu código do Notemusic é ${otp}.\n\nEle vale por 10 minutos. Se não foi você que pediu, pode ignorar esta mensagem.` };
}

function makeHandler(deps = {}) {
  const fetchImpl = deps.fetch || globalThis.fetch;
  const getCfg = deps.config || (() => config());
  const clock = deps.now || Date.now;
  return async function handler(req, res) {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    const send = (code, obj) => { res.statusCode = code; res.end(JSON.stringify(obj)); };
    if (req.method !== 'POST') return send(405, { error: 'Use POST.' });

    const cfg = getCfg();
    const store = createStore(cfg, fetchImpl, clock, { allowMemory: !!deps.allowMemory });
    if (!store.durable) return send(503, { error: 'sync_unavailable' });
    const b = readBody(req);
    if (!b) return send(400, { error: 'Corpo inválido.' });

    const action = String(b.action || '');
    const hour = Math.floor(clock() / 3600000);
    const ip = sha(clientIp(req)).slice(0, 16);
    const eHash = (email) => crypto.createHmac('sha256', cfg.mail.pepper).update(email).digest('hex');
    const lang = b.lang === 'en' ? 'en' : 'pt';

    try {
      // Teto de pedidos por origem (barato: 1 comando).
      const g = await store.incr(`acct:ip:${ip}:${hour}`, 3600);
      if (g.n > CALLS_PER_HOUR) return send(429, { error: 'Muitas tentativas. Tente mais tarde.' });

      const bad = async (status, error) => {
        const f = await store.incr(`acct:bad:${ip}:${hour}`, 3600);
        if (f.n > BAD_PER_HOUR) return send(429, { error: 'Muitas tentativas. Tente mais tarde.' });
        return send(status, { error });
      };

      /** Dono do perfil (código + segredo do aparelho), como no vínculo. Devolve { code, prof } ou já respondeu. */
      const owner = async () => {
        const code = normCode(b.code);
        const secret = String(b.secret || '');
        if (!code || !/^[0-9a-f]{64}$/.test(secret)) { await bad(400, 'Código ou segredo inválido.'); return null; }
        const prof = await store.hgetall(U(code));
        const given = sha('lnk|' + secret);
        if (!prof.h || prof.h.length !== given.length || !crypto.timingSafeEqual(Buffer.from(prof.h), Buffer.from(given))) {
          await bad(403, 'Este código pertence a outro aparelho.');
          return null;
        }
        if (prof.bl === '1') { send(403, { error: 'blocked' }); return null; }
        return { code, prof };
      };

      /** Cria o código de 6 dígitos e manda por e-mail. */
      const issue = async (eh, email, kind, code) => {
        const otp = String(crypto.randomInt(0, 1000000)).padStart(6, '0');
        await store.set(OTP(eh), JSON.stringify({ k: kind, c: code, h: sha(`otp|${eh}|${otp}`), n: 0 }), OTP_TTL);
        const m = mailText('otp', otp, lang);
        await sendMail(cfg, fetchImpl, { to: email, subject: m.subject, text: m.text });
      };

      /** Confere o código de 6 dígitos (5 tentativas, 10 minutos, uso único). Devolve o registro ou null (e já respondeu). */
      const check = async (eh, kind, otp) => {
        let rec = null;
        try { rec = JSON.parse((await store.get(OTP(eh))) || 'null'); } catch (_) { rec = null; }
        if (!rec || rec.k !== kind || !/^\d{6}$/.test(String(otp || '')) || rec.n >= OTP_TRIES) {
          await bad(403, 'Código inválido ou vencido.');
          return null;
        }
        const given = sha(`otp|${eh}|${otp}`);
        if (given.length !== rec.h.length || !crypto.timingSafeEqual(Buffer.from(given), Buffer.from(rec.h))) {
          rec.n += 1;
          await store.set(OTP(eh), JSON.stringify(rec), OTP_TTL);
          await bad(403, 'Código inválido ou vencido.');
          return null;
        }
        await store.set(OTP(eh), '', 1); // uso único
        return rec;
      };

      // ---------------- status ----------------
      if (action === 'status') {
        // Perfil que ainda não foi ao servidor (vínculo online sempre desligado): só diz se o e-mail está disponível.
        const c0 = normCode(b.code);
        if (c0 && /^[0-9a-f]{64}$/.test(String(b.secret || '')) && !(await store.hget(U(c0), 'h'))) {
          return send(200, { ok: true, enabled: mailEnabled(cfg), linked: false, hint: '' });
        }
        const o = await owner();
        if (!o) return;
        return send(200, { ok: true, enabled: mailEnabled(cfg), linked: !!o.prof.eh, hint: o.prof.em || '' });
      }

      if (!['bind_start', 'bind_verify', 'unbind', 'login_start', 'login_verify'].includes(action)) return send(400, { error: 'Ação inválida.' });

      // ---------------- desligar o e-mail ----------------
      if (action === 'unbind') {
        const o = await owner();
        if (!o) return;
        if (o.prof.eh) {
          if ((await store.hget(EM, o.prof.eh)) === o.code) await store.hdel(EM, o.prof.eh);
          await store.hdel(U(o.code), 'eh');
          await store.hdel(U(o.code), 'em');
        }
        return send(200, { ok: true });
      }

      if (!mailEnabled(cfg)) return send(503, { error: 'mail_unavailable' });
      const email = normEmail(b.email);

      // ---------------- ligar o e-mail ao perfil ----------------
      if (action === 'bind_start') {
        const o = await owner();
        if (!o) return;
        if (!email) return send(400, { error: 'E-mail inválido.' });
        const eh = eHash(email);
        const holder = await store.hget(EM, eh);
        if (holder && holder !== o.code) return send(409, { error: 'email_in_use' });
        const a = await store.incr(`acct:snd:me:${o.code}:${hour}`, 3600);
        const c = await store.incr(`acct:snd:eh:${eh}:${hour}`, 3600);
        if (a.n > SENDS_PER_HOUR || c.n > SENDS_PER_HOUR) return send(429, { error: 'Muitos códigos pedidos. Tente mais tarde.' });
        try { await issue(eh, email, 'bind', o.code); } catch (e) { return send(502, { error: 'mail_failed' }); }
        return send(200, { ok: true, ttl: OTP_TTL });
      }

      if (action === 'bind_verify') {
        const o = await owner();
        if (!o) return;
        if (!email) return send(400, { error: 'E-mail inválido.' });
        const eh = eHash(email);
        const rec = await check(eh, 'bind', b.otp);
        if (!rec) return;
        if (rec.c !== o.code) return send(403, { error: 'Código inválido ou vencido.' });
        const holder = await store.hget(EM, eh);
        if (holder && holder !== o.code) return send(409, { error: 'email_in_use' });
        if (o.prof.eh && o.prof.eh !== eh && (await store.hget(EM, o.prof.eh)) === o.code) await store.hdel(EM, o.prof.eh); // troca de e-mail
        await store.hset(EM, eh, o.code);
        await store.hset(U(o.code), 'eh', eh);
        await store.hset(U(o.code), 'em', maskEmail(email));
        return send(200, { ok: true, hint: maskEmail(email) });
      }

      // ---------------- entrar com e-mail em outro aparelho ----------------
      if (action === 'login_start') {
        if (!email) return send(400, { error: 'E-mail inválido.' });
        const eh = eHash(email);
        const s = await store.incr(`acct:ls:${ip}:${hour}`, 3600);
        const c = await store.incr(`acct:snd:eh:${eh}:${hour}`, 3600);
        if (s.n > LOGIN_STARTS_PER_HOUR || c.n > SENDS_PER_HOUR) return send(429, { error: 'Muitos códigos pedidos. Tente mais tarde.' });
        const code = await store.hget(EM, eh);
        if (code) {
          const prof = await store.hgetall(U(code));
          if (prof.h && prof.bl !== '1') {
            try { await issue(eh, email, 'login', code); } catch (e) { /* não revela nada: a pessoa tenta de novo */ }
          }
        }
        return send(200, { ok: true, ttl: OTP_TTL }); // igual com ou sem conta: não revela quem tem conta
      }

      if (action === 'login_verify') {
        const secret = String(b.secret || '');
        if (!email || !/^[0-9a-f]{64}$/.test(secret)) return bad(400, 'Dados inválidos.');
        const eh = eHash(email);
        const rec = await check(eh, 'login', b.otp);
        if (!rec) return;
        const code = rec.c;
        const prof = await store.hgetall(U(code));
        if (!prof.h || prof.eh !== eh || prof.bl === '1') return bad(403, 'Código inválido ou vencido.');
        // este aparelho passa a ser o dono; o segredo antigo e o código de suporte pendente deixam de valer
        await store.hset(U(code), 'h', sha('lnk|' + secret));
        await store.hdel(U(code), 'sc');
        await store.hdel(U(code), 'sx');
        await store.hset(U(code), 'kr', String(clock()));
        try {
          const m = mailText('notice', '', lang);
          await sendMail(cfg, fetchImpl, { to: email, subject: m.subject, text: m.text });
        } catch (_) { /* o aviso é um extra */ }
        return send(200, { ok: true, code, name: prof.n || '' });
      }
    } catch (e) {
      if (String(e.message) === 'no-redis') return send(503, { error: 'sync_unavailable' });
      console.error('account error', e && e.message);
      await serverError({ cfg, fetchImpl, clock, allowMemory: !!deps.allowMemory }, 'account', e);
      return send(500, { error: 'Erro no servidor.' });
    }
  };
}

module.exports = makeHandler();
module.exports.makeHandler = makeHandler;
module.exports._internal = { normEmail, maskEmail };
