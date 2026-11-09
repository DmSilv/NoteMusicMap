// Web Push (RFC 8030 + VAPID RFC 8292 + criptografia aes128gcm RFC 8291) só com o módulo `crypto`
// do Node: o projeto não instala pacotes npm, então nada de dependência externa.
'use strict';

const crypto = require('node:crypto');

const b64u = (buf) => Buffer.from(buf).toString('base64url');
const fromB64u = (s) => Buffer.from(String(s || ''), 'base64url');

/** Par de chaves VAPID (P-256): { publicKey, privateKey } em base64url. */
function generateVapidKeys() {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const pub = publicKey.export({ format: 'jwk' });
  const prv = privateKey.export({ format: 'jwk' });
  const raw = Buffer.concat([Buffer.from([4]), fromB64u(pub.x), fromB64u(pub.y)]);
  return { publicKey: b64u(raw), privateKey: prv.d };
}

/** Chave privada VAPID (base64url de 32 bytes) + pública (65 bytes) -> KeyObject para assinar. */
function privateKeyObject(privateB64, publicB64) {
  const pub = fromB64u(publicB64);
  if (pub.length !== 65 || pub[0] !== 4) throw new Error('chave pública VAPID inválida');
  return crypto.createPrivateKey({
    key: { kty: 'EC', crv: 'P-256', d: privateB64, x: b64u(pub.subarray(1, 33)), y: b64u(pub.subarray(33, 65)) },
    format: 'jwk',
  });
}

/** Cabeçalho Authorization VAPID para o servidor de push de [endpoint]. */
function vapidAuthorization(endpoint, vapid, nowSec) {
  const aud = new URL(endpoint).origin;
  const header = b64u(JSON.stringify({ typ: 'JWT', alg: 'ES256' }));
  const claims = b64u(JSON.stringify({ aud, exp: nowSec + 12 * 3600, sub: vapid.subject }));
  const data = `${header}.${claims}`;
  const sig = crypto.sign('sha256', Buffer.from(data), { key: privateKeyObject(vapid.privateKey, vapid.publicKey), dsaEncoding: 'ieee-p1363' });
  return `vapid t=${data}.${b64u(sig)}, k=${vapid.publicKey}`;
}

/**
 * Criptografa [plaintext] para a inscrição [sub] ({ keys: { p256dh, auth } }) no formato aes128gcm.
 * [fixed] (só nos testes): { asPrivate, salt } para reproduzir o exemplo oficial da RFC 8291.
 */
function encryptPayload(sub, plaintext, fixed = {}) {
  const uaPublic = fromB64u(sub.keys.p256dh);
  const authSecret = fromB64u(sub.keys.auth);
  if (uaPublic.length !== 65 || uaPublic[0] !== 4) throw new Error('p256dh inválido');
  if (authSecret.length !== 16) throw new Error('auth inválido');

  const ecdh = crypto.createECDH('prime256v1');
  if (fixed.asPrivate) ecdh.setPrivateKey(fromB64u(fixed.asPrivate));
  else ecdh.generateKeys();
  const asPublic = ecdh.getPublicKey();
  const shared = ecdh.computeSecret(uaPublic);
  const salt = fixed.salt ? fromB64u(fixed.salt) : crypto.randomBytes(16);

  const keyInfo = Buffer.concat([Buffer.from('WebPush: info\0'), uaPublic, asPublic]);
  const ikm = Buffer.from(crypto.hkdfSync('sha256', shared, authSecret, keyInfo, 32));
  const cek = Buffer.from(crypto.hkdfSync('sha256', ikm, salt, Buffer.from('Content-Encoding: aes128gcm\0'), 16));
  const nonce = Buffer.from(crypto.hkdfSync('sha256', ikm, salt, Buffer.from('Content-Encoding: nonce\0'), 12));

  const padded = Buffer.concat([Buffer.from(plaintext), Buffer.from([2])]); // 0x02 = último registro
  const cipher = crypto.createCipheriv('aes-128-gcm', cek, nonce);
  const enc = Buffer.concat([cipher.update(padded), cipher.final(), cipher.getAuthTag()]);

  const rs = Buffer.alloc(4);
  rs.writeUInt32BE(4096);
  return Buffer.concat([salt, rs, Buffer.from([asPublic.length]), asPublic, enc]);
}

/** Valida uma inscrição vinda do navegador (nunca confiar no que chega de fora). */
function validSubscription(sub) {
  try {
    if (!sub || typeof sub !== 'object') return null;
    const endpoint = String(sub.endpoint || '');
    if (endpoint.length < 20 || endpoint.length > 600) return null;
    const u = new URL(endpoint);
    if (u.protocol !== 'https:') return null;
    const p256dh = String(sub.keys && sub.keys.p256dh || '');
    const auth = String(sub.keys && sub.keys.auth || '');
    if (fromB64u(p256dh).length !== 65 || fromB64u(auth).length !== 16) return null;
    return { endpoint, keys: { p256dh, auth } };
  } catch (_) {
    return null;
  }
}

/**
 * Envia [payload] (objeto) à inscrição [sub]. Devolve { ok, status, gone } — gone = a inscrição
 * não existe mais (404/410) e deve ser apagada.
 */
async function sendPush(sub, payload, vapid, fetchImpl, nowSec = Math.floor(Date.now() / 1000)) {
  try {
    const body = encryptPayload(sub, JSON.stringify(payload));
    const res = await fetchImpl(sub.endpoint, {
      method: 'POST',
      headers: {
        Authorization: vapidAuthorization(sub.endpoint, vapid, nowSec),
        'Content-Encoding': 'aes128gcm',
        'Content-Type': 'application/octet-stream',
        TTL: '900', // 15 min: lembrete velho não serve
        Urgency: 'high',
      },
      body,
    });
    return { ok: res.status >= 200 && res.status < 300, status: res.status, gone: res.status === 404 || res.status === 410 };
  } catch (_) {
    return { ok: false, status: 0, gone: false };
  }
}

module.exports = { generateVapidKeys, vapidAuthorization, encryptPayload, validSubscription, sendPush, b64u, fromB64u };
