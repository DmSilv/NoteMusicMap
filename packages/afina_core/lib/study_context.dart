import 'i18n.dart';
import 'practice_coach.dart';
import 'study_streak.dart';

/// O que o treinador (IA) recebe além dos números das escalas: o estudo da semana, as tarefas em aberto do professor e, só se a
/// pessoa autorizar, as observações dele. Nunca áudio, nunca nomes: tarefas e observações entram como texto curto e limitado.
String buildStudyContext({
  required Map<String, double> studySeconds,
  required DateTime now,
  required double goalMinutes,
  List<String> openTasks = const [],
  List<String> teacherNotes = const [],
  int lessonsCount = 0,
}) {
  final w = weekSummary(studySeconds, now, goalMinutes);
  final b = StringBuffer();
  b.writeln(tr('Estudo da semana: {0} min em {1} de 7 dias; meta de {2} min batida {3}×.', [w.minutes, w.daysStudied, goalMinutes.round(), w.goalDays]));
  if (w.previousMinutes > 0) {
    b.writeln(tr('Semana anterior: {0} min.', [w.previousMinutes]));
  }
  if (lessonsCount > 0) b.writeln(tr('Aulas recebidas do professor: {0}.', [lessonsCount]));
  if (openTasks.isNotEmpty) {
    b.writeln(tr('Tarefas do professor ainda em aberto:'));
    for (final t in openTasks.take(8)) {
      b.writeln('- ${_cut(t, 90)}');
    }
  }
  if (teacherNotes.isNotEmpty) {
    b.writeln(tr('Observações recentes do professor (use para orientar, sem citar nomes):'));
    for (final n in teacherNotes.take(5)) {
      b.writeln('- ${_cut(n, 200)}');
    }
  }
  return b.toString().trim();
}

/// Mensagem pronta que o professor manda pelo WhatsApp para lembrar o aluno de estudar (ele pode mudar antes de enviar).
String studyReminderText(String firstName, List<String> openTasks) {
  final tasks = [for (final t in openTasks) if (t.trim().isNotEmpty) _cut(t, 60)].take(3).toList();
  if (tasks.isEmpty) return tr('Oi, {0}! Que tal separar 15 minutos hoje para estudar? Qualquer dúvida, é só me chamar.', [firstName]);
  return tr('Oi, {0}! Ficou para estudar: {1}. Consegue separar uns 15 minutos hoje? Qualquer dúvida, é só me chamar.', [firstName, tasks.join(', ')]);
}

String _cut(String s, int max) {
  final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.length <= max ? t : '${t.substring(0, max - 1)}…';
}

/// Impressão curta (FNV-1a) do que foi enviado: serve para saber se algo mudou desde o último plano.
String studyContextFingerprint(String text) {
  var h = 0x811c9dc5;
  for (final c in text.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h.toRadixString(16);
}

/// Pode pedir um plano novo? Sem plano: sim. Com plano de mais de 7 dias: sim. Com plano de mais de 1 dia: só se os dados mudaram.
/// Antes disso: não (o plano da semana vale, e a IA não é chamada à toa).
bool canAskNewPlan({required DateTime? planAt, required String? planFingerprint, required String currentFingerprint, required DateTime now}) {
  if (planAt == null) return true;
  final age = now.difference(planAt);
  if (age.inDays >= 7) return true;
  if (age.inHours < 24) return false;
  return planFingerprint != currentFingerprint;
}

/// Pedido de plano: junta os números das escalas (já no formato do treinador) e o contexto de estudo.
String buildPlanRequest(String scalesPrompt, String studyContext) =>
    studyContext.isEmpty ? scalesPrompt : '$scalesPrompt\n\n$studyContext';

/// Pergunta ao treinador, com o mesmo contexto.
String buildQuestionRequest(String question, String studyContext, {String? scalesPrompt}) {
  final b = StringBuffer()..writeln(tr('Pergunta do aluno: {0}', [_cut(question, 200)]));
  if (studyContext.isNotEmpty) b..writeln()..writeln(studyContext);
  if (scalesPrompt != null && scalesPrompt.isNotEmpty) b..writeln()..writeln(scalesPrompt);
  return b.toString().trim();
}

/// As sessões recentes cabem no pedido: o treinador só usa as últimas 10 (o resto é cortado em [buildAiPrompt]).
List<SessionRecord> recentSessions(List<SessionRecord> all) => all.take(10).toList();
