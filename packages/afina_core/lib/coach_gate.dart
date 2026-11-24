/// Quando o treinador (IA) abre e quais perguntas ele oferece. Dart puro e testável.
///
/// A IA custa (e tem limite grátis), então ela só abre para quem já estudou de verdade no app: [kCoachUnlockMinutes] minutos de
/// estudo somados. Antes disso a pessoa vê quanto falta e as dicas do dia, que são calculadas no aparelho e não gastam IA.
library;

import 'i18n.dart';

/// Minutos de estudo (somados, em qualquer ferramenta do app) para o treinador abrir.
const int kCoachUnlockMinutes = 60;

/// Sessões de exercício que um aluno precisa ter para o professor pedir o relatório com IA.
const int kReportMinSessions = 3;

class CoachGate {
  /// Minutos estudados no total.
  final int minutes;

  /// Quem já usou o treinador antes desta regra continua com ele aberto.
  final bool grandfathered;
  const CoachGate({required this.minutes, this.grandfathered = false});

  bool get open => grandfathered || minutes >= kCoachUnlockMinutes;
  int get left => open ? 0 : kCoachUnlockMinutes - minutes;
  double get progress => open ? 1 : (minutes / kCoachUnlockMinutes).clamp(0.0, 1.0);
}

/// [studySeconds] é o mapa dia → segundos de estudo; [grandfathered] vale para quem já tem plano ou histórico.
CoachGate coachGate({required Map<String, double> studySeconds, bool grandfathered = false}) {
  var secs = 0.0;
  for (final v in studySeconds.values) {
    if (v > 0) secs += v;
  }
  return CoachGate(minutes: (secs / 60).floor(), grandfathered: grandfathered);
}

/// Uma pergunta que o treinador aceita. O aluno só escolhe; o app manda o [id] e o servidor monta o texto.
class CoachQuestion {
  final String id;
  final String theme;
  final String text;
  const CoachQuestion(this.id, this.theme, this.text);
}

/// O banco de perguntas (os mesmos ids de `api/_lib/coach_questions.js`; um teste da API confere).
List<CoachQuestion> get coachQuestionBank => [
      CoachQuestion('esc_porque', 'scales', tr('Por que preciso estudar escala?')),
      CoachQuestion('esc_eficaz', 'scales', tr('Como estudar escala de forma mais eficiente?')),
      CoachQuestion('esc_tempo', 'scales', tr('Quanto tempo de escala vale a pena por dia?')),
      CoachQuestion('esc_lenta', 'scales', tr('Devo estudar escala devagar ou rápido?')),
      CoachQuestion('esc_arpejo', 'scales', tr('Para que servem os arpejos?')),
      CoachQuestion('esc_ordem', 'scales', tr('Em que ordem estudo as escalas?')),
      CoachQuestion('afin_mesma', 'intonation', tr('Por que erro a mesma nota?')),
      CoachQuestion('afin_ouvido', 'intonation', tr('Como treino o ouvido para afinar sem depender do afinador?')),
      CoachQuestion('afin_agudas', 'intonation', tr('Por que as notas agudas desafinam mais?')),
      CoachQuestion('afin_descida', 'intonation', tr('Por que desafino mais na descida do que na subida?')),
      CoachQuestion('afin_dedos', 'intonation', tr('Como fixo a posição dos dedos?')),
      CoachQuestion('rot_15', 'routine', tr('Como estudo bem em 15 minutos?')),
      CoachQuestion('rot_30', 'routine', tr('Como organizo um estudo de 30 minutos?')),
      CoachQuestion('rot_const', 'routine', tr('Como manter a constância no estudo?')),
      CoachQuestion('rot_aquece', 'routine', tr('Como aquecer antes de estudar?')),
      CoachQuestion('rot_metro', 'routine', tr('Como usar o metrônomo a meu favor?')),
      CoachQuestion('rot_pausas', 'routine', tr('Quando fazer pausas durante o estudo?')),
      CoachQuestion('rot_progresso', 'routine', tr('Como saber se estou melhorando?')),
      CoachQuestion('aula_ensaiar', 'lesson', tr('O que ensaiar antes da próxima aula?')),
      CoachQuestion('aula_tarefa', 'lesson', tr('Como estudar a tarefa que o professor passou?')),
      CoachQuestion('aula_duvida', 'lesson', tr('Como levar minhas dúvidas para a aula?')),
    ];

/// As perguntas de hoje: [count] por dia, sempre as mesmas no mesmo dia (não muda a cada abertura) e mudando de um dia para o outro.
/// Evita as feitas há pouco ([recent]) e, quando dá, mistura temas. Sem sessões gravadas não oferece as perguntas sobre "as minhas notas";
/// sem professor não oferece as de aula.
List<CoachQuestion> pickCoachQuestions({
  required DateTime day,
  Set<String> recent = const {},
  bool hasSessions = false,
  bool hasTeacher = false,
  int count = 3,
}) {
  bool allowed(CoachQuestion q) {
    if (!hasSessions && (q.id == 'afin_mesma' || q.id == 'afin_agudas' || q.id == 'afin_descida')) return false;
    if (!hasTeacher && q.theme == 'lesson') return false;
    return true;
  }

  final pool = [for (final q in coachQuestionBank) if (allowed(q)) q];
  var seed = day.year * 10000 + day.month * 100 + day.day;
  int next() {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed;
  }

  final shuffled = [...pool];
  for (var i = shuffled.length - 1; i > 0; i--) {
    final j = next() % (i + 1);
    final t = shuffled[i];
    shuffled[i] = shuffled[j];
    shuffled[j] = t;
  }
  // as feitas há pouco vão para o fim (só voltam se faltar pergunta)
  final fresh = [for (final q in shuffled) if (!recent.contains(q.id)) q];
  final stale = [for (final q in shuffled) if (recent.contains(q.id)) q];
  final ordered = [...fresh, ...stale];
  final out = <CoachQuestion>[];
  final themes = <String>{};
  for (final q in ordered) {
    if (out.length >= count) break;
    if (themes.add(q.theme)) out.add(q);
  }
  for (final q in ordered) {
    if (out.length >= count) break;
    if (!out.contains(q)) out.add(q);
  }
  return out;
}
