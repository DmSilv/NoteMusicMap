import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'theme.dart';

/// Controle da agenda do professor: remarcar só uma aula, trocar horários entre dois alunos e pausar um período.
/// Toda mudança mostra antes o que vai acontecer e quem é avisado, e só vale se couber na agenda (sem choque).

String _two(int n) => n.toString().padLeft(2, '0');
const _dow = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];
String _when(DateTime d) => '${_dow[d.weekday - 1]} ${_two(d.day)}/${_two(d.month)} ${_two(d.hour)}:${_two(d.minute)}';

String _nameOf(AppState app, ClassSlot s) => app.studentByCode(s.studentCode)?.name ?? 'o aluno';

Future<bool> _ask(BuildContext context, String title, String body, String ok, {bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Voltar')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: AppColors.sharp, foregroundColor: readableOn(AppColors.sharp)) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r == true;
}

/// Remarcar SÓ esta aula (numa regra semanal, as outras semanas continuam).
Future<void> moveOccurrenceFlow(BuildContext context, AppState app, SlotOccurrence o) async {
  final now = DateTime.now();
  final first = DateTime(now.year, now.month, now.day);
  final init = o.start.isBefore(first) ? first : o.start;
  final d = await showDatePicker(context: context, initialDate: init, firstDate: first, lastDate: DateTime(now.year + 2), helpText: 'Novo dia da aula');
  if (d == null || !context.mounted) return;
  final t = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: o.start.hour, minute: o.start.minute),
    helpText: 'Novo horário',
    builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!),
  );
  if (t == null || !context.mounted) return;
  final to = DateTime(d.year, d.month, d.day, t.hour, t.minute);
  final plan = planMoveOccurrence(o.slot, o.startMs, to.millisecondsSinceEpoch, newId: newSlotId(DateTime.now()));
  final err = validatePlan(plan, app.agenda, DateTime.now().millisecondsSinceEpoch, nameOf: (c) => app.studentByCode(c)?.name ?? 'outro aluno');
  if (err != null) {
    app.say(err);
    return;
  }
  final who = _nameOf(app, o.slot);
  final ok = await _ask(
      context, 'Remarcar esta aula?', '$who: de ${_when(o.start)} para ${_when(to)}.\n$who é avisado.${o.slot.weekly ? '\nAs outras semanas continuam como estão.' : ''}', 'Remarcar');
  if (!ok) return;
  final e = app.commitPlan(plan, crumbName: 'Remarcar aula');
  if (e != null) {
    app.say(e);
  } else {
    app.celebrate('Aula remarcada', detail: '$who · ${_when(to)}');
  }
}

/// Trocar o horário desta aula com o de outro aluno (os dois são avisados).
Future<void> swapFlow(BuildContext context, AppState app, SlotOccurrence o) async {
  final now = DateTime.now();
  final others = agendaBetween(app.visibleAgenda, now.millisecondsSinceEpoch, now.millisecondsSinceEpoch + 21 * kMsDay)
      .where((x) => x.slot.id != o.slot.id && x.slot.studentCode != o.slot.studentCode)
      .toList();
  if (others.isEmpty) {
    app.say('Não há aulas de outros alunos nas próximas 3 semanas para trocar.');
    return;
  }
  final pick = await showModalBottomSheet<SlotOccurrence>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Ds.radiusCard))),
    builder: (c) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.8),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Ds.screenPad, 0, Ds.screenPad, Ds.s8),
          child: Text('Trocar com quem?', style: Ds.title()),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Ds.screenPad, 0, Ds.screenPad, Ds.s8),
          child: Text('A aula de ${_nameOf(app, o.slot)} (${_when(o.start)}) vai para o horário da aula escolhida, e a escolhida vem para cá.', style: Ds.support()),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(Ds.screenPad, 0, Ds.screenPad, Ds.s24),
            children: [
              for (final x in others)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const DsIconBadge(Icons.swap_horiz_rounded, size: 34),
                  title: Text(_nameOf(app, x.slot), style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(_when(x.start)),
                  onTap: () => Navigator.pop(c, x),
                ),
            ],
          ),
        ),
      ]),
    ),
  );
  if (pick == null || !context.mounted) return;
  final nowId = newSlotId(DateTime.now());
  final plan = planSwap(o, pick, newIdA: nowId, newIdB: '${nowId}b');
  final err = validatePlan(plan, app.agenda, DateTime.now().millisecondsSinceEpoch, nameOf: (c) => app.studentByCode(c)?.name ?? 'outro aluno');
  if (err != null) {
    app.say(err);
    return;
  }
  final a = _nameOf(app, o.slot), b = _nameOf(app, pick.slot);
  final ok = await _ask(context, 'Trocar os horários?', '$a: ${_when(o.start)} → ${_when(pick.start)}\n$b: ${_when(pick.start)} → ${_when(o.start)}\n\nOs dois são avisados.', 'Trocar');
  if (!ok) return;
  final e = app.commitPlan(plan, crumbName: 'Trocar horários');
  if (e != null) {
    app.say(e);
  } else {
    app.celebrate('Horários trocados', detail: '$a ↔ $b');
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
