/// Área do professor (versão local, sem login): alunos, tarefas, observações,
/// relatórios e troca de dados por texto. Dart puro e testável.
library;

import 'dart:convert';

import 'absence.dart';
import 'identity.dart';
import 'input_guard.dart';
import 'lesson.dart';
import 'practice_coach.dart';
import 'i18n.dart';

class TeacherNote {
  final DateTime date;
  final String text;
  const TeacherNote(this.date, this.text);

  Map<String, dynamic> toJson() => {'d': date.toIso8601String(), 't': text};
  static TeacherNote? tryFrom(Map<String, dynamic> j) {
    try {
      return TeacherNote(DateTime.parse(j['d'] as String),
          cleanText(j['t'] as String?, max: kMaxNote, multiline: true));
    } catch (_) {
      return null;
    }
  }
}

/// Tipos de tarefa. Só a escala/arpejo é medida pelo app (acerto); as demais o
/// professor marca como feitas.
enum TaskKind {
  scale(/*tr*/'Escala ou arpejo'),
  method(/*tr*/'Método e lição'),
  repertoire(/*tr*/'Repertório'),
  free(/*tr*/'Outra atividade'),
  material(/*tr*/'Material do professor');

  final String _label;
  String get label => tr(_label);
  const TaskKind(this._label);
}

/// Métodos e livros de estudo comuns (sugestões; o professor digita o que quiser).
final List<String> kMethodSuggestions = [
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

  /// Só do lado do professor: a tarefa já foi enviada ao aluno (true), ainda não (false)
  /// ou não se aplica / vem de dados antigos (null). Nunca vai para o servidor.
  final bool? sent;

  /// Só do lado do professor: quando o ALUNO marcou como feita (null = não marcou). A tarefa só
  /// passa a "feita" (done) quando o professor valida. Nunca vai para o servidor como parte da tarefa.
  final DateTime? claimedAt;
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
    this.sent,
    this.claimedAt,
  });

  bool get isScale => kind == TaskKind.scale;

  /// "Suzuki · Lição 5" (ou só o assunto, se não há detalhe).
  static String titleFor(String subject, String detail) {
    final s = subject.trim(), d = detail.trim();
    if (s.isEmpty) return d;
    return d.isEmpty ? s : '$s · $d';
  }

  Assignment copyWith({bool? done, String? subject, String? detail, String? note, bool? sent}) {
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
        created: created,
        sent: sent ?? this.sent,
        claimedAt: claimedAt);
  }

  /// Cópia com a marca do aluno ligada ([at]) ou desligada (null).
  Assignment withClaim(DateTime? at) => Assignment(
      id: id,
      title: title,
      kind: kind,
      subject: subject,
      detail: detail,
      note: note,
      scaleTypeIndex: scaleTypeIndex,
      tonicPc: tonicPc,
      octaves: octaves,
      goal: goal,
      done: done,
      created: created,
      sent: sent,
      claimedAt: at);

  /// O aluno marcou como feita e o professor ainda não validou.
  bool get awaitsValidation => claimedAt != null && !done;

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
        if (sent != null) 'snt': sent,
        if (claimedAt != null) 'cl': claimedAt!.toIso8601String(),
      };

  static Assignment? tryFrom(Map<String, dynamic> j) {
    try {
      final kindName = j['kind'] as String?;
      final kind = TaskKind.values.where((k) => k.name == kindName).firstOrNull ?? TaskKind.scale;
      return Assignment(
        id: j['id'] as String,
        title: cleanText((j['title'] as String?) ?? tr('Tarefa'), max: kMaxTitle),
        kind: kind,
        subject: cleanText(j['sub'] as String?, max: kMaxTitle),
        detail: cleanText(j['det'] as String?, max: kMaxLine),
        note: cleanText(j['note'] as String?, max: kMaxNote, multiline: true),
        scaleTypeIndex: (j['st'] as num?)?.toInt() ?? 0,
        tonicPc: ((j['pc'] as num?)?.toInt() ?? 0) % 12,
        octaves: ((j['oct'] as num?)?.toInt() ?? 1).clamp(1, 4),
        goal: ((j['goal'] as num?) ?? 0.8).toDouble().clamp(0.0, 1.0),
        done: j['done'] == true,
        created: DateTime.parse(j['c'] as String),
        sent: j['snt'] as bool?,
        claimedAt: j['cl'] is String ? DateTime.tryParse(j['cl'] as String) : null,
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

  /// Aulas dadas a este aluno, mais recente primeiro.
  final List<LessonRecord> lessons;

  /// Faltas registradas pelo professor, da aula mais recente para a mais antiga.
  List<Absence> absences;

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
    List<LessonRecord>? lessons,
    List<Absence>? absences,
  })  : created = created ?? DateTime.now(),
        absences = absences ?? [],
        lessons = lessons ?? [],
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
        if (lessons.isNotEmpty) 'lessons': [for (final l in lessons) l.toJson()],
        if (absences.isNotEmpty) 'abs': [for (final a in absences) a.toJson()],
      };

  static Student? tryFrom(Map<String, dynamic> j) {
    try {
      return Student(
        id: j['id'] as String,
        name: _nameOr(j['name'] as String?),
        code: formatShareCode((j['code'] as String?) ?? ''),
        linkState: (j['lk'] as String?),
        remoteName: (j['rn'] as String?) == null ? null : cleanText(j['rn'] as String?, max: kMaxName),
        created: DateTime.tryParse((j['c'] as String?) ?? ''),
        notes: [
          for (final n in (j['notes'] as List? ?? const []).take(500))
            ?TeacherNote.tryFrom((n as Map).cast<String, dynamic>())
        ],
        tasks: [
          for (final t in (j['tasks'] as List? ?? const []).take(500))
            ?Assignment.tryFrom((t as Map).cast<String, dynamic>())
        ],
        sessions: [
          for (final s in (j['sessions'] as List? ?? const []).take(1000))
            ?SessionRecord.tryFromJson((s as Map).cast<String, dynamic>())
        ],
        lessons: [for (final l in (j['lessons'] as List? ?? const []).take(200)) ?LessonRecord.tryFrom(l)],
        absences: [for (final a in (j['abs'] as List? ?? const []).take(kMaxAbsences)) ?Absence.tryFrom(a)],
      );
    } catch (_) {
      return null;
    }
  }
}

String _nameOr(String? raw) {
  final n = cleanText(raw, max: kMaxName);
  return n.isEmpty ? tr('Aluno') : n;
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
      codeErr = tr('Código inválido. Ele tem 8 letras e números, como K7QM-4TXD. Confira com o aluno.');
    } else if (code == ownCode) {
      codeErr = tr('Este é o seu próprio código: você não pode ser aluno de si mesmo. Peça o código do aluno.');
    } else if (teacherCodes.contains(code)) {
      codeErr = tr('Este é o código do seu professor. Ele não pode ser cadastrado como seu aluno.');
    } else {
      for (final s in existing) {
        if (s.id != exceptId && s.code == code) {
          codeErr = tr('Este código já é de {0}.', [s.name]);
          break;
        }
      }
    }
  }

  String? nameErr;
  final n = _nameKey(name);
  if (n.isEmpty) {
    nameErr = tr('Digite o nome do aluno.');
  } else if (code == null && ownName != null && _nameKey(ownName) == n) {
    nameErr = tr('Este é o seu nome. Para estudar você mesmo, use o app normalmente: não precisa se cadastrar como aluno. Se for outra pessoa com o mesmo nome, acrescente o sobrenome.');
  } else {
    for (final s in existing) {
      if (s.id == exceptId || _nameKey(s.name) != n) continue;
      final bothHaveCodes = code != null && s.code != null;
      if (!bothHaveCodes) {
        nameErr = tr('Já existe um aluno com este nome. Acrescente o sobrenome, ou use o código para diferenciar.');
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
String studentReport(Student s, {bool? flats = false}) {
  final sum = summarizeStudent(s);
  final b = StringBuffer(tr('Relatório de {0}\n', [s.name]));
  b.writeln(tr('Sessões: {0}', [sum.sessions]));
  if (sum.recentAverage != null) {
    b.writeln(tr('Taxa de acerto média (últimas 5): {0} · melhor: {1}', [_pct(sum.recentAverage!), _pct(sum.best!)]));
    b.writeln(tr('Última sessão: {0}', [_day(sum.last!)]));
    if (sum.trendPoints != null) {
      final t = sum.trendPoints!;
      b.writeln(tr('Tendência: {0}{1} pontos nas últimas 3 sessões', [t >= 0 ? '+' : '', t.round()]));
    }
  }
  final open = s.tasks.where((t) => !t.done).toList();
  if (open.isNotEmpty) {
    b.writeln(tr('\nTarefas em aberto:'));
    for (final t in open) {
      final meta = t.isScale ? tr(' (meta {0})', [_pct(t.goal)]) : '';
      b.writeln('- ${t.kind == TaskKind.scale ? '' : '${t.kind.label}: '}${t.title}$meta');
      if (t.note.isNotEmpty) b.writeln(tr('  Observação: {0}', [t.note]));
    }
  }
  final tips = analyzePractice(s.sessions, flats: flats);
  if (tips.isNotEmpty) {
    b.writeln(tr('\nOrientações:'));
    for (final t in tips) {
      b.writeln('- ${t.text}');
    }
  }
  if (s.notes.isNotEmpty) {
    b.writeln(tr('\nObservações do professor:'));
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
  // Texto enorme não é um aluno: recusa sem nem tentar ler (evita travar o aparelho).
  if (text.length > kMaxBackup) return null;
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
