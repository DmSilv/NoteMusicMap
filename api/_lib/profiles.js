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
};
const TOUCH_EVERY = 6 * 3600 * 1000;
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
  await cmd.pipeline([['ZREM', Z.last, code], ['ZREM', Z.born, code], ['ZREM', Z.teach, code], ['ZREM', Z.stud, code]]);
}

module.exports = { Z, TOUCH_EVERY, created, touch, setRole, forget };
