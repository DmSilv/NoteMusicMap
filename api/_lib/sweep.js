// Limpeza de perfis abandonados: um perfil SEM vínculo, SEM aluno/professor, SEM horários nem notificações e
// parado há 60 dias é apagado. Quem tem qualquer vínculo ou agenda, e quem foi bloqueado, nunca é apagado.
// Custo: 1 comando quando não há nada para limpar; ~20 por perfil apagado. Falhar aqui não derruba nada.
'use strict';

const profiles = require('./profiles');
const { K } = require('./metrics');

const { Z } = profiles;
const STALE_MS = 60 * 86400000;
const PAGE = 10;
// Todas as chaves que pertencem a um perfil (ver docs/04_API_E_DADOS.md).
const KEYS = (c) => ['u', 'ut', 'us', 'sl', 'ss', 'ul', 'dn', 'vd', 'av', 'tk', 'ps'].map((p) => `${p}:${c}`);
const DATA_KEYS = (c) => ['ut', 'us', 'sl', 'ss', 'av', 'ps', 'ul', 'dn', 'vd', 'tk'].map((p) => `${p}:${c}`);

/** Este perfil pode ser apagado? (sem papel, sem dados, sem bloqueio) */
async function isEmpty(cmd, code) {
  const [prof, ...lens] = await cmd.pipeline([['HMGET', `u:${code}`, 'rt', 'rs', 'bl'], ...DATA_KEYS(code).map((k) => ['HLEN', k])]);
  const [rt, rs, bl] = prof || [];
  if (rt === '1' || rs === '1' || bl === '1') return false;
  return lens.every((n) => !Number(n));
}

/** Apaga até [limit] perfis vazios e parados há mais de 60 dias. Devolve quantos apagou. */
async function sweepEmpty(cmd, now, limit = PAGE, rnd = Math.random) {
  try {
    const cutoff = String(now - STALE_MS);
    const stale = Number(await cmd.cmd(['ZCOUNT', Z.last, '-inf', cutoff])) || 0;
    if (!stale) return 0;
    // Começa num ponto aleatório: perfis parados que têm dados (e ficam) não travam a fila.
    const off = stale <= limit ? 0 : Math.floor(rnd() * (stale - limit + 1));
    const codes = (await cmd.cmd(['ZRANGEBYSCORE', Z.last, '-inf', cutoff, 'LIMIT', String(off), String(limit)])) || [];
    let removed = 0;
    for (const code of codes) {
      if (!(await isEmpty(cmd, code))) continue;
      await cmd.pipeline([...KEYS(code).map((k) => ['DEL', k]), ['SREM', 'pf:bl', code]]);
      await profiles.forget(cmd, code);
      removed++;
    }
    if (removed) await cmd.cmd(['HINCRBY', K.total, 'profiles', String(-removed)]);
    return removed;
  } catch (_) {
    return 0;
  }
}

module.exports = { sweepEmpty, isEmpty, STALE_MS };
