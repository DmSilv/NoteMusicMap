// Gera o par de chaves das notificações (Web Push / VAPID).
//
// Uso:  node scripts/gen_vapid.js
//
// Copie os dois valores para as variáveis de ambiente da Vercel (Settings > Environment Variables):
//   VAPID_PUBLIC_KEY   = (a chave pública)
//   VAPID_PRIVATE_KEY  = (a chave privada, SECRETA: não envie a ninguém nem cole em conversas)
// Depois faça um novo deploy. Opcional: VAPID_SUBJECT (um site ou "mailto:" de contato).
'use strict';

const { generateVapidKeys } = require('../api/_lib/webpush');

const k = generateVapidKeys();
console.log('');
console.log('VAPID_PUBLIC_KEY  =', k.publicKey);
console.log('VAPID_PRIVATE_KEY =', k.privateKey);
console.log('');
console.log('A chave PRIVADA é secreta: coloque só na Vercel. Não envie a ninguém.');
