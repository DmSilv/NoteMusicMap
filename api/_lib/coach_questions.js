'use strict';
// Perguntas que o treinador aceita. O aluno NÃO digita nada: escolhe uma da lista, o app manda só o "id" e o servidor
// monta o texto. Assim ninguém usa a IA como bate-papo livre. O mesmo banco existe no app (packages/afina_core/lib/coach_questions.dart);
// um teste confere que os ids são iguais.

const QUESTIONS = [
  // escalas
  { id: 'esc_porque', theme: 'scales', pt: 'Por que preciso estudar escala?' },
  { id: 'esc_eficaz', theme: 'scales', pt: 'Como estudar escala de forma mais eficiente?' },
  { id: 'esc_tempo', theme: 'scales', pt: 'Quanto tempo de escala vale a pena por dia?' },
  { id: 'esc_lenta', theme: 'scales', pt: 'Devo estudar escala devagar ou rápido?' },
  { id: 'esc_arpejo', theme: 'scales', pt: 'Para que servem os arpejos?' },
  { id: 'esc_ordem', theme: 'scales', pt: 'Em que ordem estudo as escalas?' },
  // afinação
  { id: 'afin_mesma', theme: 'intonation', pt: 'Por que erro a mesma nota?' },
  { id: 'afin_ouvido', theme: 'intonation', pt: 'Como treino o ouvido para afinar sem depender do afinador?' },
  { id: 'afin_agudas', theme: 'intonation', pt: 'Por que as notas agudas desafinam mais?' },
  { id: 'afin_descida', theme: 'intonation', pt: 'Por que desafino mais na descida do que na subida?' },
  { id: 'afin_dedos', theme: 'intonation', pt: 'Como fixo a posição dos dedos?' },
  // rotina
  { id: 'rot_15', theme: 'routine', pt: 'Como estudo bem em 15 minutos?' },
  { id: 'rot_30', theme: 'routine', pt: 'Como organizo um estudo de 30 minutos?' },
  { id: 'rot_const', theme: 'routine', pt: 'Como manter a constância no estudo?' },
  { id: 'rot_aquece', theme: 'routine', pt: 'Como aquecer antes de estudar?' },
  { id: 'rot_metro', theme: 'routine', pt: 'Como usar o metrônomo a meu favor?' },
  { id: 'rot_pausas', theme: 'routine', pt: 'Quando fazer pausas durante o estudo?' },
  { id: 'rot_progresso', theme: 'routine', pt: 'Como saber se estou melhorando?' },
  // aula
  { id: 'aula_ensaiar', theme: 'lesson', pt: 'O que ensaiar antes da próxima aula?' },
  { id: 'aula_tarefa', theme: 'lesson', pt: 'Como estudar a tarefa que o professor passou?' },
  { id: 'aula_duvida', theme: 'lesson', pt: 'Como levar minhas dúvidas para a aula?' },
];

/** Perguntas dos apps antigos (texto livre no resumo): em português e em inglês. */
const LEGACY = [
  'Por que erro a mesma nota?',
  'Como estudo bem em 15 minutos?',
  'O que ensaiar antes da próxima aula?',
  'Why do I miss the same note?',
  'How do I study well in 15 minutes?',
  'What should I rehearse before the next lesson?',
];

const BY_ID = new Map(QUESTIONS.map((q) => [q.id, q]));
const byId = (id) => BY_ID.get(String(id)) || null;

/** A primeira linha do resumo é uma das perguntas antigas? */
function legacyMatch(summary) {
  const first = String(summary).split('\n').map((l) => l.trim()).find(Boolean) || '';
  const body = first.replace(/^[^:\n]{3,40}:\s*/, '').trim();
  return LEGACY.includes(body);
}

/** Tira do resumo a linha "Pergunta do aluno: ..." (o servidor põe a dele). */
function withoutQuestionLine(summary) {
  const lines = String(summary).split('\n');
  const i = lines.findIndex((l) => l.trim());
  if (i >= 0 && /^(Pergunta do aluno|Student's question):/i.test(lines[i].trim())) lines.splice(i, 1);
  return lines.join('\n').trim();
}

module.exports = { QUESTIONS, LEGACY, byId, legacyMatch, withoutQuestionLine };
