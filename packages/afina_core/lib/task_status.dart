import 'identity.dart' show formatShareCode;
import 'teacher.dart';

/// Decisão oficial do professor sobre uma tarefa que o aluno marcou como feita.
enum Verdict { ok, back }

/// Como o ALUNO enxerga uma tarefa: o professor é a fonte oficial; "fiz" é só um sinal.
enum StudentTaskState { pending, claimed, validated, returned }

/// Estado de uma tarefa para o aluno.
/// [verdict] vem do professor (null = ainda sem decisão); [claimed] é o "fiz" do aluno.
/// A decisão do professor sempre vale mais que o "fiz": se ele devolveu mas o aluno
/// marcou de novo depois, vale a nova marca ([claimedAfterVerdict]).
StudentTaskState studentTaskState({required bool claimed, Verdict? verdict, bool claimedAfterVerdict = false}) {
  if (verdict == Verdict.ok) return StudentTaskState.validated;
  if (verdict == Verdict.back) {
    return claimed && claimedAfterVerdict ? StudentTaskState.claimed : StudentTaskState.returned;
  }
  return claimed ? StudentTaskState.claimed : StudentTaskState.pending;
}

String studentTaskLabel(StudentTaskState s) => switch (s) {
      StudentTaskState.pending => 'Pendente',
      StudentTaskState.claimed => 'Aguardando o professor',
      StudentTaskState.validated => 'Validada pelo professor',
      StudentTaskState.returned => 'Refazer (devolvida)',
    };

/// Código curto usado no servidor para a decisão.
String verdictWire(Verdict v) => v == Verdict.ok ? 'ok' : 'back';

Verdict? verdictFromWire(Object? s) => s == 'ok' ? Verdict.ok : (s == 'back' ? Verdict.back : null);

/// Resumo do aluno para o professor ao começar a aula (nunca bloqueia nada).
class TaskSummary {
  /// Tarefas que o aluno marcou como feitas e esperam validação.
  final List<Assignment> toValidate;

  /// Tarefas passadas e ainda não feitas (nem marcadas).
  final List<Assignment> pending;

  /// Tarefas já validadas pelo professor.
  final int concluded;
  const TaskSummary({required this.toValidate, required this.pending, required this.concluded});

  int get total => toValidate.length + pending.length + concluded;
  bool get isEmpty => total == 0;

  /// Há algo que o professor precisa decidir agora.
  bool get needsAttention => toValidate.isNotEmpty;

  /// "2 para validar · 1 pendente · 3 concluídas"; vazio se não há tarefas.
  String get line {
    if (isEmpty) return '';
    final parts = <String>[
      if (toValidate.isNotEmpty) '${toValidate.length} para validar',
      if (pending.isNotEmpty) '${pending.length} pendente${pending.length == 1 ? '' : 's'}',
      if (concluded > 0) '$concluded concluída${concluded == 1 ? '' : 's'}',
    ];
    return parts.join(' · ');
  }
}

/// Resumo das tarefas de [s] (mais antigas primeiro dentro de cada grupo).
TaskSummary summarizeTasks(Student s) {
  final toValidate = <Assignment>[], pending = <Assignment>[];
  var concluded = 0;
  for (final t in s.tasks) {
    if (t.done) {
      concluded++;
    } else if (t.awaitsValidation) {
      toValidate.add(t);
    } else {
      pending.add(t);
    }
  }
  toValidate.sort((a, b) => a.claimedAt!.compareTo(b.claimedAt!));
  pending.sort((a, b) => a.created.compareTo(b.created));
  return TaskSummary(toValidate: toValidate, pending: pending, concluded: concluded);
}

/// Uma decisão do professor como o servidor devolve ao aluno.
class VerdictEntry {
  final String teacherCode, lessonId, taskId;
  final Verdict verdict;
  const VerdictEntry(this.teacherCode, this.lessonId, this.taskId, this.verdict);

  /// Chave usada no aparelho do aluno: "professor:aula:tarefa".
  String get key => '$teacherCode:$lessonId:$taskId';

  static VerdictEntry? tryFromWire(Object? j) {
    try {
      final m = (j as Map).cast<String, dynamic>();
      final te = formatShareCode((m['te'] as String?) ?? '');
      final l = (m['l'] as String?) ?? '', k = (m['k'] as String?) ?? '';
      final v = verdictFromWire(m['v']);
      if (te == null || v == null) return null;
      if (!RegExp(r'^[a-z0-9]{2,40}$').hasMatch(l) || !RegExp(r'^[A-Za-z0-9_-]{1,40}$').hasMatch(k)) return null;
      return VerdictEntry(te, l, k, v);
    } catch (_) {
      return null;
    }
  }
}
