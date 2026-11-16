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
// CHAVE DE 25 CARACTERES (sem e-mail, funciona mesmo com o envio de e-mail desligado): o app pede uma chave aleatória
// (XXXXX-XXXXX-XXXXX-XXXXX-XXXXX, 125 bits) que o servidor guarda só como hash; num aparelho novo, digitá-la faz o aparelho
// virar o dono do perfil (o segredo antigo deixa de valer). Gerar outra chave cancela a anterior.
//
// Ações (todas POST):
//   status        { code, secret }                      -> { ok, enabled, linked, hint, hasKey }
//   rk_new        { code, secret }                      -> { ok, key }: gera a chave de 25 (a anterior deixa de valer)
//   rk_login      { key, secret }                       -> { ok, code, name }: este aparelho (segredo novo) vira o dono
//   bind_start    { code, secret, email, lang? }        -> manda o código ao e-mail
//   bind_verify   { code, secret, email, otp }          -> liga o e-mail ao perfil
//   unbind        { code, secret }                      -> desliga o e-mail do perfil
//   login_start   { email, lang? }                      -> manda o código (sempre { ok } para não revelar quem tem conta)
//   login_verify  { email, otp, secret, drop?, dn? }    -> { ok, code, name }: este aparelho (segredo novo) entra na conta
//   pair_new      { code, secret }                      -> { ok, pair: 'XXXX-XXXX', ttl }: código de 10 min para ligar OUTRO aparelho
//   pair_join     { pair, secret, drop?, dn? }          -> { ok, code, name }: o aparelho novo entra na conta (sem e-mail nem chave)
//   devices       { code, secret }                      -> { ok, max, devices: [{ id, ou, br, md, dn, c, l, me }] }
//   device_remove { code, secret, id }                  -> tira um aparelho da conta (nunca o último)
//   device_name   { code, secret, dn }                  -> dá um apelido a ESTE aparelho
//
// APARELHOS: a mesma conta abre em até 5 aparelhos (api/_lib/devices.js). Entrar com e-mail ou chave ADICIONA o aparelho;
// com 5 já na conta, responde 422 { error: 'device_limit', max, devices } e o app pergunta qual tirar (repete com drop: id).
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
const devices = require('./_lib/devices');
const profilesLib = require('./_lib/profiles');

const { normCode } = _internal;
const OTP_TTL = 600; // segundos
const OTP_TRIES = 5;
const CALLS_PER_HOUR = 40; // por origem
const BAD_PER_HOUR = 20; // tentativas erradas por origem
const SENDS_PER_HOUR = 5; // códigos por perfil e por e-mail
const LOGIN_STARTS_PER_HOUR = 10; // por origem

const sha = (s) => crypto.createHash('sha256').update(s).digest('hex');

/** A chave digitada (com ou sem hífens, minúsculas) em 25 símbolos, ou null. */
function normKey(v) {
  if (typeof v !== 'string' || v.length > 60) return null;
  const k = v.toUpperCase().replace(/[\s-]/g, '');
  if (k.length !== RK_LEN) return null;
  for (const c of k) if (!RK_ALPHABET.includes(c)) return null;
  return k;
}
const keyHash = (k) => sha('rk|' + k);
function newKey() {
  let k = '';
  for (let i = 0; i < RK_LEN; i++) k += RK_ALPHABET[crypto.randomInt(0, 32)];
  return k;
}
const showKey = (k) => k.match(/.{5}/g).join('-');
const EM = 'acct:em'; // hash: hash do e-mail -> código do perfil
const RK = 'acct:rk'; // hash: hash da chave de 25 -> código do perfil
const RK_ALPHABET = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ'; // 32 símbolos sem 0, O, 1 e I
const RK_LEN = 25;
const KEYS_PER_HOUR = 5; // chaves novas por perfil
const U = (code) => `u:${code}`;
const OTP = (eh) => `acct:otp:${eh}`;
const DEV_CALLS_PER_HOUR = 180; // pedidos de aparelhos por perfil (a tela de adicionar confere a cada 10 s enquanto o código está aberto)
const PAIR_TTL = 600; // segundos
const PAIR_TRIES = 5;
const PAIRS_PER_HOUR = 10; // códigos de pareamento por perfil
const PAIR = (h) => `acct:pair:${h}`;
const PAIR_ALPHABET = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
/** O código digitado (com ou sem hífen, minúsculas) em 8 símbolos, ou null. */
function normPair(v) {
  if (typeof v !== 'string' || v.length > 24) return null;
  const k = v.toUpperCase().replace(/[\s-]/g, '');
  if (k.length !== 8) return null;
  for (const c of k) if (!PAIR_ALPHABET.includes(c)) return null;
  return k;
}
const pairHash = (k) => sha('pair|' + k);
function newPair() {
  let k = '';
  for (let i = 0; i < 8; i++) k += PAIR_ALPHABET[crypto.randomInt(0, 32)];
  return k;
}

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
      ? { subject: 'New sign-in to your Notemusic account', text: 'Your Notemusic account was just opened on a new device using this email.\n\nIf it was you, nothing to do. If it was not, open Notemusic on a device you trust, go to My account > Devices and remove the one you do not recognize. Then generate a new recovery key under My account > Recovery key.' }
      : { subject: 'Novo acesso à sua conta do Notemusic', text: 'A sua conta do Notemusic acabou de ser aberta em um aparelho novo usando este e-mail.\n\nSe foi você, não precisa fazer nada. Se não foi, abra o Notemusic num aparelho em que você confia, vá em Minha conta › Aparelhos e tire o que você não reconhece. Depois gere uma nova chave de recuperação em Minha conta › Chave de recuperação.' };
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
        if (!prof.h || !devices.find(prof, given)) {
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
          return send(200, { ok: true, enabled: mailEnabled(cfg), linked: false, hint: '', hasKey: false });
        }
        const o = await owner();
        if (!o) return;
        return send(200, { ok: true, enabled: mailEnabled(cfg), linked: !!o.prof.eh, hint: o.prof.em || '', hasKey: !!o.prof.rk });
      }

      if (!['bind_start', 'bind_verify', 'unbind', 'login_start', 'login_verify', 'rk_new', 'rk_login', 'devices', 'device_remove', 'device_name', 'pair_new', 'pair_join'].includes(action)) return send(400, { error: 'Ação inválida.' });

      // Ficha do aparelho de quem pede (sistema, navegador, modelo): o servidor deduz; nada de IP.
      const infoOf = () => {
        const i = profilesLib.deviceInfo(undefined, req.headers);
        return { ou: i.ou, br: i.br, md: i.md };
      };
      const limitReply = (r) => send(422, { error: 'device_limit', max: devices.MAX_DEVICES, devices: r.devices.map((d) => devices.view(d)) });

      // ---------------- aparelhos da conta ----------------
      if (action === 'devices' || action === 'device_remove' || action === 'device_name') {
        const o = await owner();
        if (!o) return;
        const n = await store.incr(`acct:dev:${o.code}:${hour}`, 3600);
        if (n.n > DEV_CALLS_PER_HOUR) return send(429, { error: 'Muitas tentativas. Tente mais tarde.' });
        const mine = devices.secretHash(String(b.secret));
        if (action === 'device_remove') {
          const id = String(b.id || '');
          const cur = devices.find(o.prof, mine);
          if (cur && cur.i === id) return send(400, { error: 'current_device' });
          const r = await devices.remove(store, o.code, o.prof, id);
          if (r.missing) return send(404, { error: 'Aparelho não encontrado.' });
          if (r.last) return send(400, { error: 'last_device' });
          await store.hset(U(o.code), 'kr', String(clock())); // quem foi tirado percebe na próxima consulta
          return send(200, { ok: true, max: devices.MAX_DEVICES, devices: r.devices.map((d) => devices.view(d, mine)) });
        }
        if (action === 'device_name') {
          await devices.rename(store, o.code, o.prof, mine, b.dn);
          const prof = await store.hgetall(U(o.code));
          return send(200, { ok: true, max: devices.MAX_DEVICES, devices: devices.list(prof).map((d) => devices.view(d, mine)) });
        }
        return send(200, { ok: true, max: devices.MAX_DEVICES, devices: devices.list(o.prof).map((d) => devices.view(d, mine)) });
      }

      // ---------------- ligar outro aparelho com um código de 10 minutos (sem e-mail e sem chave) ----------------
      // O aparelho que já está na conta gera o código (pair_new) e o aparelho novo o digita (pair_join). Uso único,
      // 5 tentativas, 10 minutos, só o hash fica guardado.
      if (action === 'pair_new') {
        const o = await owner();
        if (!o) return;
        const n = await store.incr(`acct:pairn:${o.code}:${hour}`, 3600);
        if (n.n > PAIRS_PER_HOUR) return send(429, { error: 'Muitas tentativas. Tente mais tarde.' });
        const k = newPair();
        await store.set(PAIR(pairHash(k)), JSON.stringify({ c: o.code, n: 0 }), PAIR_TTL);
        return send(200, { ok: true, pair: `${k.slice(0, 4)}-${k.slice(4)}`, ttl: PAIR_TTL });
      }
      /** Põe o aparelho de quem pede na conta (e responde se a conta já está cheia). Devolve true se entrou. */
      const joinDevice = async (code, prof, secret, dropId, name) => {
        const r = await devices.add(store, code, prof, devices.secretHash(secret), infoOf(), name, clock(), dropId);
        if (r.limit) { limitReply(r); return false; }
        return true;
      };

      if (action === 'pair_join') {
        const k = normPair(b.pair);
        const secret = String(b.secret || '');
        if (!k || !/^[0-9a-f]{64}$/.test(secret)) return bad(400, 'Código inválido ou vencido.');
        const key = PAIR(pairHash(k));
        let rec = null;
        try { rec = JSON.parse((await store.get(key)) || 'null'); } catch (_) { rec = null; }
        if (!rec || !rec.c || rec.n >= PAIR_TRIES) return bad(403, 'Código inválido ou vencido.');
        const code = rec.c;
        const prof = await store.hgetall(U(code));
        if (!prof.h || prof.bl === '1') return bad(403, 'Código inválido ou vencido.');
        if (!(await joinDevice(code, prof, secret, b.drop, b.dn))) return; // conta cheia: 422, o código continua valendo
        await store.set(key, '', 1); // uso único
        await store.hset(U(code), 'kr', String(clock()));
        return send(200, { ok: true, code, name: prof.n || '' });
      }

      // ---------------- chave de recuperação de 25 caracteres (não depende de e-mail) ----------------
      if (action === 'rk_new') {
        const o = await owner();
        if (!o) return;
        const n = await store.incr(`acct:rkn:${o.code}:${hour}`, 3600);
        if (n.n > KEYS_PER_HOUR) return send(429, { error: 'Muitas tentativas. Tente mais tarde.' });
        const key = newKey();
        const h = keyHash(key);
        if (o.prof.rk && (await store.hget(RK, o.prof.rk)) === o.code) await store.hdel(RK, o.prof.rk); // a chave anterior deixa de valer
        await store.hset(RK, h, o.code);
        await store.hset(U(o.code), 'rk', h);
        return send(200, { ok: true, key: showKey(key) });
      }

      if (action === 'rk_login') {
        const key = normKey(b.key);
        const secret = String(b.secret || '');
        if (!key || !/^[0-9a-f]{64}$/.test(secret)) return bad(400, 'Chave inválida.');
        const h = keyHash(key);
        const code = await store.hget(RK, h);
        const prof = code ? await store.hgetall(U(code)) : {};
        if (!code || !prof.h || prof.rk !== h || prof.bl === '1') return bad(403, 'Chave inválida.');
        // este aparelho entra na conta (até 5); o código de suporte pendente deixa de valer
        if (!(await joinDevice(code, prof, secret, b.drop, b.dn))) return;
        await store.hdel(U(code), 'sc');
        await store.hdel(U(code), 'sx');
        await store.hset(U(code), 'kr', String(clock()));
        return send(200, { ok: true, code, name: prof.n || '' });
      }

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
        // este aparelho entra na conta (até 5); com a conta cheia o código de 6 dígitos continua valendo para escolher qual tirar
        if (!(await joinDevice(code, prof, secret, b.drop, b.dn))) {
          await store.set(OTP(eh), JSON.stringify(rec), OTP_TTL);
          return;
        }
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
module.exports._internal = { normEmail, maskEmail, normKey, normPair };
