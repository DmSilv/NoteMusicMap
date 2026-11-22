/// Aulas: o professor começa a aula com um aluno, pode pausar, e ao encerrar o
/// que ele passou nela (tarefas e observações) é empacotado para o aluno receber.
/// Dart puro e testável (o relógio é sempre passado de fora).
library;

import 'identity.dart' show formatShareCode;
import 'input_guard.dart';
import 'lesson_week.dart' show fmtLessonDay;
import 'teacher.dart';
import 'i18n.dart';

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
        // 'snt' (enviada) e 'cl' (marcada pelo aluno) são controle do professor: não saem do aparelho.
        'tasks': [for (final t in tasks) (t.toJson()..remove('snt')..remove('cl')..remove('rv'))],
        'notes': notes,
      };

  /// Pacote só de tarefas (sem aula): o professor passou tarefas fora de uma aula.
  bool get tasksOnly => durationSec == 0 && tasks.isNotEmpty;

  /// Pacote só de observações (sem aula e sem tarefas): o professor anotou algo fora de uma aula.
  bool get notesOnly => durationSec == 0 && tasks.isEmpty && notes.isNotEmpty;

  /// "Aula de segunda, 09/11" ou, se foram só tarefas, "Tarefas de segunda, 09/11" (ou "Observações de …").
  String get label => tr('{0} de {1}@@dia', [tasksOnly ? tr('Tarefas') : (notesOnly ? tr('Observações') : tr('Aula')), fmtLessonDay(date)]);

  /// Quem passou: "Marina · K7QM-4TXD" (nome e código), só o código ou "Professor".
  String get teacherLabel {
    final n = teacherName.trim(), c = teacherCode.trim();
    if (n.isNotEmpty && c.isNotEmpty) return '$n · $c';
    if (n.isNotEmpty) return n;
    return c.isNotEmpty ? tr('Professor {0}', [c]) : tr('Professor');
  }

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

/// Observações que vão com uma aula: as feitas durante ela e as que ficaram esperando envio (feitas fora de aula).
/// As que já foram enviadas (sent == true) nunca vão de novo.
List<TeacherNote> lessonNotes(Student s, DateTime start, DateTime end) {
  bool inside(DateTime d) =>
      !d.isBefore(start.subtract(const Duration(seconds: 1))) && !d.isAfter(end.add(const Duration(seconds: 1)));
  return [
    for (final n in s.notes)
      if (n.text.trim().isNotEmpty && n.sent != true && (inside(n.date) || n.sent == false)) n
  ].take(kMaxLessonNotes).toList();
}

/// Observações do aluno que ainda esperam envio (feitas fora de uma aula, mais recentes primeiro).
List<TeacherNote> pendingNotes(Student s) => [
      for (final n in s.notes)
        if (n.sent == false && n.text.trim().isNotEmpty) n
    ];

/// Monta o pacote da aula encerrada: as tarefas e observações criadas entre o início
/// e o fim. Devolve o registro (com o pacote) para o histórico do aluno.
LessonRecord buildLessonRecord(Student s, ActiveLesson l, DateTime end, {String teacherName = ''}) {
  final start = l.startedAt;
  // Folga de 1 s: o relógio das tarefas e o da aula são lidos em instantes diferentes.
  bool inside(DateTime d) =>
      !d.isBefore(start.subtract(const Duration(seconds: 1))) &&
      !d.isAfter(end.add(const Duration(seconds: 1)));
  // Vai com a aula: o que foi passado durante ela e o que ficou esperando envio. O que já
  // foi enviado antes (sent == true) nunca vai de novo.
  final tasks = [
    for (final t in s.tasks)
      if (t.sent != true && (inside(t.created) || t.sent == false)) t
  ].take(kMaxLessonTasks).toList();
  final notes = [for (final n in lessonNotes(s, start, end)) n.text.trim()];
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

/// O número de uma aula para conversar sobre ela ("a aula 7K2M-9QX4"): o mesmo no aparelho do professor e no do aluno.
/// Vem do identificador interno (que nasce do relógio em microssegundos e por isso não se repete): os 8 últimos caracteres, em
/// maiúsculas, em dois grupos de 4.
String lessonDisplayId(String id) {
  final c = id.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  final t = c.length > 8 ? c.substring(c.length - 8) : c.padLeft(8, '0');
  return '${t.substring(0, 4)}-${t.substring(4)}';
}

/// "1 h 05 min", "42 min" ou "3 min 20 s".
String fmtLessonDuration(int seconds) {
  if (seconds >= 3600) {
    final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60;
    return tr('{0} h {1} min', [h, m.toString().padLeft(2, '0')]);
  }
  if (seconds >= 600) return '${seconds ~/ 60} min';
  if (seconds >= 60) return tr('{0} min {1} s', [seconds ~/ 60, (seconds % 60).toString().padLeft(2, '0')]);
  return '$seconds s';
}

/// Ids das tarefas que o pacote [rec] leva (para marcá-las como enviadas).
Set<String> taskIdsOf(LessonRecord rec) => {
      for (final t in (rec.wire?['tasks'] as List? ?? const []))
        if (t is Map && t['id'] is String) t['id'] as String
    };

/// Tarefas do aluno que ainda esperam envio (mais recentes primeiro).
List<Assignment> pendingTasks(Student s) => [
      for (final t in s.tasks)
        if (t.sent == false) t
    ];

/// Pacote só com as tarefas e observações ainda não enviadas, para mandar fora de uma aula. Sai sem
/// duração (durationSec 0): o aluno vê "Tarefas de …" ou "Observações de …" em vez de "Aula de …". Null se não há nada.
LessonRecord? buildTasksPackage(Student s, DateTime now, {String teacherName = '', String? id}) {
  final tasks = pendingTasks(s).take(kMaxLessonTasks).toList();
  final notes = [for (final n in pendingNotes(s).take(kMaxLessonNotes)) n.text.trim()];
  if (tasks.isEmpty && notes.isEmpty) return null;
  final pkgId = id ?? now.microsecondsSinceEpoch.toRadixString(36);
  final pkg = SharedLesson(id: pkgId, atMs: now.millisecondsSinceEpoch, durationSec: 0, tasks: tasks, notes: notes);
  return LessonRecord(
    id: pkgId,
    startedAt: now,
    endedAt: now,
    durationSec: 0,
    taskCount: tasks.length,
    noteCount: notes.length,
    wire: {...pkg.toWire(), if (teacherName.isNotEmpty) 'tn': cleanText(teacherName, max: kMaxName)},
  );
}

/// Como uma tarefa nova chega ao aluno.
enum DeliveryMode {
  /// Há aula em andamento com ele: vai junto quando ela terminar.
  inLesson,

  /// Pode ser enviada agora (a entrega depende só da conexão).
  now,

  /// Pode ser enviada, mas vai ficar na fila (vínculo ligado depois, aluno ainda não vinculado, servidor indisponível).
  queued,

  /// Não há como enviar: sem código ou o aluno encerrou o vínculo. Fica só na ficha.
  localOnly,
}

class TaskDelivery {
  final DeliveryMode mode;
  final String text;
  const TaskDelivery(this.mode, this.text);

  /// Dá para mandar (agora ou na fila) sem estar em aula.
  bool get canSend => mode == DeliveryMode.now || mode == DeliveryMode.queued;
}

/// A regra de entrega das tarefas: em aula, vai com a aula; fora dela, o professor
/// escolhe enviar na hora. Sem código ou com vínculo encerrado, só fica na ficha.
TaskDelivery taskDeliveryFor(
  Student s, {
  required bool inLessonWithThis,
  required bool linkOn,
  required bool serverUp,
  bool studentReady = true,
}) {
  final n = s.name;
  if (inLessonWithThis) {
    return TaskDelivery(DeliveryMode.inLesson, tr('Vai para {0} quando você encerrar a aula.', [n]));
  }
  if (s.code == null) {
    return TaskDelivery(
        DeliveryMode.localOnly,
        tr('{0} não tem código: a tarefa fica só na sua ficha. Para enviar, informe o código dele (menu ⋮ › Código do aluno).', [n]));
  }
  if (s.linkState == 'ended') {
    return TaskDelivery(DeliveryMode.localOnly, tr('{0} encerrou o vínculo: a tarefa fica só na sua ficha.', [n]));
  }
  if (!linkOn) {
    return TaskDelivery(
        DeliveryMode.queued, tr('O vínculo online está desligado: a tarefa fica guardada e vai quando você ligá-lo.'));
  }
  if (!serverUp) {
    return TaskDelivery(
        DeliveryMode.queued, tr('O servidor ainda não recebe tarefas: ela fica guardada e vai quando ficar disponível.'));
  }
  if (s.linkState != 'active') {
    return TaskDelivery(
        DeliveryMode.queued, tr('{0} ainda não está vinculado: a tarefa fica guardada e vai quando ele se vincular.', [n]));
  }
  if (!studentReady) {
    return TaskDelivery(
        DeliveryMode.queued,
        tr('{0} ainda não ligou o "Vínculo online" no app dele: a tarefa fica na fila e chega assim que ele ligar.', [n]));
  }
  return TaskDelivery(DeliveryMode.now, tr('{0} recebe na hora, em Estudo › Tarefas do professor.', [n]));
}

/// Texto do aviso para o aluno quando chegam aulas ou tarefas novas.
String newLessonsMessage(List<SharedLesson> fresh) {
  String who(SharedLesson l) => l.teacherName.trim().isNotEmpty ? l.teacherName.trim() : tr('Seu professor');
  String tasks(int k) => tr('{0} tarefa{1}', [k, k == 1 ? '' : 's']);
  final total = fresh.fold<int>(0, (a, l) => a + l.tasks.length);
  if (fresh.length == 1) {
    final l = fresh.first;
    final k = l.tasks.length;
    if (l.tasksOnly) return tr('{0} passou {1} para você.', [who(l), tasks(k)]);
    if (k > 0) return tr('{0} encerrou a aula e passou {1}.', [who(l), tasks(k)]);
    return l.notes.isNotEmpty
        ? tr('{0} encerrou a aula e deixou observações.', [who(l)])
        : tr('{0} encerrou a aula.', [who(l)]);
  }
  return total > 0
      ? tr('{0} novidades dos seus professores: {1} nova{2}.', [fresh.length, tasks(total), total == 1 ? '' : 's'])
      : tr('{0} novidades dos seus professores.', [fresh.length]);
}

/// Uma marcação de "feita" que o aluno enviou (como o servidor devolve ao professor).
class DoneEntry {
  final String studentCode;
  final String lessonId;
  final String taskId;
  final int atMs;
  const DoneEntry(this.studentCode, this.lessonId, this.taskId, this.atMs);

  static DoneEntry? tryFromWire(Object? j) {
    try {
      final m = (j as Map).cast<String, dynamic>();
      final code = formatShareCode((m['s'] as String?) ?? '');
      final task = (m['k'] as String?) ?? '';
      final lesson = (m['l'] as String?) ?? '';
      if (code == null || !RegExp(r'^[A-Za-z0-9_-]{1,40}$').hasMatch(task)) return null;
      return DoneEntry(code, lesson, task, ((m['t'] as num?)?.toInt() ?? 0).clamp(0, 4102444800000));
    } catch (_) {
      return null;
    }
  }
}

/// Aplica ao aluno [s] as marcações que ele enviou: tarefa marcada passa a "aguardando
/// validação"; tarefa que ele desmarcou perde a marca. O que o professor já validou
/// (done) não muda. Devolve quantas tarefas foram marcadas agora (novidades).
int applyClaims(Student s, Iterable<DoneEntry> mine) {
  final byTask = {for (final e in mine) e.taskId: e};
  var fresh = 0;
  for (var i = 0; i < s.tasks.length; i++) {
    final t = s.tasks[i];
    if (t.done) continue;
    final e = byTask[t.id];
    if (e != null && t.claimedAt == null) {
      s.tasks[i] = t.withClaim(DateTime.fromMillisecondsSinceEpoch(e.atMs == 0 ? DateTime.now().millisecondsSinceEpoch : e.atMs));
      fresh++;
    } else if (e == null && t.claimedAt != null) {
      s.tasks[i] = t.withClaim(null);
    }
  }
  return fresh;
}

/// Tarefas que o aluno marcou como feitas e esperam o professor validar (mais antigas primeiro).
List<Assignment> awaitingValidation(Student s) {
  final l = [for (final t in s.tasks) if (t.awaitsValidation) t];
  l.sort((a, b) => a.claimedAt!.compareTo(b.claimedAt!));
  return l;
}

/// Quanto tempo uma tarefa enviada e não validada continua pedindo uma decisão do professor.
/// Passado isso ela deixa de contar como "para avaliar" (dado antigo não vira um aviso enorme).
const int kReviewWindowDays = 28;

/// O que o professor decide sobre uma tarefa que passou ao aluno.
enum TaskReview {
  /// Está boa: finaliza como feita.
  ok,

  /// Refazer: o aluno vê "refazer" e a tarefa continua pendente.
  back,

  /// Levar para a próxima aula: a tarefa volta a "a enviar" e vai de novo no próximo pacote.
  next,
}

/// Tarefas de [s] que esperam uma decisão do professor: já enviadas ao aluno, ainda não validadas,
/// sem decisão nesta rodada e recentes (mais antigas primeiro). Quem não usa o app do aluno também entra:
/// o aluno não precisa "assinar" nada, o professor é quem confere.
List<Assignment> toReview(Student s, DateTime now) {
  final from = now.subtract(const Duration(days: kReviewWindowDays));
  final l = [
    for (final t in s.tasks)
      if (t.sent == true && !t.done && !t.reviewed && t.created.isAfter(from)) t
  ];
  l.sort((a, b) => a.created.compareTo(b.created));
  return l;
}

/// Um aluno na fila de validação: primeiro o que ELE marcou como feito, depois o resto do que espera decisão.
class ReviewGroup {
  final Student student;

  /// Tarefas que o aluno marcou como feitas (mais antigas marcações primeiro).
  final List<Assignment> marked;

  /// Tarefas enviadas que o aluno não marcou (o professor confere na aula).
  final List<Assignment> others;
  const ReviewGroup(this.student, this.marked, this.others);

  int get total => marked.length + others.length;

  /// Todas, na ordem em que aparecem: marcadas e depois as outras.
  List<Assignment> get all => [...marked, ...others];
}

/// A fila de validação de todos os alunos: só quem tem tarefa esperando decisão. Quem tem tarefa marcada
/// pelo aluno vem antes (mais marcadas primeiro; empate pelo nome); depois os demais, por nome.
List<ReviewGroup> reviewQueue(Iterable<Student> students, DateTime now) {
  final out = <ReviewGroup>[];
  for (final s in students) {
    final list = toReview(s, now);
    if (list.isEmpty) continue;
    final marked = [for (final t in list) if (t.claimedAt != null) t]..sort((a, b) => a.claimedAt!.compareTo(b.claimedAt!));
    final others = [for (final t in list) if (t.claimedAt == null) t];
    out.add(ReviewGroup(s, marked, others));
  }
  out.sort((a, b) {
    final byMarked = b.marked.length.compareTo(a.marked.length);
    if (byMarked != 0) return byMarked;
    return a.student.name.toLowerCase().compareTo(b.student.name.toLowerCase());
  });
  return out;
}

/// Aplica a decisão [r] do professor à tarefa [taskId]. Devolve false se ela não existe.
bool reviewTask(Student s, String taskId, TaskReview r, {DateTime? now}) {
  final i = s.tasks.indexWhere((t) => t.id == taskId);
  if (i < 0) return false;
  final t = s.tasks[i];
  s.tasks[i] = switch (r) {
    TaskReview.ok => t.withClaim(null).copyWith(done: true, reviewed: false),
    TaskReview.back => t.withClaim(null).copyWith(done: false, reviewed: true),
    // Volta a "a enviar" com a data de agora: vai no próximo pacote e conta de novo a partir dele.
    TaskReview.next => t.withClaim(null).copyWith(done: false, reviewed: false, sent: false, created: now ?? DateTime.now()),
  };
  return true;
}

/// Novo pacote (aula ou tarefas) saiu para [s]: o que tinha sido devolvido volta a pedir decisão.
void reopenReviews(Student s) {
  for (var i = 0; i < s.tasks.length; i++) {
    if (s.tasks[i].reviewed) s.tasks[i] = s.tasks[i].copyWith(reviewed: false);
  }
}

/// Valida ([ok] = true: finaliza como feita) ou devolve ([ok] = false: tira a marca e ela volta a ser
/// pendente). Devolve false se a tarefa não existe.
bool validateTask(Student s, String taskId, {required bool ok}) {
  final i = s.tasks.indexWhere((t) => t.id == taskId);
  if (i < 0) return false;
  final t = s.tasks[i];
  s.tasks[i] = ok ? t.copyWith(done: true) : t.withClaim(null);
  return true;
}
