/// "Esta semana" do aluno: junta as tarefas das aulas recebidas dos últimos 7 dias e
/// as que ficaram em aberto de aulas mais antigas. Dart puro e testável.
library;

import 'lesson.dart';
import 'teacher.dart';

/// Uma tarefa dentro do plano da semana.
class WeekTask {
  final SharedLesson lesson;
  final Assignment task;
  final bool done;

  /// A aula é de hoje.
  final bool today;

  /// Está em aberto e é de uma aula anterior à mais recente: já devia ter sido feita.
  final bool overdue;
  const WeekTask(this.lesson, this.task, this.done, this.today, this.overdue);
}

/// Tarefas de uma mesma aula.
class WeekGroup {
  final SharedLesson lesson;
  final List<WeekTask> tasks;
  const WeekGroup(this.lesson, this.tasks);

  int get doneCount => tasks.where((t) => t.done).length;
}

class WeekPlan {
  /// Aulas dos últimos 7 dias (mais recente primeiro), só as que têm tarefas.
  final List<WeekGroup> week;

  /// Aulas mais antigas que ainda têm tarefa em aberto (só essas tarefas).
  final List<WeekGroup> late;
  const WeekPlan(this.week, this.late);

  int get total => [...week, ...late].fold(0, (a, g) => a + g.tasks.length);
  int get done => [...week, ...late].fold(0, (a, g) => a + g.doneCount);
  int get open => total - done;
  bool get isEmpty => week.isEmpty && late.isEmpty;

  /// 0..1 (1 se não há nada a fazer).
  double get progress => total == 0 ? 1 : done / total;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Monta o plano. [doneKeys] são as tarefas feitas, no formato "idAula:idTarefa".
/// "Últimos 7 dias" conta de [now] para trás (hoje e os 6 dias anteriores... mais o
/// dia de 7 dias atrás, para a aula "da semana passada, no mesmo dia" ainda aparecer).
WeekPlan buildWeekPlan(List<SharedLesson> lessons, Set<String> doneKeys, DateTime now) {
  final today = _day(now);
  final from = today.subtract(const Duration(days: 7));
  final sorted = [...lessons]..sort((a, b) => b.atMs.compareTo(a.atMs));
  // "Em atraso" conta a partir da última AULA de verdade: tarefas avulsas (passadas fora de
  // aula) não fazem as da aula anterior virarem atraso, mas ficam em atraso quando uma aula nova vem depois.
  final latestLessonAt = sorted.where((l) => !l.tasksOnly).map((l) => l.atMs).firstOrNull;
  bool isDone(SharedLesson l, Assignment t) => doneKeys.contains('${l.id}:${t.id}');

  final week = <WeekGroup>[];
  final late = <WeekGroup>[];
  for (final l in sorted) {
    if (l.tasks.isEmpty) continue;
    final d = _day(l.date);
    final inWeek = !d.isBefore(from);
    final isToday = d == today;
    final tasks = <WeekTask>[];
    for (final t in l.tasks) {
      final done = isDone(l, t);
      // Fora da semana só interessa o que ficou em aberto.
      if (!inWeek && done) continue;
      tasks.add(WeekTask(l, t, done, isToday, !done && latestLessonAt != null && l.atMs < latestLessonAt));
    }
    if (tasks.isEmpty) continue;
    (inWeek ? week : late).add(WeekGroup(l, tasks));
  }
  return WeekPlan(week, late);
}

/// "segunda, 09/11" (o dia da semana em português).
String fmtLessonDay(DateTime d) {
  const days = ['segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'];
  final dd = d.day.toString().padLeft(2, '0'), mm = d.month.toString().padLeft(2, '0');
  return '${days[d.weekday - 1]}, $dd/$mm';
}
