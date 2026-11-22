/// Gamificação do estudo (Dart puro): meta da semana, conquistas e o resumo que o aluno pode mostrar ao professor.
/// Tudo sai dos dados que o aparelho já tem (segundos por dia e escalas feitas); nada é enviado daqui.
library;

import 'dart:math' as math;

import 'i18n.dart';
import 'practice_coach.dart';
import 'study_streak.dart';

/// Meta da semana em minutos: a meta diária em 5 dias de estudo (dá folga no fim de semana).
int weeklyGoalMinutes(double dailyGoalMinutes) => math.max(10, (dailyGoalMinutes * 5).round());

/// Uma conquista: o que é, se já foi ganha e quanto falta (0..1).
class Achievement {
  /// Identificador estável (o app escolhe o ícone por ele).
  final String id;
  final String title;
  final String hint;
  final bool done;
  final double progress;
  const Achievement(this.id, this.title, this.hint, this.done, this.progress);
}

/// Maior sequência de dias estudados (sem perdão) que já aconteceu.
int bestStudyRun(Map<String, double> secs) {
  final days = secs.entries.where((e) => e.value >= kStudyDayMinSeconds).map((e) => e.key).toList()..sort();
  var best = 0, run = 0;
  DateTime? prev;
  for (final k in days) {
    final d = DateTime.tryParse(k);
    if (d == null) continue;
    run = (prev != null && d.difference(prev).inHours.abs() >= 20 && d.difference(prev).inHours.abs() <= 28) ? run + 1 : 1;
    best = math.max(best, run);
    prev = d;
  }
  return best;
}

/// As conquistas, ganhas ou não. Poucas e simples; cada uma diz o que falta.
List<Achievement> achievements({
  required Map<String, double> secs,
  required List<SessionRecord> sessions,
  required DateTime today,
  required double dailyGoalMinutes,
}) {
  final run = bestStudyRun(secs);
  final totalSecs = secs.values.fold<double>(0, (a, b) => a + b);
  final week = weekSummary(secs, today, dailyGoalMinutes);
  final weekGoal = weeklyGoalMinutes(dailyGoalMinutes);
  final bestAcc = sessions.isEmpty ? 0.0 : sessions.map((s) => s.accuracy).reduce(math.max);
  double p(num v, num of) => (v / of).clamp(0, 1).toDouble();
  return [
    Achievement('first', tr('Primeiro estudo'), tr('Estude 1 minuto'), totalSecs >= kStudyDayMinSeconds, p(totalSecs, kStudyDayMinSeconds)),
    Achievement('run3', tr('3 dias seguidos'), tr('Estude 3 dias em sequência'), run >= 3, p(run, 3)),
    Achievement('run7', tr('7 dias seguidos'), tr('Estude 7 dias em sequência'), run >= 7, p(run, 7)),
    Achievement('run30', tr('30 dias seguidos'), tr('Estude 30 dias em sequência'), run >= 30, p(run, 30)),
    Achievement('acc80', tr('Acerto acima de 80%'), tr('Faça uma escala com 80% ou mais de acerto'), bestAcc >= 0.8, p(bestAcc, 0.8)),
    Achievement('week', tr('Meta da semana'), tr('Estude {0} min em 7 dias', [weekGoal]), week.minutes >= weekGoal, p(week.minutes, weekGoal)),
    Achievement('scales10', tr('10 escalas'), tr('Faça 10 escalas guiadas'), sessions.length >= 10, p(sessions.length, 10)),
    Achievement('hours10', tr('10 horas de estudo'), tr('Some 10 horas de estudo'), totalSecs >= 36000, p(totalSecs, 36000)),
  ];
}

/// Segunda-feira da semana de [d], como AAAA-MM-DD.
String weekStartKey(DateTime d) => studyDayKey(DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1)));

/// O resumo da semana que o aluno escolheu mostrar ao professor. Só números e até 3 nomes de notas:
/// `w` início da semana, `m` minutos nos últimos 7 dias, `g` meta da semana, `d` dias estudados, `a` acerto médio
/// nas escalas dos últimos 7 dias (-1 sem escalas), `tk`/`tt` tarefas feitas e total, `n` dias seguidos,
/// `weak` as notas mais desafinadas e `up` a escala que mais melhorou. [noteOf] dá o nome de uma nota (ex.: "Fá#").
Map<String, dynamic> buildStudyShare({
  required Map<String, double> secs,
  required List<SessionRecord> sessions,
  required DateTime today,
  required double dailyGoalMinutes,
  required int tasksDone,
  required int tasksTotal,
  required String Function(int midi) noteOf,
}) {
  final week = weekSummary(secs, today, dailyGoalMinutes);
  final since = DateTime(today.year, today.month, today.day).subtract(const Duration(days: 6));
  final recent = sessions.where((s) => !s.date.isBefore(since)).toList();
  final acc = recent.isEmpty ? -1 : (recent.map((s) => s.accuracy).reduce((a, b) => a + b) / recent.length * 100).round();

  // Notas mais desafinadas: média do desvio (em cents, sem sinal) por nota da escala, com pelo menos 3 leituras.
  final sums = <int, double>{};
  final counts = <int, int>{};
  for (final s in recent) {
    for (final st in s.steps) {
      final c = st.cents;
      if (c == null) continue;
      final pc = st.midi % 12;
      sums[pc] = (sums[pc] ?? 0) + c.abs();
      counts[pc] = (counts[pc] ?? 0) + 1;
    }
  }
  final weak = [
    for (final e in sums.entries)
      if ((counts[e.key] ?? 0) >= 3 && e.value / counts[e.key]! >= 12) MapEntry(e.key, e.value / counts[e.key]!),
  ]..sort((a, b) => b.value.compareTo(a.value));

  // Escala que mais melhorou: a de título repetido cujo último acerto passou do primeiro em pelo menos 3 pontos.
  Map<String, dynamic>? up;
  final byTitle = <String, List<SessionRecord>>{};
  for (final s in sessions.where((s) => !s.date.isBefore(since.subtract(const Duration(days: 7))))) {
    (byTitle[s.title] ??= []).add(s);
  }
  var bestGain = 3;
  byTitle.forEach((t, list) {
    if (list.length < 2) return;
    list.sort((a, b) => a.date.compareTo(b.date));
    final a = (list.first.accuracy * 100).round(), b = (list.last.accuracy * 100).round();
    if (b - a >= bestGain) {
      bestGain = b - a;
      up = {'t': t, 'a': a, 'b': b};
    }
  });

  return {
    'w': weekStartKey(today),
    'm': week.minutes,
    'g': weeklyGoalMinutes(dailyGoalMinutes),
    'd': week.daysStudied,
    'a': acc,
    'tk': tasksDone,
    'tt': tasksTotal,
    'n': studyStreak(secs, today).days,
    'weak': [for (final e in weak.take(3)) noteOf(60 + e.key)],
    if (up != null) 'up': up,
  };
}

/// O resumo da semana de um aluno, como o professor o recebe (resposta de `study_get`). Tudo é limpo na entrada.
class StudyShare {
  final String week; // início da semana (AAAA-MM-DD)
  final int minutes;
  final int goal;
  final int days;
  final int accuracy; // 0..100, -1 = sem escalas
  final int tasksDone;
  final int tasksTotal;
  final int streak;
  final List<String> weak;
  final String upTitle;
  final int upFrom;
  final int upTo;
  final DateTime at;
  const StudyShare({
    required this.week,
    required this.minutes,
    required this.goal,
    required this.days,
    required this.accuracy,
    required this.tasksDone,
    required this.tasksTotal,
    required this.streak,
    required this.weak,
    required this.upTitle,
    required this.upFrom,
    required this.upTo,
    required this.at,
  });

  bool get hasUp => upTitle.isNotEmpty;

  static StudyShare? tryFrom(Object? x) {
    if (x is! Map) return null;
    int i(Object? v, int max, {int min = 0}) => ((v is num ? v.round() : 0)).clamp(min, max);
    final w = x['w'];
    if (w is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(w)) return null;
    final up = x['up'];
    String clean(Object? s, int max) => String.fromCharCodes(('$s').runes.where((r) => r >= 32 && r != 127 && !(r >= 0x200b && r <= 0x200f) && !(r >= 0x202a && r <= 0x202e) && !(r >= 0x2066 && r <= 0x2069))).trim();
    final title = up is Map ? clean(up['t'], 40) : '';
    return StudyShare(
      week: w,
      minutes: i(x['m'], 6000),
      goal: i(x['g'], 6000),
      days: i(x['d'], 7),
      accuracy: i(x['a'], 100, min: -1),
      tasksDone: i(x['tk'], 99),
      tasksTotal: i(x['tt'], 99),
      streak: i(x['n'], 999),
      weak: [
        for (final n in (x['weak'] is List ? x['weak'] as List : const []).take(3))
          if (RegExp(r'^[\p{L}#♯♭0-9]{1,6}$', unicode: true).hasMatch('$n')) '$n'
      ],
      upTitle: title,
      upFrom: up is Map ? i(up['a'], 100) : 0,
      upTo: up is Map ? i(up['b'], 100) : 0,
      at: DateTime.fromMillisecondsSinceEpoch(i(x['at'], 4102444800000)),
    );
  }
}
