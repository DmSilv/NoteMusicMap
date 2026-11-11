// Desfaz o vínculo entre um professor e um aluno e apaga tudo o que dependia dele.
// Usado pelo app (ação "unlink" de /api/link) e pelo suporte do painel (/api/admin).
'use strict';

const profiles = require('./profiles');

const U = (c) => `u:${c}`, T = (c) => `ut:${c}`, S = (c) => `us:${c}`, UL = (c) => `ul:${c}`, SS = (c) => `ss:${c}`;
const TK = (c) => `tk:${c}`, VD = (c) => `vd:${c}`, DN = (c) => `dn:${c}`;

/** Apaga os campos de [key] que começam com [prefix]. */
async function wipePrefix(store, key, prefix) {
  for (const f of Object.keys(await store.hgetall(key))) if (f.startsWith(prefix)) await store.hdel(key, f);
}

/**
 * Remove o vínculo [teacher] -> [student] e o que dependia dele (aulas, marcações, decisões,
 * horários pegos). Devolve true se o vínculo existia. Quem chama conta a métrica de vínculos.
 */
async function unlinkPair(store, cmd, teacher, student, now) {
  const hadLink = (await store.hget(T(teacher), student)) !== undefined;
  await store.hdel(T(teacher), student);
  await store.hdel(S(student), teacher);
  await wipePrefix(store, UL(student), `${teacher}:`); // as aulas desse professor deixam de existir para o aluno
  await store.hset(U(teacher), 'kr', String(now));
  await store.hset(U(student), 'kr', String(now));
  if ((await store.hlen(T(teacher))) === 0) await profiles.setRole(cmd, teacher, 't', false, now);
  if ((await store.hlen(S(student))) === 0) await profiles.setRole(cmd, student, 's', false, now);
  await wipePrefix(store, SS(student), `${teacher}:`); // aulas marcadas desse professor para esse aluno
  await wipePrefix(store, DN(teacher), `${student}:`); // marcações de tarefa que esse aluno fez
  const tk = await store.hgetall(TK(teacher)); // horários pegos por esse aluno (libera espaço)
  for (const [sid, who] of Object.entries(tk)) if (who === student) await store.hdel(TK(teacher), sid);
  await wipePrefix(store, VD(student), `${teacher}:`); // decisões do professor sobre as tarefas do aluno
  return hadLink;
}

module.exports = { unlinkPair, wipePrefix };
