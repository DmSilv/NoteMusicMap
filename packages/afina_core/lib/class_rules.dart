/// Regra única das aulas: em que fase está cada aula, o que dá para mudar nela e quais aulas
/// entram na agenda mostrada. Hub (Meu espaço), agenda e lembretes usam estas mesmas funções,
/// para nunca mostrarem números ou estados diferentes. Dart puro e testável.
library;

import 'agenda.dart';
import 'i18n.dart';

/// Quantos minutos antes da aula ela passa a ser "começando".
const int kSoonMinutes = 15;

/// Fases de uma aula (uma ocorrência).
enum ClassPhase { upcoming, soon, ongoing, finished }

/// Fase de uma aula que começa em [startMs] e termina em [endMs], vista em [nowMs].
/// O instante do início já é "em andamento"; o instante do fim já é "encerrada".
ClassPhase classPhase(int startMs, int endMs, int nowMs) {
  if (nowMs >= endMs) return ClassPhase.finished;
  if (nowMs >= startMs) return ClassPhase.ongoing;
  if (startMs - nowMs <= kSoonMinutes * kMsMinute) return ClassPhase.soon;
  return ClassPhase.upcoming;
}

String classPhaseLabel(ClassPhase p) => switch (p) {
      ClassPhase.upcoming => '',
      ClassPhase.soon => tr('começa em breve'),
      ClassPhase.ongoing => tr('em andamento'),
      ClassPhase.finished => tr('encerrada'),
    };

/// Quem está olhando para a aula.
enum ClassViewer { teacher, student }

/// O que cada papel pode fazer com UMA aula (ocorrência).
class ClassPermissions {
  /// Mudar horário, duração ou observação.
  final bool edit;

  /// Cancelar só esta aula (de uma regra semanal) ou a aula inteira.
  final bool cancel;

  /// Começar a aula (abrir a ficha e registrar tarefas).
  final bool start;
  const ClassPermissions({this.edit = false, this.cancel = false, this.start = false});
}

/// Regras: só o professor muda ou cancela; aula encerrada não muda (vira histórico);
/// o professor pode começar a aula a partir de [kSoonMinutes] antes até o fim dela.
ClassPermissions classPermissions(ClassViewer who, ClassPhase phase) {
  if (who == ClassViewer.student) return const ClassPermissions();
  return switch (phase) {
    ClassPhase.upcoming => const ClassPermissions(edit: true, cancel: true),
    ClassPhase.soon => const ClassPermissions(edit: true, cancel: true, start: true),
    ClassPhase.ongoing => const ClassPermissions(edit: true, start: true),
    ClassPhase.finished => const ClassPermissions(),
  };
}

/// As aulas do PROFESSOR que valem para mostrar: sem canceladas e só de alunos que ele ainda tem
/// ([knownStudents] = códigos dos alunos). Aula de aluno excluído não aparece em lugar nenhum.
List<ClassSlot> visibleTeacherSlots(Iterable<ClassSlot> slots, Set<String> knownStudents) =>
    [for (final s in slots) if (!s.canceled && knownStudents.contains(s.studentCode)) s];

/// Resumo de um dia para o hub e a agenda: quantas aulas, a próxima e a em andamento.
class DayClasses {
  final List<SlotOccurrence> all;
  final int nowMs;
  const DayClasses(this.all, this.nowMs);

  int get count => all.length;

  /// Aulas que ainda não terminaram.
  List<SlotOccurrence> get remaining => [for (final o in all) if (o.startMs + o.slot.endOffsetMs > nowMs) o];

  SlotOccurrence? get ongoing {
    for (final o in all) {
      if (classPhase(o.startMs, o.startMs + o.slot.endOffsetMs, nowMs) == ClassPhase.ongoing) return o;
    }
    return null;
  }

  SlotOccurrence? get next => remaining.isEmpty ? null : remaining.first;
}

/// As aulas de [slots] no dia local de [now] (para hub e agenda mostrarem o mesmo número).
DayClasses classesToday(Iterable<ClassSlot> slots, DateTime now) =>
    DayClasses(agendaDay(slots, now), now.millisecondsSinceEpoch);
