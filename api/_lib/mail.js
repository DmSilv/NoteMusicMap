// Envio de e-mail (só os códigos de verificação da conta). Usa o serviço de e-mail por API (padrão: Resend); a chave e o
// remetente vêm das variáveis de ambiente da Vercel (MAIL_API_KEY ou RESEND_API_KEY, e MAIL_FROM). Sem elas, o recurso
// de e-mail fica desligado e o app esconde as telas dele. NUNCA registra o conteúdo da mensagem (tem o código).
'use strict';

/** O envio de e-mail está configurado? */
function mailEnabled(cfg) {
  return !!(cfg && cfg.mail && cfg.mail.key && cfg.mail.from);
}

/** Envia um e-mail de texto simples. Lança erro se o serviço recusar (quem chama decide o que dizer à pessoa). */
async function sendMail(cfg, fetchImpl, { to, subject, text }) {
  if (!mailEnabled(cfg)) throw new Error('mail-off');
  const r = await fetchImpl(cfg.mail.url, {
    method: 'POST',
    headers: { Authorization: `Bearer ${cfg.mail.key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from: cfg.mail.from, to: [to], subject, text }),
  });
  if (!r.ok) throw new Error('mail ' + r.status);
}

module.exports = { mailEnabled, sendMail };
