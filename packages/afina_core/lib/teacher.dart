/// Área do professor (versão local, sem login): alunos, tarefas, observações,
/// relatórios e troca de dados por texto. Dart puro e testável.
library;

import 'dart:convert';

import 'identity.dart';
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

/// Tipos de tarefa. Só a escala/arpejo é medida pelo app (acerto); as demais o
/// professor marca como feitas.
enum TaskKind {
  scale('Escala ou arpejo'),
  method('Método e lição'),
  repertoire('Repertório'),
  free('Outra atividade');

  final String label;
  const TaskKind(this.label);
}

/// Métodos e livros de estudo comuns (sugestões; o professor digita o que quiser).
const List<String> kMethodSuggestions = [
  'Suzuki',
  'Ševčík',
  'Kayser',
  'Wohlfahrt',
  'Mazas',
  'Schradieck',
  'Kreutzer',
  'Dont',
  'Flesch',
  'Hanon',
];

/// Tarefa passada pelo professor. Para [TaskKind.scale] o app mede o acerto;
/// para método, repertório e outras, [subject] (ex.: "Suzuki · Livro 2") e
/// [detail] (ex.: "Lição 5") descrevem o que estudar. Todas aceitam [note]: a
/// observação livre do professor (o que merece atenção, o que estudar mais).
class Assignment {
  final String id;

  /// Texto mostrado na lista (já com assunto e detalhe).
  final String title;
  final TaskKind kind;
  final String subject; // método, peça ou título
  final String detail; // lição, trecho, compassos…
  final String note;
  final int scaleTypeIndex;
  final int tonicPc; // 0..11
  final int octaves;
  final double goal; // 0..1 (taxa de acerto)
  final bool done;
  final DateTime created;
  const Assignment({
    required this.id,
    required this.title,
    this.kind = TaskKind.scale,
    this.subject = '',
    this.detail = '',
    this.note = '',
    this.scaleTypeIndex = 0,
    this.tonicPc = 0,
    this.octaves = 1,
    this.goal = 0.8,
    this.done = false,
    required this.created,
  });

  bool get isScale => kind == TaskKind.scale;

  /// "Suzuki · Lição 5" (ou só o assunto, se não há detalhe).
  static String titleFor(String subject, String detail) {
    final s = subject.trim(), d = detail.trim();
    if (s.isEmpty) return d;
    return d.isEmpty ? s : '$s · $d';
  }

  Assignment copyWith({bool? done, String? subject, String? detail, String? note}) {
    final sub = subject ?? this.subject;
    final det = detail ?? this.detail;
    return Assignment(
        id: id,
        title: (subject != null || detail != null) && !isScale ? titleFor(sub, det) : title,
        kind: kind,
        subject: sub,
        detail: det,
        note: note ?? this.note,
        scaleTypeIndex: scaleTypeIndex,
        tonicPc: tonicPc,
        octaves: octaves,
        goal: goal,
        done: done ?? this.done,
        created: created);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (!isScale) 'kind': kind.name,
        if (subject.isNotEmpty) 'sub': subject,
        if (detail.isNotEmpty) 'det': detail,
        if (note.isNotEmpty) 'note': note,
        'st': scaleTypeIndex,
        'pc': tonicPc,
        'oct': octaves,
        'goal': goal,
        'done': done,
        'c': created.toIso8601String(),
      };

  static Assignment? tryFrom(Map<String, dynamic> j) {
    try {
      final kindName = j['kind'] as String?;
      final kind = TaskKind.values.where((k) => k.name == kindName).firstOrNull ?? TaskKind.scale;
      return Assignment(
        id: j['id'] as String,
        title: (j['title'] as String?) ?? 'Tarefa',
        kind: kind,
        subject: (j['sub'] as String?) ?? '',
        detail: (j['det'] as String?) ?? '',
        note: (j['note'] as String?) ?? '',
        scaleTypeIndex: (j['st'] as num?)?.toInt() ?? 0,
        tonicPc: ((j['pc'] as num?)?.toInt() ?? 0) % 12,
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

  /// Código de identificação do aluno ("K7QM-4TXD"), se o aluno o informou.
  /// Hoje só identifica o aluno na sua lista; é o gancho para o vínculo
  /// automático (o aluno aceita o convite) quando houver sincronização.
  String? code;

  /// Vínculo online com o aluno: null = só neste aparelho; 'pending' = a enviar quando
  /// houver conexão; 'active' = vinculado dos dois lados; 'ended' = encerrado pelo aluno.
  String? linkState;

  /// Apelido que o aluno informou ao se vincular (para acompanhar mudanças dele).
  String? remoteName;
  final DateTime created;
  final List<TeacherNote> notes; // mais recente primeiro
  final List<Assignment> tasks;
  final List<SessionRecord> sessions; // mais recente primeiro

  Student({
    required this.id,
    required this.name,
    this.code,
    this.linkState,
    this.remoteName,
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
        if (code != null) 'code': code,
        if (linkState != null) 'lk': linkState,
        if (remoteName != null) 'rn': remoteName,
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
        code: formatShareCode((j['code'] as String?) ?? ''),
        linkState: (j['lk'] as String?),
        remoteName: (j['rn'] as String?),
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

/// Problemas encontrados ao cadastrar um aluno (null = sem problema naquele campo).
class StudentEntryCheck {
  final String? name;
  final String? code;
  const StudentEntryCheck(this.name, this.code);
  bool get ok => name == null && code == null;
}

String _nameKey(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Regras de cadastro de aluno (valem ao digitar, ao ler QR, ao editar o código
/// e ao importar):
/// - o código tem de ser válido e **não pode ser o do próprio professor**;
/// - não pode ser o código de um professor do próprio usuário;
/// - o código e o nome não podem repetir os de outro aluno (a não ser que os
///   dois tenham códigos diferentes: aí são pessoas distintas de mesmo nome);
/// - sem código, o nome não pode ser o seu próprio nome de perfil.
/// [exceptId] é o aluno que está sendo editado (ele não conta como repetido).
StudentEntryCheck checkStudentEntry({
  required String name,
  required String codeInput,
  required String ownCode,
  String? ownName,
  Iterable<String> teacherCodes = const [],
  required List<Student> existing,
  String? exceptId,
}) {
  String? codeErr;
  final typed = codeInput.trim();
  final code = typed.isEmpty ? null : formatShareCode(typed);
  if (typed.isNotEmpty) {
    if (code == null) {
      codeErr = 'Código inválido. Ele tem 8 letras e números, como K7QM-4TXD. Confira com o aluno.';
    } else if (code == ownCode) {
      codeErr = 'Este é o seu próprio código: você não pode ser aluno de si mesmo. Peça o código do aluno.';
    } else if (teacherCodes.contains(code)) {
      codeErr = 'Este é o código do seu professor. Ele não pode ser cadastrado como seu aluno.';
    } else {
      for (final s in existing) {
        if (s.id != exceptId && s.code == code) {
          codeErr = 'Este código já é de ${s.name}.';
          break;
        }
      }
    }
  }

  String? nameErr;
  final n = _nameKey(name);
  if (n.isEmpty) {
    nameErr = 'Digite o nome do aluno.';
  } else if (code == null && ownName != null && _nameKey(ownName) == n) {
    nameErr = 'Este é o seu nome. Para estudar você mesmo, use o app normalmente: não precisa se cadastrar '
        'como aluno. Se for outra pessoa com o mesmo nome, acrescente o sobrenome.';
  } else {
    for (final s in existing) {
      if (s.id == exceptId || _nameKey(s.name) != n) continue;
      final bothHaveCodes = code != null && s.code != null;
      if (!bothHaveCodes) {
        nameErr = 'Já existe um aluno com este nome. Acrescente o sobrenome, ou use o código para diferenciar.';
        break;
      }
    }
  }
  return StudentEntryCheck(nameErr, codeErr);
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
      final meta = t.isScale ? ' (meta ${_pct(t.goal)})' : '';
      b.writeln('- ${t.kind == TaskKind.scale ? '' : '${t.kind.label}: '}${t.title}$meta');
      if (t.note.isNotEmpty) b.writeln('  Observação: ${t.note}');
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

/// Junta sessões novas ([extra]) às existentes sem duplicar (mesmo id, ou mesma
/// data e título para dados antigos).
int mergeSessions(List<SessionRecord> into, List<SessionRecord> extra) {
  var added = 0;
  for (final e in extra) {
    final dup = into.any((s) => s.id == e.id || (s.date == e.date && s.title == e.title));
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
