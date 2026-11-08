/// Aulas: o professor começa a aula com um aluno, pode pausar, e ao encerrar o
/// que ele passou nela (tarefas e observações) é empacotado para o aluno receber.
/// Dart puro e testável (o relógio é sempre passado de fora).
library;

import 'input_guard.dart';
import 'teacher.dart';

/// Máximos por aula (valem no app e no servidor).
const int kMaxLessonTasks = 30;
const int kMaxLessonNotes = 10;
const int kMaxLessonKept = 60; // aulas guardadas por aluno

/// Aula em andamento (do lado do professor). Guarda só instantes: o tempo
/// decorrido é calculado na hora, então sobrevive a fechar o app.
class ActiveLesson {
  final String id;
  final String studentId;
  final DateTime startedAt;

  /// Tempo já parado (ms) e, se está pausada agora, desde quando.
  int pausedMs;
  DateTime? pausedAt;

  ActiveLesson({
    required this.id,
    required this.studentId,
    required this.startedAt,
    this.pausedMs = 0,
    this.pausedAt,
  });

  bool get paused => pausedAt != null;

  void pause(DateTime now) => pausedAt ??= now;

  void resume(DateTime now) {
    final p = pausedAt;
    if (p == null) return;
    pausedMs += now.difference(p).inMilliseconds.clamp(0, 1 << 40);
    pausedAt = null;
  }

  /// Tempo de aula de verdade (sem as pausas).
  Duration elapsed(DateTime now) {
    final end = pausedAt ?? now;
    final ms = end.difference(startedAt).inMilliseconds - pausedMs;
    return Duration(milliseconds: ms < 0 ? 0 : ms);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sid': studentId,
        's': startedAt.toIso8601String(),
        'pm': pausedMs,
        if (pausedAt != null) 'pa': pausedAt!.toIso8601String(),
      };

  static ActiveLesson? tryFrom(Object? j) {
    try {
      final m = (j as Map).cast<String, dynamic>();
      return ActiveLesson(
        id: m['id'] as String,
        studentId: m['sid'] as String,
        startedAt: DateTime.parse(m['s'] as String),
        pausedMs: ((m['pm'] as num?)?.toInt() ?? 0).clamp(0, 1 << 40),
        pausedAt: m['pa'] == null ? null : DateTime.parse(m['pa'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

/// O que o aluno recebe de uma aula: quando foi, quanto durou, quem deu, as
/// tarefas que foram passadas e as observações do professor.
class SharedLesson {
  final String id;
  final String teacherCode;
  final String teacherName;

  /// Fim da aula, ms desde 1970.
  final int atMs;
  final int durationSec;
  final List<Assignment> tasks;
  final List<String> notes;

  const SharedLesson({
    required this.id,
    this.teacherCode = '',
    this.teacherName = '',
    required this.atMs,
    this.durationSec = 0,
    this.tasks = const [],
    this.notes = const [],
  });

  DateTime get date => DateTime.fromMillisecondsSinceEpoch(atMs);

  /// Formato que vai para o servidor (e volta dele).
  Map<String, dynamic> toWire() => {
        'id': id,
        't': atMs,
        'd': durationSec,
        'tasks': [for (final t in tasks) t.toJson()],
        'notes': notes,
      };

  /// Lê o formato do servidor, limpando e limitando tudo (o servidor também confere,
  /// mas o app não confia em nada que vem de fora).
  static SharedLesson? tryFromWire(Object? j, {String teacherCode = '', String teacherName = ''}) {
    try {
      final m = (j as Map).cast<String, dynamic>();
      final id = '${m['id']}';
      if (!RegExp(r'^[a-z0-9]{2,40}$').hasMatch(id)) return null;
      final at = (m['t'] as num).toInt().clamp(0, 4102444800000);
      final tasks = <Assignment>[
        for (final x in ((m['tasks'] as List?) ?? const []).take(kMaxLessonTasks))
          ?Assignment.tryFrom((x as Map).cast<String, dynamic>())
      ];
      final notes = <String>[
        for (final x in ((m['notes'] as List?) ?? const []).take(kMaxLessonNotes))
          if (cleanText('$x', max: kMaxNote, multiline: true).isNotEmpty)
            cleanText('$x', max: kMaxNote, multiline: true)
      ];
      return SharedLesson(
        id: id,
        teacherCode: teacherCode.isNotEmpty ? teacherCode : cleanText(m['by'] as String?, max: 12),
        teacherName: teacherName.isNotEmpty ? teacherName : cleanText(m['tn'] as String?, max: kMaxName),
        atMs: at,
        durationSec: ((m['d'] as num?)?.toInt() ?? 0).clamp(0, 86400),
        tasks: tasks,
        notes: notes,
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {...toWire(), 'by': teacherCode, 'tn': teacherName};
}

/// Registro de uma aula no histórico do professor (por aluno).
class LessonRecord {
  final String id;
  final DateTime startedAt;
  final DateTime endedAt;
  final int durationSec;
  final int taskCount;
  final int noteCount;

  /// null = nunca precisou enviar (aluno sem vínculo online); false = a enviar;
  /// true = o servidor aceitou.
  bool? sent;

  /// O pacote pronto (para enviar ou reenviar). Some depois de enviado.
  Map<String, dynamic>? wire;

  LessonRecord({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.durationSec,
    required this.taskCount,
    required this.noteCount,
    this.sent,
    this.wire,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        's': startedAt.toIso8601String(),
        'e': endedAt.toIso8601String(),
        'd': durationSec,
        'nt': taskCount,
        'nn': noteCount,
        if (sent != null) 'sent': sent,
        if (wire != null && sent != true) 'w': wire,
      };

  static LessonRecord? tryFrom(Object? j) {
    try {
      final m = (j as Map).cast<String, dynamic>();
      return LessonRecord(
        id: m['id'] as String,
        startedAt: DateTime.parse(m['s'] as String),
        endedAt: DateTime.parse(m['e'] as String),
        durationSec: ((m['d'] as num?)?.toInt() ?? 0).clamp(0, 86400),
        taskCount: ((m['nt'] as num?)?.toInt() ?? 0).clamp(0, kMaxLessonTasks),
        noteCount: ((m['nn'] as num?)?.toInt() ?? 0).clamp(0, kMaxLessonNotes),
        sent: m['sent'] as bool?,
        wire: m['w'] is Map ? (m['w'] as Map).cast<String, dynamic>() : null,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Monta o pacote da aula encerrada: as tarefas e observações criadas entre o início
/// e o fim. Devolve o registro (com o pacote) para o histórico do aluno.
LessonRecord buildLessonRecord(Student s, ActiveLesson l, DateTime end, {String teacherName = ''}) {
  final start = l.startedAt;
  // Folga de 1 s: o relógio das tarefas e o da aula são lidos em instantes diferentes.
  bool inside(DateTime d) =>
      !d.isBefore(start.subtract(const Duration(seconds: 1))) &&
      !d.isAfter(end.add(const Duration(seconds: 1)));
  final tasks = [
    for (final t in s.tasks)
      if (inside(t.created)) t
  ].take(kMaxLessonTasks).toList();
  final notes = [
    for (final n in s.notes)
      if (inside(n.date) && n.text.trim().isNotEmpty) n.text.trim()
  ].take(kMaxLessonNotes).toList();
  final secs = l.elapsed(end).inSeconds.clamp(0, 86400);
  final pkg = SharedLesson(
    id: l.id,
    atMs: end.millisecondsSinceEpoch,
    durationSec: secs,
    teacherName: teacherName,
    tasks: tasks,
    notes: notes,
  );
  return LessonRecord(
    id: l.id,
    startedAt: start,
    endedAt: end,
    durationSec: secs,
    taskCount: tasks.length,
    noteCount: notes.length,
    wire: {...pkg.toWire(), if (teacherName.isNotEmpty) 'tn': cleanText(teacherName, max: kMaxName)},
  );
}

/// "1 h 05 min", "42 min" ou "3 min 20 s".
String fmtLessonDuration(int seconds) {
  if (seconds >= 3600) {
    final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60;
    return '$h h ${m.toString().padLeft(2, '0')} min';
  }
  if (seconds >= 600) return '${seconds ~/ 60} min';
  if (seconds >= 60) return '${seconds ~/ 60} min ${(seconds % 60).toString().padLeft(2, '0')} s';
  return '$seconds s';
}
