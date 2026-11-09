'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const wp = require('./webpush');

// Exemplo oficial da RFC 8291 (apêndice A).
const RFC = {
  plaintext: 'When I grow up, I want to be a watermelon',
  uaPublic: 'BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4',
  auth: 'BTBZMqHH6r4Tts7J_aSIgg',
  asPrivate: 'yfWPiYE-n46HLnH0KqZOF1fJJU3MYrct3AELtAQ-oRw',
  salt: 'DGv6ra1nlYgDCS1FRnbzlw',
  body:
    'DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_yl95bQpu6cVPTpK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN',
};

test('criptografia aes128gcm bate com o exemplo oficial da RFC 8291', () => {
  const out = wp.encryptPayload({ keys: { p256dh: RFC.uaPublic, auth: RFC.auth } }, RFC.plaintext, { asPrivate: RFC.asPrivate, salt: RFC.salt });
  assert.equal(wp.b64u(out), RFC.body);
});

test('ida e volta: quem tem a chave do navegador consegue abrir a mensagem', () => {
  const ua = crypto.createECDH('prime256v1');
  ua.generateKeys();
  const auth = crypto.randomBytes(16);
  const sub = { keys: { p256dh: wp.b64u(ua.getPublicKey()), auth: wp.b64u(auth) } };
  const body = wp.encryptPayload(sub, JSON.stringify({ kind: 'lesson', start: 123 }));
  // lado do navegador
  const salt = body.subarray(0, 16);
  const idlen = body[20];
  const asPublic = body.subarray(21, 21 + idlen);
  const enc = body.subarray(21 + idlen);
  const shared = ua.computeSecret(asPublic);
  const keyInfo = Buffer.concat([Buffer.from('WebPush: info\0'), ua.getPublicKey(), asPublic]);
  const ikm = Buffer.from(crypto.hkdfSync('sha256', shared, auth, keyInfo, 32));
  const cek = Buffer.from(crypto.hkdfSync('sha256', ikm, salt, Buffer.from('Content-Encoding: aes128gcm\0'), 16));
  const nonce = Buffer.from(crypto.hkdfSync('sha256', ikm, salt, Buffer.from('Content-Encoding: nonce\0'), 12));
  const d = crypto.createDecipheriv('aes-128-gcm', cek, nonce);
  d.setAuthTag(enc.subarray(enc.length - 16));
  const plain = Buffer.concat([d.update(enc.subarray(0, enc.length - 16)), d.final()]);
  assert.equal(plain[plain.length - 1], 2);
  assert.deepEqual(JSON.parse(plain.subarray(0, plain.length - 1).toString()), { kind: 'lesson', start: 123 });
});

test('VAPID: o token é ES256 verificável com a chave pública', () => {
  const keys = wp.generateVapidKeys();
  const auth = wp.vapidAuthorization('https://fcm.googleapis.com/fcm/send/abc', { ...keys, subject: 'https://exemplo.app' }, 1000);
  const m = /^vapid t=([^,]+), k=(.+)$/.exec(auth);
  assert.ok(m);
  assert.equal(m[2], keys.publicKey);
  const [h, c, s] = m[1].split('.');
  assert.equal(JSON.parse(Buffer.from(h, 'base64url')).alg, 'ES256');
  const claims = JSON.parse(Buffer.from(c, 'base64url'));
  assert.equal(claims.aud, 'https://fcm.googleapis.com');
  assert.equal(claims.sub, 'https://exemplo.app');
  assert.equal(claims.exp, 1000 + 12 * 3600);
  const pub = Buffer.from(keys.publicKey, 'base64url');
  const key = crypto.createPublicKey({ key: { kty: 'EC', crv: 'P-256', x: wp.b64u(pub.subarray(1, 33)), y: wp.b64u(pub.subarray(33)) }, format: 'jwk' });
  assert.equal(crypto.verify('sha256', Buffer.from(`${h}.${c}`), { key, dsaEncoding: 'ieee-p1363' }, Buffer.from(s, 'base64url')), true);
});

test('inscrição inválida é recusada (endpoint não https, chaves de tamanho errado)', () => {
  const good = { endpoint: 'https://fcm.googleapis.com/fcm/send/abcdefghij', keys: { p256dh: RFC.uaPublic, auth: RFC.auth } };
  assert.ok(wp.validSubscription(good));
  assert.equal(wp.validSubscription({ ...good, endpoint: 'http://x.example.com/abcdefghijklmnop' }), null);
  assert.equal(wp.validSubscription({ ...good, keys: { p256dh: 'curta', auth: RFC.auth } }), null);
  assert.equal(wp.validSubscription({ ...good, keys: { p256dh: RFC.uaPublic, auth: 'x' } }), null);
  assert.equal(wp.validSubscription(null), null);
  assert.equal(wp.validSubscription({ endpoint: 'lixo' }), null);
});

test('envio: 201 = ok, 410 = inscrição morta (apagar), erro de rede = não derruba', async () => {
  const keys = wp.generateVapidKeys();
  const vapid = { ...keys, subject: 'https://exemplo.app' };
  const sub = { endpoint: 'https://fcm.googleapis.com/fcm/send/abcdefghij', keys: { p256dh: RFC.uaPublic, auth: RFC.auth } };
  let seen;
  const ok = await wp.sendPush(sub, { a: 1 }, vapid, async (url, init) => { seen = { url, init }; return { status: 201 }; });
  assert.equal(ok.ok, true);
  assert.equal(seen.url, sub.endpoint);
  assert.equal(seen.init.headers['Content-Encoding'], 'aes128gcm');
  assert.equal(seen.init.headers.Urgency, 'high');
  assert.ok(Buffer.isBuffer(seen.init.body));
  const gone = await wp.sendPush(sub, { a: 1 }, vapid, async () => ({ status: 410 }));
  assert.equal(gone.gone, true);
  const fail = await wp.sendPush(sub, { a: 1 }, vapid, async () => { throw new Error('rede'); });
  assert.deepEqual({ ok: fail.ok, gone: fail.gone }, { ok: false, gone: false });
});
