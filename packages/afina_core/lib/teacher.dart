/// Área do professor (versão local, sem login): alunos, tarefas, observações,
/// relatórios e troca de dados por texto. Dart puro e testável.
library;

import 'dart:convert';

import 'practice_coach.dart';

class TeacherNote {
  final DateTime date;
  final String text;
  const TeacherNote(this.date, this.text);

  Map<String, dynamic> toJson() => {'d': date.toIso8601String(), 't': text};
  static TeacherNote? tryFrom(Map<String, dynamic> j) {
    try {
      return TeacherNote(DateTime.parse(j['d'] as String), (j['t'] as String?) ?? '');
    } catch (_) {
      return null;
    }
  }
}

/// Tarefa passada pelo professor: tocar uma escala/arpejo e atingir uma meta.
class Assignment {
  final String id;
  final String title;
  final int scaleTypeIndex;
  final int tonicPc; // 0..11
  final int octaves;
  final double goal; // 0..1 (taxa de acerto)
  final bool done;
  final DateTime created;
  const Assignment({
    required this.id,
    required this.title,
    required this.scaleTypeIndex,
    required this.tonicPc,
    required this.octaves,
    required this.goal,
    this.done = false,
    required this.created,
  });

  Assignment copyWith({bool? done}) => Assignment(
      id: id,
      title: title,
      scaleTypeIndex: scaleTypeIndex,
      tonicPc: tonicPc,
      octaves: octaves,
      goal: goal,
      done: done ?? this.done,
      created: created);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'st': scaleTypeIndex,
        'pc': tonicPc,
        'oct': octaves,
        'goal': goal,
        'done': done,
        'c': created.toIso8601String(),
      };

  static Assignment? tryFrom(Map<String, dynamic> j) {
    try {
      return Assignment(
        id: j['id'] as String,
        title: (j['title'] as String?) ?? 'Tarefa',
        scaleTypeIndex: (j['st'] as num).toInt(),
        tonicPc: (j['pc'] as num).toInt() % 12,
        octaves: (j['oct'] as num?)?.toInt() ?? 1,
        goal: ((j['goal'] as num?) ?? 0.8).toDouble().clamp(0.0, 1.0),
        done: j['done'] == true,
        created: DateTime.parse(j['c'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

class Student {
  final String id;
  String name;
  final DateTime created;
  final List<TeacherNote> notes; // mais recente primeiro
  final List<Assignment> tasks;
  final List<SessionRecord> sessions; // mais recente primeiro

  Student({
    required this.id,
    required this.name,
    DateTime? created,
    List<TeacherNote>? notes,
    List<Assignment>? tasks,
    List<SessionRecord>? sessions,
  })  : created = created ?? DateTime.now(),
        notes = notes ?? [],
        tasks = tasks ?? [],
        sessions = sessions ?? [];

  Map<String, dynamic> toJson() => {
        'v': 1,
        'id': id,
        'name': name,
        'c': created.toIso8601String(),
        'notes': [for (final n in notes) n.toJson()],
        'tasks': [for (final t in tasks) t.toJson()],
        'sessions': [for (final s in sessions) s.toJson()],
      };

  static Student? tryFrom(Map<String, dynamic> j) {
    try {
      return Student(
        id: j['id'] as String,
        name: ((j['name'] as String?) ?? 'Aluno').trim(),
        created: DateTime.tryParse((j['c'] as String?) ?? ''),
        notes: [
          for (final n in (j['notes'] as List? ?? const []))
            ?TeacherNote.tryFrom((n as Map).cast<String, dynamic>())
        ],
        tasks: [
          for (final t in (j['tasks'] as List? ?? const []))
            ?Assignment.tryFrom((t as Map).cast<String, dynamic>())
        ],
        sessions: [
          for (final s in (j['sessions'] as List? ?? const []))
            ?SessionRecord.tryFromJson((s as Map).cast<String, dynamic>())
        ],
      );
    } catch (_) {
      return null;
    }
  }
}

class StudentSummary {
  final int sessions;

  /// Média da taxa de acerto das últimas 5 sessões (0..1) ou null.
  final double? recentAverage;
  final double? best;
  final DateTime? last;

  /// Variação (pontos percentuais) das 3 últimas contra as 3 anteriores; null se faltar dado.
  final double? trendPoints;
  const StudentSummary(this.sessions, this.recentAverage, this.best, this.last, this.trendPoints);
}

StudentSummary summarizeStudent(Student s) {
  final v = s.sessions;
  if (v.isEmpty) return const StudentSummary(0, null, null, null, null);
  double mean(Iterable<SessionRecord> r) => r.fold<double>(0, (a, b) => a + b.accuracy) / r.length;
  final recent = v.take(5);
  double? trend;
  if (v.length >= 6) trend = (mean(v.take(3)) - mean(v.skip(3).take(3))) * 100;
  return StudentSummary(v.length, mean(recent), v.map((e) => e.accuracy).reduce((a, b) => a > b ? a : b),
      v.first.date, trend);
}

String _pct(double a) => '${(a * 100).round()}%';
String _day(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Relatório em texto para enviar ao aluno ou guardar.
String studentReport(Student s, {bool flats = false}) {
  final sum = summarizeStudent(s);
  final b = StringBuffer('Relatório de ${s.name}\n');
  b.writeln('Sessões: ${sum.sessions}');
  if (sum.recentAverage != null) {
    b.writeln('Taxa de acerto média (últimas 5): ${_pct(sum.recentAverage!)} · melhor: ${_pct(sum.best!)}');
    b.writeln('Última sessão: ${_day(sum.last!)}');
    if (sum.trendPoints != null) {
      final t = sum.trendPoints!;
      b.writeln('Tendência: ${t >= 0 ? '+' : ''}${t.round()} pontos nas últimas 3 sessões');
    }
  }
  final open = s.tasks.where((t) => !t.done).toList();
  if (open.isNotEmpty) {
    b.writeln('\nTarefas em aberto:');
    for (final t in open) {
      b.writeln('- ${t.title} (meta ${_pct(t.goal)})');
    }
  }
  final tips = analyzePractice(s.sessions, flats: flats);
  if (tips.isNotEmpty) {
    b.writeln('\nOrientações:');
    for (final t in tips) {
      b.writeln('- ${t.text}');
    }
  }
  if (s.notes.isNotEmpty) {
    b.writeln('\nObservações do professor:');
    for (final n in s.notes.take(5)) {
      b.writeln('- ${_day(n.date)}: ${n.text}');
    }
  }
  return b.toString().trimRight();
}

/// Dados do aluno em texto (JSON) para copiar/colar.
String exportStudent(Student s) => jsonEncode(s.toJson());

/// Lê os dados colados; null se não forem válidos.
Student? importStudent(String text) {
  try {
    final j = jsonDecode(text.trim());
    if (j is! Map) return null;
    return Student.tryFrom(j.cast<String, dynamic>());
  } catch (_) {
    return null;
  }
}

/// Junta sessões novas ([extra]) às existentes sem duplicar (mesma data e título).
int mergeSessions(List<SessionRecord> into, List<SessionRecord> extra) {
  var added = 0;
  for (final e in extra) {
    final dup = into.any((s) => s.date == e.date && s.title == e.title);
    if (!dup) {
      into.add(e);
      added++;
    }
  }
  into.sort((a, b) => b.date.compareTo(a.date));
  return added;
}

/// Hash simples (FNV-1a de 32 bits em duas passadas) para a trava do modo
/// professor. Não é segurança forte: só impede que o aluno entre sem querer.
String hashPin(String pin, String salt) {
  int fnv(String s, int seed) {
    var h = seed;
    for (final c in s.codeUnits) {
      h ^= c;
      // 0x01000193 = 2^24 + 0x193; evita estourar os 53 bits de precisão na web.
      h = ((h * 0x193) + (h << 24)) & 0xFFFFFFFF;
    }
    return h;
  }

  final a = fnv('$salt|$pin', 0x811C9DC5);
  final b = fnv('$pin|$salt|${a.toRadixString(16)}', 0x01234567);
  return a.toRadixString(16).padLeft(8, '0') + b.toRadixString(16).padLeft(8, '0');
}
