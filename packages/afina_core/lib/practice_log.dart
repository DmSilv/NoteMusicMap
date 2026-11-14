/// Diário de prática do aluno: em quais dias ele estudou cada tarefa da aula.
///
/// Quem estuda música pratica a semana toda e só entrega na próxima aula. Por isso a marca
/// de "estudei" é POR DIA (zera sozinha no dia seguinte, porque o dia é outro) e a entrega
/// ("pronta para a aula") é um passo à parte. Dart puro, só no aparelho: nada vai ao servidor.
library;

/// "2026-11-14" (dia civil local; a hora não importa).
String practiceDayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Um dia da fileira dos últimos 7 dias.
class PracticeDay {
  final DateTime date;
  final bool isToday;

  /// Pode marcar: o dia é de hoje ou anterior e a aula já tinha acontecido.
  final bool enabled;
  const PracticeDay(this.date, this.isToday, this.enabled);
}

/// Os 7 dias que terminam hoje (o mais antigo primeiro). Dias antes da aula ([lessonDate]) ficam desligados.
List<PracticeDay> practiceStrip(DateTime now, DateTime lessonDate) {
  final today = _day(now);
  final first = _day(lessonDate);
  return [
    for (var i = 6; i >= 0; i--)
      () {
        final d = today.subtract(Duration(days: i));
        return PracticeDay(d, i == 0, !d.isBefore(first));
      }()
  ];
}

class PracticeLog {
  /// Quantos dias a lembrança guarda (o resto é descartado ao ler/gravar).
  static const int keepDays = 120;

  /// Teto de marcas guardadas (proteção contra dado estragado).
  static const int maxMarks = 4000;

  final Map<String, Set<String>> _days = {};

  /// Chave de uma tarefa de aula: "idAula:idTarefa".
  static String taskKey(String lessonId, String taskId) => '$lessonId:$taskId';

  bool has(String key, DateTime day) => _days[key]?.contains(practiceDayKey(day)) ?? false;

  /// Liga/desliga o dia. Devolve true se ficou marcado.
  bool toggle(String key, DateTime day) {
    final set = _days.putIfAbsent(key, () => <String>{});
    final k = practiceDayKey(day);
    final on = !set.remove(k);
    if (on) set.add(k);
    if (set.isEmpty) _days.remove(key);
    return on;
  }

  /// Em quantos dos 7 dias que terminam em [now] a tarefa foi estudada.
  int countLast7(String key, DateTime now) {
    final set = _days[key];
    if (set == null) return 0;
    final today = _day(now);
    var n = 0;
    for (var i = 0; i < 7; i++) {
      if (set.contains(practiceDayKey(today.subtract(Duration(days: i))))) n++;
    }
    return n;
  }

  /// Alguma tarefa estudada naquele dia.
  bool anyOn(DateTime day) {
    final k = practiceDayKey(day);
    return _days.values.any((s) => s.contains(k));
  }

  /// Dias seguidos estudando. Se hoje ainda não teve marca, a sequência de ontem continua valendo
  /// (o aluno ainda tem o dia todo para estudar).
  int streak(DateTime now) {
    var d = _day(now);
    if (!anyOn(d)) d = d.subtract(const Duration(days: 1));
    var n = 0;
    while (anyOn(d) && n < 3650) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  /// Formato guardado: uma entrada "idAula:idTarefa|2026-11-14" por dia marcado.
  List<String> encode({DateTime? now}) {
    prune(now ?? DateTime.now());
    return [
      for (final e in _days.entries)
        for (final d in e.value) '${e.key}|$d'
    ];
  }

  static PracticeLog decode(Iterable<String> raw, {DateTime? now}) {
    final log = PracticeLog();
    final re = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    var n = 0;
    for (final s in raw) {
      if (n >= maxMarks) break;
      final i = s.lastIndexOf('|');
      if (i <= 0) continue;
      final day = s.substring(i + 1);
      if (!re.hasMatch(day)) continue;
      log._days.putIfAbsent(s.substring(0, i), () => <String>{}).add(day);
      n++;
    }
    log.prune(now ?? DateTime.now());
    return log;
  }

  /// Descarta o que é mais velho que [keepDays].
  void prune(DateTime now) {
    final limit = practiceDayKey(_day(now).subtract(const Duration(days: keepDays)));
    for (final s in _days.values) {
      s.removeWhere((d) => d.compareTo(limit) < 0);
    }
    _days.removeWhere((_, s) => s.isEmpty);
  }

  /// Esquece as marcas de uma tarefa (ex.: aula apagada).
  void forget(String key) => _days.remove(key);

  int get totalMarks => _days.values.fold(0, (a, s) => a + s.length);
}
