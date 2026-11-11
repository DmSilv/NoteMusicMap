// Índice dos perfis anônimos (código + apelido) para o painel do administrador: quando entrou,
// última atividade, papel (professor / aluno) e bloqueio. NÃO há cadastro nem login.
//
// Custo: 3 comandos quando o perfil nasce; depois, no máximo 1 gravação a cada 6 h por perfil
// ativo (a leitura do perfil já acontece em toda chamada, então checar é de graça).
// Falhar aqui nunca pode derrubar o que o usuário estava fazendo.
'use strict';

const Z = {
  last: 'pf:last', // código -> última atividade (ms)
  born: 'pf:new', // código -> quando entrou (ms)
  teach: 'pf:t', // código -> última atividade, só quem tem alunos
  stud: 'pf:s', // código -> última atividade, só quem tem professor
  on: 'pf:on', // código -> último sinal de vida (presença), de 10 em 10 minutos
  hot: 'pf:hot', // origem+dia -> quando passou de 30 perfis novos (aviso no painel)
};
const TOUCH_EVERY = 6 * 3600 * 1000;
const PRESENCE_EVERY = 10 * 60 * 1000; // no máximo 1 gravação de presença a cada 10 min por perfil
const ONLINE_WINDOW = 12 * 60 * 1000; // "online" = sinal nos últimos 12 min
const PRESENCE_KEEP = 2 * 24 * 3600 * 1000; // quem some há 2 dias sai do índice
const U = (code) => `u:${code}`;

/** Perfil acabou de nascer. */
async function created(cmd, code, now) {
  try {
    await cmd.pipeline([
      ['HSET', U(code), 'ca', String(now)],
      ['HSET', U(code), 'la', String(now)],
      ['ZADD', Z.born, String(now), code],
      ['ZADD', Z.last, String(now), code],
    ]);
  } catch (_) { /* índice não derruba nada */ }
}

/** Registra atividade (no máximo a cada 6 h). Devolve true se gravou. */
async function touch(cmd, prof, code, now) {
  const la = Number(prof.la) || 0;
  if (la && now - la < TOUCH_EVERY) return false;
  try {
    const list = [['HSET', U(code), 'la', String(now)], ['ZADD', Z.last, String(now), code]];
    if (!prof.ca) { // perfil antigo (de antes do índice): conta como visto pela primeira vez agora
      list.push(['HSET', U(code), 'ca', String(now)], ['ZADD', Z.born, String(now), code]);
    }
    if (prof.rt === '1') list.push(['ZADD', Z.teach, String(now), code]);
    if (prof.rs === '1') list.push(['ZADD', Z.stud, String(now), code]);
    await cmd.pipeline(list);
    return true;
  } catch (_) { return false; }
}

/**
 * Sinal de vida: o app à frente com o vínculo ligado consulta o servidor a cada ~30 s; aqui isso vira
 * "visto agora" com no máximo 1 gravação (2 comandos) a cada 10 min por perfil. A leitura do perfil já
 * acontece em toda chamada, então checar é de graça. Só código e horário: nada mais é guardado.
 */
async function seen(cmd, prof, code, now) {
  const pa = Number(prof.pa) || 0;
  if (pa && now - pa < PRESENCE_EVERY) return false;
  try {
    await cmd.pipeline([['HSET', U(code), 'pa', String(now)], ['ZADD', Z.on, String(now), code]]);
    return true;
  } catch (_) { return false; }
}

/** Uma origem passou de 30 perfis novos no dia: guarda para o painel avisar (7 dias). */
async function hot(cmd, key, now) {
  try {
    await cmd.pipeline([['ZADD', Z.hot, String(now), key], ['ZREMRANGEBYSCORE', Z.hot, '-inf', String(now - 7 * 86400000)]]);
  } catch (_) { /* aviso não derruba nada */ }
}

/** Liga ou desliga o papel: kind 't' (tem alunos) ou 's' (tem professor). */
async function setRole(cmd, code, kind, on, now) {
  try {
    const field = kind === 't' ? 'rt' : 'rs';
    const zs = kind === 't' ? Z.teach : Z.stud;
    await cmd.pipeline([
      ['HSET', U(code), field, on ? '1' : '0'],
      on ? ['ZADD', zs, String(now), code] : ['ZREM', zs, code],
    ]);
  } catch (_) { /* ok */ }
}

/** Tira o perfil de todos os índices. */
async function forget(cmd, code) {
  await cmd.pipeline([['ZREM', Z.last, code], ['ZREM', Z.born, code], ['ZREM', Z.teach, code], ['ZREM', Z.stud, code], ['ZREM', Z.on, code]]);
}

module.exports = { Z, TOUCH_EVERY, PRESENCE_EVERY, ONLINE_WINDOW, PRESENCE_KEEP, created, touch, seen, setRole, forget, hot };
