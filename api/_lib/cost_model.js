// Quanto custa manter a plataforma: projeção de gastos por número de usuários. Função pura (sem rede, sem Redis), usada pelo
// painel (aba Custos › Contas) e testada em api/cost_model.test.js.
//
// De onde vêm os números:
//  - PRICES: preços de tabela dos serviços (conferir nos sites; mudam). Vale para o plano pago "pay as you go".
//  - SIM: consumo por usuário ATIVO no mês, medido pela simulação `node scripts/simulate_load.js` (handlers de verdade, usuários
//    fictícios). O painel também calcula o consumo REAL (dos contadores dos últimos 30 dias) e o usuário escolhe qual usar.
// Limites do modelo: não mede velocidade nem limites reais de rede; assume uma visita de ~12 minutos e 35% de uso diário.
'use strict';

const PRICES = {
  asOf: '2026-11-12',
  source: 'Tabelas públicas de upstash.com (Redis e QStash) e vercel.com, consultadas em 12/11/2026. Confira antes de decidir: os preços mudam.',
  redis: { freeCommands: 500000, usdPer100kCommands: 0.2 },
  qstash: { freeMessagesPerDay: 1000, usdPer100kMessages: 1 },
  vercel: {
    proUsdPerMonth: 20,
    includedInvocations: 1000000, // chamadas de função incluídas no Pro
    usdPerMillionInvocations: 0.6,
    hobbyInvocationsLow: 100000, // algumas fontes dizem 100 mil no Hobby; outras, 1 milhão
    hobbyBandwidthGB: 100,
    proBandwidthGB: 1000,
    usdPerGBOver: 0.15,
  },
  oneOff: [
    { name: 'Google Play (conta de desenvolvedor)', usd: 25, when: 'uma vez (já paga)' },
    { name: 'Apple Developer (App Store)', usd: 99, when: 'por ano (opcional)' },
    { name: 'Domínio próprio (opcional)', usd: 12, when: 'por ano (hoje usa notemusicmap.vercel.app, grátis)' },
  ],
};

/** Consumo por usuário ativo no mês, medido na simulação de carga (scripts/simulate_load.js, 300 usuários, 30 dias). */
const SIM = {
  asOf: '2026-11-12',
  commandsPerUser: 387,
  callsPerUser: 136,
  remindersPerUser: 3.4,
  mbPerUser: 16, // abrir o app (~10 MB na 1ª vez, depois quase tudo vem do cache) e ~20 aberturas
};

const round = (n, d = 2) => { const k = 10 ** d; return Math.round((Number(n) || 0) * k) / k; };

/** Preço do mês para um consumo total. */
function price({ commands, calls, reminders, users, mb }, { commercial = false, fx = 5.5 } = {}) {
  const P = PRICES;
  const bandwidthGB = ((mb || 0) * (users || 0)) / 1024;
  const alerts = [];
  const items = [];

  const overCmd = Math.max(0, commands - P.redis.freeCommands);
  const redisUsd = (overCmd / 100000) * P.redis.usdPer100kCommands;
  items.push({ key: 'redis', name: 'Banco de dados (Upstash Redis)', plan: overCmd ? 'Pay as you go' : 'Grátis', usd: round(redisUsd), detail: `${Math.round(commands).toLocaleString('pt-BR')} comandos no mês (grátis até ${P.redis.freeCommands.toLocaleString('pt-BR')})` });
  if (commands >= P.redis.freeCommands * 0.8 && !overCmd) alerts.push('O banco está perto do limite grátis (80% ou mais).');
  if (overCmd) alerts.push('O banco passa do limite grátis: precisa mudar para o plano pago (pay as you go) no Upstash, ou o app para de gravar.');

  const perDay = reminders / 30;
  const qOverMsgs = Math.max(0, reminders - P.qstash.freeMessagesPerDay * 30);
  items.push({ key: 'qstash', name: 'Lembretes das aulas (Upstash QStash)', plan: qOverMsgs ? 'Pay as you go' : 'Grátis', usd: round((qOverMsgs / 100000) * P.qstash.usdPer100kMessages), detail: `${Math.round(reminders).toLocaleString('pt-BR')} lembretes no mês, média de ${round(perDay, 1)} por dia (grátis até ${P.qstash.freeMessagesPerDay}/dia)` });
  if (perDay > P.qstash.freeMessagesPerDay * 0.8) alerts.push('Os lembretes estão perto do limite diário grátis do QStash.');

  const needsPro = calls > P.vercel.includedInvocations || commercial;
  let vercelUsd = 0;
  if (needsPro) {
    vercelUsd = P.vercel.proUsdPerMonth + (Math.max(0, calls - P.vercel.includedInvocations) / 1e6) * P.vercel.usdPerMillionInvocations
      + Math.max(0, bandwidthGB - P.vercel.proBandwidthGB) * P.vercel.usdPerGBOver;
  }
  items.push({ key: 'vercel', name: 'Hospedagem do site e das funções (Vercel)', plan: needsPro ? 'Pro' : 'Hobby (grátis)', usd: round(vercelUsd), detail: `${Math.round(calls).toLocaleString('pt-BR')} chamadas de função no mês · ~${round(bandwidthGB, 1)} GB de tráfego` });
  if (commercial) alerts.push('O plano Hobby da Vercel é só para uso não comercial: se o app gerar receita (anúncios, assinatura), é preciso o Pro.');
  if (!needsPro && calls > P.vercel.hobbyInvocationsLow) alerts.push(`Acima de ${P.vercel.hobbyInvocationsLow.toLocaleString('pt-BR')} chamadas de função o plano Hobby pode bloquear (as fontes divergem: de 100 mil a 1 milhão). Confira o limite na sua conta da Vercel.`);
  if (!needsPro && bandwidthGB > P.vercel.hobbyBandwidthGB * 0.8) alerts.push('O tráfego está perto do limite do plano Hobby da Vercel.');
  if (!needsPro && calls > P.vercel.includedInvocations) alerts.push('Passou do que o plano Hobby da Vercel inclui: precisa do Pro.');

  items.push({ key: 'ai', name: 'Respostas da IA (provedores de IA)', plan: 'Variável', usd: 0, detail: 'Grátis enquanto dentro das cotas dos provedores; acima disso o preço depende do provedor e não está somado aqui' });

  const totalUsd = round(items.reduce((s, x) => s + x.usd, 0));
  return { items, alerts, totalUsd, totalBrl: round(totalUsd * fx), perUserUsd: users ? round(totalUsd / users, 4) : 0, perUserBrl: users ? round((totalUsd * fx) / users, 4) : 0, commands: Math.round(commands), calls: Math.round(calls), reminders: Math.round(reminders), bandwidthGB: round(bandwidthGB, 1), needsPro };
}

/** Projeção para [users] usuários ativos por mês, dado o consumo por usuário [per]. */
function project(users, per, opts = {}) {
  const u = Math.max(1, Math.round(users));
  return { users: u, ...price({ commands: u * per.commandsPerUser, calls: u * per.callsPerUser, reminders: u * per.remindersPerUser, users: u, mb: per.mbPerUser }, opts) };
}

/**
 * Relatório completo.
 * measured: { users30, commands, calls, reminders } dos últimos 30 dias (do painel); users: cenário escolhido; basis: 'real' | 'sim'.
 */
function report({ measured, users = 1000, fx = 5.5, basis = 'sim', commercial = false } = {}) {
  const f = Math.min(20, Math.max(1, Number(fx) || 5.5));
  const m = measured || {};
  const u30 = Math.max(0, Number(m.users30) || 0);
  const realOk = u30 >= 30 && Number(m.commands) > 0;
  const real = realOk
    ? { commandsPerUser: round(m.commands / u30, 1), callsPerUser: round((m.calls || 0) / u30, 1), remindersPerUser: round((m.reminders || 0) / u30, 2), mbPerUser: SIM.mbPerUser }
    : null;
  const used = basis === 'real' && real ? real : SIM;
  const usedName = basis === 'real' && real ? 'real' : 'sim';
  const opts = { commercial: !!commercial, fx: f };
  const list = [...new Set([Math.max(1, Math.round(Number(users) || 1000)), 100, 1000, 5000, 10000])].sort((a, b) => a - b);
  const now = u30 > 0 || m.commands > 0
    ? price({ commands: Number(m.commands) || 0, calls: Number(m.calls) || 0, reminders: Number(m.reminders) || 0, users: u30, mb: SIM.mbPerUser }, opts)
    : null;
  return {
    prices: { asOf: PRICES.asOf, source: PRICES.source, oneOff: PRICES.oneOff },
    fx: f, basis: usedName, realAvailable: !!real,
    perUser: { sim: SIM, real, used },
    now: now ? { users30: u30, ...now } : null,
    scenarios: list.map((n) => project(n, used, opts)),
    custom: Math.max(1, Math.round(Number(users) || 1000)),
    notes: [
      'Cada usuário ativo = alguém que abriu o app nos últimos 30 dias.',
      'A projeção multiplica o consumo por usuário: não considera descontos, impostos, nem picos (um dia de muito acesso pode gastar mais).',
      'Valores em dólar (preço de tabela dos serviços) e em reais pela cotação informada.',
    ],
  };
}

module.exports = { PRICES, SIM, price, project, report };
