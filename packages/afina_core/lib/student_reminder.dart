/// Lembretes que o PROFESSOR manda pelo WhatsApp: número do aluno (fica só no aparelho do professor), mensagens amigáveis,
/// quem pode precisar de um empurrãozinho e os dias em que o professor quer ser lembrado de lembrar. Dart puro e testável.
///
/// Nada aqui envia mensagem sozinho: o WhatsApp não deixa um site enviar por conta própria. O app prepara o texto,
/// abre a conversa e quem envia é o professor.
library;

import 'gamify.dart';
import 'i18n.dart';
import 'teacher.dart';

/// Limpa o número digitado e devolve no formato do WhatsApp (só dígitos, com o país), ou null se não parece um número.
/// Brasil: DDD + número (10 ou 11 dígitos) ganha o 55. Outro país: começa com "+".
String? cleanWhatsNumber(String input) {
  final raw = input.trim();
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (RegExp(r'[^0-9+()\s.\-]').hasMatch(raw)) return null;
  if (raw.startsWith('+')) return digits.length >= 8 && digits.length <= 15 ? digits : null;
  if ((digits.length == 12 || digits.length == 13) && digits.startsWith('55')) return digits;
  if (digits.length == 10 || digits.length == 11) {
    final ddd = int.parse(digits.substring(0, 2));
    return ddd >= 11 && ddd <= 99 ? '55$digits' : null;
  }
  return null;
}

/// O número para mostrar: "+55 13 91234-5678" no Brasil; "+1234567890" nos outros.
String whatsLabel(String number) {
  if (number.startsWith('55') && (number.length == 12 || number.length == 13)) {
    final ddd = number.substring(2, 4);
    final rest = number.substring(4);
    return '+55 $ddd ${rest.substring(0, rest.length - 4)}-${rest.substring(rest.length - 4)}';
  }
  return '+$number';
}

/// Endereço que abre o WhatsApp com [text] pronto. Sem [number], o WhatsApp pergunta para quem enviar.
Uri whatsUri(String? number, String text) => Uri.parse('https://wa.me/${number ?? ''}?text=${Uri.encodeComponent(text)}');

String _short(String s) {
  final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.length <= 60 ? t : '${t.substring(0, 59)}…';
}

/// Mensagens amigáveis para escolher. Com tarefas em aberto citam até três; sem tarefas, só o convite.
List<String> reminderMessages(String firstName, List<String> openTasks) {
  final tasks = [for (final t in openTasks) if (t.trim().isNotEmpty) _short(t)].take(3).toList();
  if (tasks.isEmpty) {
    return [
      studyReminderPlain(firstName),
      tr('Oi, {0}! Tudo bem? Que tal pegar o instrumento por 15 minutinhos hoje? Um pouco todo dia faz muita diferença 🎻', [firstName]),
      tr('{0}, passando para te animar: abre o app, toca uma escala com calma e me conta como foi. Estou torcendo por você! 😊', [firstName]),
    ];
  }
  final list = tasks.join(', ');
  return [
    tr('Oi, {0}! Ficou para estudar: {1}. Consegue separar uns 15 minutos hoje? Qualquer dúvida, é só me chamar.', [firstName, list]),
    tr('Oi, {0}! Tudo bem? Que tal estudarmos hoje uns 20 minutos? Dá uma olhada no app: {1}. Vai com calma, o importante é praticar 🎻', [firstName, list]),
    tr('{0}, passando para te animar! Suas tarefas te esperam no app: {1}. Um pedacinho hoje já ajuda muito. Se travar em algo, me chama 😊', [firstName, list]),
  ];
}

/// O convite simples, sem tarefas.
String studyReminderPlain(String firstName) => tr('Oi, {0}! Que tal separar 15 minutos hoje para estudar? Qualquer dúvida, é só me chamar.', [firstName]);

// ---------------- quem pode precisar de um empurrãozinho ----------------

enum NudgeReason { scheduled, tasks, study }

class NudgeSuggestion {
  final Student student;
  final NudgeReason reason;

  /// tasks: há quantos dias a tarefa mais recente está em aberto. study: minutos estudados na semana.
  final int value;
  const NudgeSuggestion(this.student, this.reason, this.value);

  String get label => switch (reason) {
        NudgeReason.scheduled => tr('Hoje é dia de lembrar'),
        NudgeReason.tasks => value == 1 ? tr('Tarefa em aberto há 1 dia') : tr('Tarefa em aberto há {0} dias', [value]),
        NudgeReason.study => tr('Estudou {0} min nesta semana', [value]),
      };
}

/// Depois de lembrar um aluno, ele sai da lista por este tempo (para não insistir).
const int kNudgeRestDays = 3;

/// Tarefa em aberto há pelo menos estes dias, sem o aluno marcar nenhuma nesse período, vira sugestão.
const int kNudgeTaskDays = 3;

/// Menos que estes minutos na semana (só para quem COMPARTILHA o estudo) vira sugestão.
const int kNudgeStudyMinutes = 20;

int _daysBetween(DateTime a, DateTime b) => DateTime(b.year, b.month, b.day).difference(DateTime(a.year, a.month, a.day)).inDays;

/// Os alunos que podem precisar de um empurrãozinho. Usa só o que o professor já vê: as tarefas que passou, o que o aluno
/// marcou como feito e, só para quem escolheu compartilhar, o resumo de estudo. Não olha se o aluno abriu o app.
List<NudgeSuggestion> whoNeedsNudge(Iterable<Student> students, DateTime now, {Map<String, StudyShare> shares = const {}}) {
  final out = <NudgeSuggestion>[];
  for (final s in students) {
    if (s.paused) continue;
    final last = s.remindedMs == null ? null : DateTime.fromMillisecondsSinceEpoch(s.remindedMs!);
    if (s.remindDays.contains(now.weekday) && (last == null || _daysBetween(last, now) >= 1)) {
      out.add(NudgeSuggestion(s, NudgeReason.scheduled, 0));
      continue;
    }
    if (last != null && _daysBetween(last, now) < kNudgeRestDays) continue;
    final open = [for (final t in s.tasks) if (!t.done && t.claimedAt == null) t];
    final claimedRecently = s.tasks.any((t) => t.claimedAt != null && _daysBetween(t.claimedAt!, now) < kNudgeTaskDays);
    if (open.isNotEmpty && !claimedRecently) {
      final newest = open.map((t) => t.created).reduce((a, b) => a.isAfter(b) ? a : b);
      final days = _daysBetween(newest, now);
      if (days >= kNudgeTaskDays) {
        out.add(NudgeSuggestion(s, NudgeReason.tasks, days));
        continue;
      }
    }
    final share = s.code == null ? null : shares[s.code];
    if (share != null && share.minutes < kNudgeStudyMinutes && now.weekday >= DateTime.wednesday) {
      out.add(NudgeSuggestion(s, NudgeReason.study, share.minutes));
    }
  }
  int rank(NudgeSuggestion x) => x.reason.index;
  out.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    return a.reason == NudgeReason.study ? a.value.compareTo(b.value) : b.value.compareTo(a.value);
  });
  return out;
}
