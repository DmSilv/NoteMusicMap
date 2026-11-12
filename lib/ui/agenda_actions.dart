import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'agenda_sheets.dart';

/// Controle da agenda do professor: remarcar só uma aula, trocar horários entre dois alunos e pausar um período.
/// Toda mudança mostra antes o que vai acontecer e quem é avisado, e só vale se couber na agenda (sem choque).

String _two(int n) => n.toString().padLeft(2, '0');
const _dow = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];
String _when(DateTime d) => '${_dow[d.weekday - 1]} ${_two(d.day)}/${_two(d.month)} ${_two(d.hour)}:${_two(d.minute)}';

String _nameOf(AppState app, ClassSlot s) => app.studentByCode(s.studentCode)?.name ?? 'o aluno';

Future<bool> _ask(BuildContext context, String title, String body, String ok, {bool danger = false}) =>
    showConfirmSheet(context, title: title, body: body, ok: ok, danger: danger, icon: danger ? Icons.event_busy_rounded : Icons.help_outline_rounded);

/// Remarcar SÓ esta aula (numa regra semanal, as outras semanas continuam). Um modal só: dia, hora, conferência ao vivo e confirmação.
/// Devolve true se a aula foi remarcada.
Future<bool> moveOccurrenceFlow(BuildContext context, AppState app, SlotOccurrence o) async {
  final newId = newSlotId(DateTime.now());
  SlotPlan planFor(DateTime to) => planMoveOccurrence(o.slot, o.startMs, to.millisecondsSinceEpoch, newId: newId);
  String? check(DateTime to) =>
      validatePlan(planFor(to), app.agenda, DateTime.now().millisecondsSinceEpoch, nameOf: (c) => app.studentByCode(c)?.name ?? 'outro aluno');
  final who = _nameOf(app, o.slot);
  final to = await showMoveSheet(
    context,
    who: who,
    from: o.start,
    weekly: o.slot.weekly,
    check: check,
    commit: (to) => app.commitPlan(planFor(to), crumbName: 'Remarcar aula'),
  );
  if (to != null) app.celebrate('Aula remarcada', detail: '$who · ${_when(to)}');
  return to != null;
}

/// Trocar o horário desta aula com o de outro aluno (os dois são avisados). Um modal só: escolher, ver o que muda e confirmar.
Future<void> swapFlow(BuildContext context, AppState app, SlotOccurrence o) async {
  final now = DateTime.now();
  final others = agendaBetween(app.visibleAgenda, now.millisecondsSinceEpoch, now.millisecondsSinceEpoch + 21 * kMsDay)
      .where((x) => x.slot.id != o.slot.id && x.slot.studentCode != o.slot.studentCode)
      .toList();
  if (others.isEmpty) {
    app.say('Não há aulas de outros alunos nas próximas 3 semanas para trocar.');
    return;
  }
  final nowId = newSlotId(DateTime.now());
  SlotPlan planFor(int i) => planSwap(o, others[i], newIdA: nowId, newIdB: '${nowId}b');
  final a = _nameOf(app, o.slot);
  final i = await showSwapSheet(
    context,
    aName: a,
    aStart: o.start,
    options: [for (final x in others) SwapOption(_nameOf(app, x.slot), x.start)],
    check: (i) => validatePlan(planFor(i), app.agenda, DateTime.now().millisecondsSinceEpoch, nameOf: (c) => app.studentByCode(c)?.name ?? 'outro aluno'),
    commit: (i) => app.commitPlan(planFor(i), crumbName: 'Trocar horários'),
  );
  if (i != null) app.celebrate('Horários trocados', detail: '$a ↔ ${_nameOf(app, others[i].slot)}');
}

/// Cancelar uma aula: a semanal pergunta se é só esta data ou todas; a avulsa só confirma. O aluno é avisado.
Future<void> cancelOccurrenceFlow(BuildContext context, AppState app, SlotOccurrence o) async {
  final s = o.slot;
  final who = _nameOf(app, s);
  if (s.weekly) {
    final c = await showCancelSheet(context, who: who, dateLabel: _when(o.start));
    if (c == null) return;
    if (c == CancelChoice.one) {
      app.skipOccurrence(s.id, o.startMs);
    } else {
      app.cancelSlot(s.id);
    }
  } else {
    final ok = await _ask(context, 'Cancelar a aula?', '$who é avisado.', 'Cancelar aula', danger: true);
    if (!ok) return;
    app.cancelSlot(s.id);
  }
  app.say('Aula cancelada.');
}

/// "Aluno não veio": registra a falta na ficha e, conforme a escolha, cancela só a aula de hoje ou abre o remarcar.
/// [occ] é a aula em questão; sem ela, usa a aula mais perto de agora (ou só registra, se não há aula marcada).
Future<void> absenceFlow(BuildContext context, AppState app, Student s, {SlotOccurrence? occ}) async {
  final now = DateTime.now();
  occ ??= s.code == null ? null : lessonForAbsence(app.slotsOf(s.code!), now.millisecondsSinceEpoch);
  final sameDay = occ != null && occ.start.year == now.year && occ.start.month == now.month && occ.start.day == now.day;
  final label = occ == null ? null : '${sameDay ? 'Aula de hoje' : 'Aula'} · ${_when(occ.start)}';
  final choice = await showAbsenceSheet(context, who: s.name, lessonLabel: label, hasLesson: occ != null, weekly: occ?.slot.weekly ?? false);
  if (choice == null || !context.mounted) return;
  final lessonMs = occ?.startMs ?? DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
  switch (choice) {
    case AbsenceChoice.noShow:
      app.recordAbsence(s, lessonMs: lessonMs, kind: AbsenceKind.noShow);
      app.say('Falta registrada na ficha de ${s.name}.');
    case AbsenceChoice.notified:
      app.recordAbsence(s, lessonMs: lessonMs, kind: AbsenceKind.notified);
      if (occ != null) {
        app.skipOccurrence(occ.slot.id, occ.startMs);
        app.say('Falta registrada. A aula foi cancelada e ${s.name} foi avisado.');
      } else {
        app.say('Falta registrada na ficha de ${s.name}.');
      }
    case AbsenceChoice.reschedule:
      // Só registra se a aula foi mesmo remarcada (se voltou do modal, nada mudou).
      if (occ != null && await moveOccurrenceFlow(context, app, occ)) {
        app.recordAbsence(s, lessonMs: lessonMs, kind: AbsenceKind.notified);
      }
  }
}

/// Pausar todas as aulas de um período (férias, viagem): cancela só aquelas datas.
Future<void> pauseFlow(BuildContext context, AppState app) async {
  final now = DateTime.now();
  final first = DateTime(now.year, now.month, now.day);
  final r = await showDateRangePicker(
    context: context,
    firstDate: first,
    lastDate: DateTime(now.year + 2),
    helpText: 'Pausar aulas de… até…',
    saveText: 'Continuar',
  );
  if (r == null || !context.mounted) return;
  final from = DateTime(r.start.year, r.start.month, r.start.day);
  final to = DateTime(r.end.year, r.end.month, r.end.day + 1);
  final plan = planPause(app.agenda, from.millisecondsSinceEpoch, to.millisecondsSinceEpoch);
  final err = plan.ok ? null : plan.error;
  if (err != null) {
    app.say(err);
    return;
  }
  final hit = agendaBetween(app.visibleAgenda, from.millisecondsSinceEpoch, to.millisecondsSinceEpoch);
  if (hit.isEmpty) {
    app.say('Não há aulas nesse período.');
    return;
  }
  final students = {for (final h in hit) h.slot.studentCode};
  final ok = await _ask(
      context,
      'Pausar as aulas?',
      '${hit.length} aula${hit.length == 1 ? '' : 's'} de ${_two(from.day)}/${_two(from.month)} a ${_two(r.end.day)}/${_two(r.end.month)} '
          'ser${hit.length == 1 ? 'á cancelada' : 'ão canceladas'}.\n${students.length} aluno${students.length == 1 ? ' é avisado' : 's são avisados'}.\nAs aulas semanais voltam depois do período.',
      'Pausar',
      danger: true);
  if (!ok) return;
  final e = app.commitPlan(plan, crumbName: 'Pausar aulas');
  if (e != null) {
    app.say(e);
  } else {
    app.celebrate('Aulas pausadas', detail: '${hit.length} aula${hit.length == 1 ? '' : 's'} · ${students.length} aluno${students.length == 1 ? '' : 's'} avisado${students.length == 1 ? '' : 's'}');
  }
}
