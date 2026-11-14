import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'my_lessons_page.dart' show taskKindIcon;
import 'theme.dart';
import 'widgets.dart';

/// Modal "Como foi esta tarefa?": o professor decide sozinho (o aluno não precisa marcar nada).
/// Três saídas: está boa (valida), refazer (o aluno vê "refazer") ou levar para a próxima aula.
Future<void> showReviewSheet(BuildContext context, AppState app, Student student, Assignment task) {
  return showDsSheet(
    context,
    title: tr('Como foi esta tarefa?'),
    listenable: app,
    children: (c) {
      final t = student.tasks.where((x) => x.id == task.id).firstOrNull ?? task;
      void pick(TaskReview r, String msg) {
        app.reviewAssignment(student, t.id, r);
        Navigator.of(c).pop();
        app.say(msg);
      }

      Widget option({required IconData icon, required String label, required String hint, required VoidCallback onTap, bool primary = false}) => Padding(
            padding: const EdgeInsets.only(bottom: Ds.s16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                height: Ds.primaryHeight,
                child: primary
                    ? FilledButton.icon(onPressed: onTap, icon: Icon(icon), label: Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)))
                    : OutlinedButton.icon(onPressed: onTap, icon: Icon(icon), label: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
              ),
              const SizedBox(height: Ds.s4),
              Text(hint, textAlign: TextAlign.center, style: Ds.support()),
            ]),
          );

      return [
        Row(children: [
          DsIconBadge(taskKindIcon(t.kind), size: 40),
          const SizedBox(width: Ds.s12),
          Expanded(child: Text(t.title, style: const TextStyle(fontSize: Ds.fontBody, fontWeight: FontWeight.w700))),
        ]),
        if (t.awaitsValidation) ...[
          const SizedBox(height: Ds.s8),
          Row(children: [
            Icon(Icons.fact_check_outlined, size: 16, color: AppColors.accent),
            const SizedBox(width: 6),
            Text(tr('Aluno marcou como feita'), style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: Ds.fontLabel)),
          ]),
        ],
        const SizedBox(height: Ds.s20),
        if (!t.done)
          option(
            primary: true,
            icon: Icons.check_rounded,
            label: tr('Está boa'),
            hint: tr('Finaliza a tarefa e avisa o aluno.'),
            onTap: () => pick(TaskReview.ok, tr('Tarefa validada.')),
          ),
        option(
          icon: Icons.replay_rounded,
          label: tr('Refazer'),
          hint: tr('O aluno vê "refazer" e continua com ela.'),
          onTap: () => pick(TaskReview.back, tr('Devolvida para refazer.')),
        ),
        option(
          icon: Icons.redo_rounded,
          label: tr('Levar para a próxima aula'),
          hint: tr('Vai de novo com a próxima aula do aluno.'),
          onTap: () => pick(TaskReview.next, tr('Vai com a próxima aula.')),
        ),
      ];
    },
  );
}

/// Na ficha do aluno: as tarefas que esperam a decisão do professor. O aluno não precisa assinar nada;
/// quem confere é o professor (um toque no ✓ valida; tocar na linha abre as três saídas).
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
        padding: const EdgeInsets.fromLTRB(Ds.s16, Ds.s16, Ds.s8, Ds.s8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.fact_check_outlined, color: AppColors.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                list.length == 1 ? tr('1 tarefa para avaliar') : tr('{0} tarefas para avaliar', [list.length]),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
          ]),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(right: Ds.s8),
            child: Text(tr('Como foi a semana de {0}? Valide, mande refazer ou leve para a próxima aula.', [student.name]), style: Ds.support()),
          ),
          const SizedBox(height: Ds.s4),
          for (final t in list)
            InkWell(
              borderRadius: BorderRadius.circular(Ds.radiusControl),
              onTap: () => showReviewSheet(context, app, student, t),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 60),
                child: Row(children: [
                  Icon(taskKindIcon(t.kind), size: 20, color: AppColors.textDim),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: Ds.fontBody)),
                      if (t.awaitsValidation) Text(tr('Aluno marcou como feita'), style: TextStyle(color: AppColors.accent, fontSize: Ds.fontLabel, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                  IconButton.filledTonal(
                    tooltip: tr('Está boa'),
                    style: IconButton.styleFrom(minimumSize: const Size(Ds.tap, Ds.tap)),
                    onPressed: () => app.reviewAssignment(student, t.id, TaskReview.ok),
                    icon: const Icon(Icons.check_rounded),
                  ),
                  Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
                ]),
              ),
            ),
          if (list.length > 1)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  for (final t in list) {
                    app.reviewAssignment(student, t.id, TaskReview.ok);
                  }
                  app.say(tr('{0} tarefas confirmadas.', [list.length]));
                },
                icon: const Icon(Icons.done_all, size: 18),
                label: Text(tr('Confirmar todas')),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Ao começar a aula: o professor confere as tarefas da semana de uma vez. Para cada uma escolhe "Boa",
/// "Refazer" ou "Levar" (para a próxima aula); sem escolha, nada muda. Não bloqueia a aula.
Future<void> showValidationDialog(BuildContext context, AppState app, Student s) async {
  final list = app.awaitingOf(s);
  if (list.isEmpty) return;
  final pick = <String, TaskReview?>{};
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) => AlertDialog(
        title: Text(tr('Como foi a semana de {0}?', [s.name])),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Escolha o que fazer com cada tarefa. O que você não escolher fica como está.'), style: Ds.support()),
              const SizedBox(height: Ds.s12),
              for (final t in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: Ds.s16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: Ds.fontBody)),
                    const SizedBox(height: Ds.s8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final (r, label) in [(TaskReview.ok, tr('Boa')), (TaskReview.back, tr('Refazer')), (TaskReview.next, tr('Levar'))])
                        ChoiceChip(
                          label: Text(label),
                          selected: pick[t.id] == r,
                          onSelected: (v) => setS(() => pick[t.id] = v ? r : null),
                        ),
                    ]),
                  ]),
                ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Decidir depois'))),
          FilledButton.icon(onPressed: () => Navigator.pop(c, true), icon: const Icon(Icons.check, size: 18), label: Text(tr('Aplicar'))),
        ],
      ),
    ),
  );
  if (ok != true) return;
  var good = 0, back = 0, next = 0;
  for (final t in list) {
    final r = pick[t.id];
    if (r == null) continue;
    app.reviewAssignment(s, t.id, r);
    switch (r) {
      case TaskReview.ok:
        good++;
      case TaskReview.back:
        back++;
      case TaskReview.next:
        next++;
    }
  }
  if (good + back + next > 0) {
    app.say(tr('{0} validada(s), {1} para refazer, {2} para a próxima aula.', [good, back, next]));
  }
}
