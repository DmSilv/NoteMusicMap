import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'my_lessons_page.dart' show taskKindIcon;
import 'theme.dart';
import 'widgets.dart';

String _when(DateTime at) {
  final d = at.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final hh = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  if (day == today) return tr('hoje, {0}', [hh]);
  if (day == today.subtract(const Duration(days: 1))) return tr('ontem, {0}', [hh]);
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}, $hh';
}

/// Na ficha do aluno: as tarefas que ELE marcou como feitas e que esperam a validação do
/// professor. Só viram "feitas" (finalizadas) quando o professor confirma; se não, voltam a pendente.
class ValidationCard extends StatelessWidget {
  final AppState app;
  final Student student;
  const ValidationCard({super.key, required this.app, required this.student});

  @override
  Widget build(BuildContext context) {
    final list = app.awaitingOf(student);
    if (list.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.fact_check_outlined, color: AppColors.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                list.length == 1 ? tr('1 tarefa para validar') : tr('{0} tarefas para validar', [list.length]),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            tr('{0} marcou como feita. Confirme para finalizar ou devolva para ficar pendente.', [student.name]),
            style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.3),
          ),
          for (final t in list)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(children: [
                Icon(taskKindIcon(t.kind), size: 18, color: AppColors.textDim),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(tr('Marcada {0}', [_when(t.claimedAt!)]), style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                  ]),
                ),
                TextButton.icon(
                  onPressed: () => app.validateAssignment(student, t.id, ok: false),
                  icon: const Icon(Icons.undo, size: 18), label: Text(tr('Devolver')),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => app.validateAssignment(student, t.id, ok: true),
                  icon: const Icon(Icons.check, size: 18), label: Text(tr('Confirmar')),
                ),
              ]),
            ),
          if (list.length > 1) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  for (final t in list) {
                    app.validateAssignment(student, t.id, ok: true);
                  }
                  app.say(tr('{0} tarefas confirmadas.', [list.length]));
                },
                icon: const Icon(Icons.done_all, size: 18),
                label: Text(tr('Confirmar todas')),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Ao começar a próxima aula: o professor confere o que o aluno marcou como feito desde a
/// última vez. Marcadas = confirmar (finaliza); desmarcadas = devolver (volta a pendente).
/// "Decidir depois" não muda nada. Não bloqueia a aula.
Future<void> showValidationDialog(BuildContext context, AppState app, Student s) async {
  final sum = summarizeTasks(s);
  final list = sum.toValidate;
  if (list.isEmpty) {
    // Nada a validar: se há tarefas pendentes, mostra só o resumo (não bloqueia; um toque e segue).
    if (sum.pending.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Resumo de {0}', [s.name])),
        content: SingleChildScrollView(child: _summaryBody(sum, showValidateHint: false)),
        actions: [FilledButton.icon(onPressed: () => Navigator.pop(c), icon: const Icon(Icons.play_arrow, size: 18), label: Text(tr('Começar a aula')))],
      ),
    );
    return;
  }
  final keep = {for (final t in list) t.id: true};
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) => AlertDialog(
        title: Text(tr('{0} fez {1}?', [s.name, list.length == 1 ? tr('esta tarefa') : tr('estas tarefas')])),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              tr('Ele marcou como feita. Deixe marcada a que está boa e desmarque a que precisa refazer.'),
              style: TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.3),
            ),
            const SizedBox(height: 6),
            Text(sum.line, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            const SizedBox(height: 8),
            for (final t in list)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: keep[t.id],
                onChanged: (v) => setS(() => keep[t.id] = v ?? false),
                title: Text(t.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(tr('Marcada {0}', [_when(t.claimedAt!)]), style: const TextStyle(fontSize: 12)),
              ),
            if (sum.pending.isNotEmpty) ...[
              const Divider(height: 18),
              _pendingList(sum),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Decidir depois'))),
          FilledButton.icon(onPressed: () => Navigator.pop(c, true), icon: const Icon(Icons.check, size: 18), label: Text(tr('Aplicar'))),
        ],
      ),
    ),
  );
  if (ok != true) return;
  var done = 0, back = 0;
  for (final t in list) {
    final yes = keep[t.id] == true;
    app.validateAssignment(s, t.id, ok: yes);
    yes ? done++ : back++;
  }
  app.say(tr('{0} confirmada{1}{2}.', [done, done == 1 ? '' : 's', back > 0 ? tr(', {0} devolvida{1}', [back, back == 1 ? '' : 's']) : '']));
}

Widget _summaryBody(TaskSummary sum, {required bool showValidateHint}) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(sum.line, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        const SizedBox(height: 8),
        _pendingList(sum),
      ],
    );

/// Tarefas ainda pendentes (até 5; o resto vira "e mais N").
Widget _pendingList(TaskSummary sum) {
  final shown = sum.pending.take(5).toList();
  final more = sum.pending.length - shown.length;
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(tr('Ainda pendentes'), style: TextStyle(color: AppColors.textDim, fontSize: 12.5, fontWeight: FontWeight.w700)),
    const SizedBox(height: 4),
    for (final t in shown)
      Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(children: [
          Icon(taskKindIcon(t.kind), size: 15, color: AppColors.textDim),
          const SizedBox(width: 6),
          Expanded(child: Text(t.title, style: const TextStyle(height: 1.25))),
        ]),
      ),
    if (more > 0) Text(tr('e mais {0}', [more]), style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
  ]);
}
