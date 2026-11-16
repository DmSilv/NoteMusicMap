import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'my_lessons_page.dart' show taskKindIcon;
import 'teacher_page.dart' show StudentPage;
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
        if (t.note.isNotEmpty) ...[
          const SizedBox(height: Ds.s12),
          Text(t.note, style: Ds.support()),
        ],
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
          hint: tr('O aluno vê "refazer" e continua estudando esta tarefa.'),
          onTap: () => pick(TaskReview.back, tr('Devolvida para refazer.')),
        ),
        option(
          icon: Icons.redo_rounded,
          label: tr('Passar para a próxima aula'),
          hint: tr('A tarefa volta como pendente e é enviada de novo ao aluno na próxima aula.'),
          onTap: () => pick(TaskReview.next, tr('A tarefa vai de novo ao aluno na próxima aula.')),
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
      padding: const EdgeInsets.only(bottom: Ds.gap),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Ds.s16, Ds.s16, Ds.s16, Ds.s8),
            child: DsCardTitle(
              Icons.fact_check_outlined,
              list.length == 1 ? tr('1 tarefa para avaliar') : tr('{0} tarefas para avaliar', [list.length]),
              subtitle: tr('Como foi a semana de {0}? Valide, mande refazer ou passe para a próxima aula.', [student.name]),
            ),
          ),
          for (final t in list)
            DsTaskRow(
              icon: taskKindIcon(t.kind),
              title: t.title,
              support: t.kind.label,
              status: t.awaitsValidation ? DsStatus(tr('Aluno marcou como feita'), Icons.fact_check_outlined, AppColors.accent) : null,
              onTap: () => showReviewSheet(context, app, student, t),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton.filledTonal(
                  tooltip: tr('Está boa'),
                  style: IconButton.styleFrom(minimumSize: const Size(Ds.tap, Ds.tap)),
                  onPressed: () => app.reviewAssignment(student, t.id, TaskReview.ok),
                  icon: const Icon(Icons.check_rounded),
                ),
                Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
              ]),
            ),
          if (list.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(Ds.s8, 0, Ds.s8, Ds.s8),
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
              for (final (_, icon, label, hint) in [
                (TaskReview.ok, Icons.check_rounded, tr('Está boa'), tr('finaliza a tarefa')),
                (TaskReview.back, Icons.replay_rounded, tr('Refazer'), tr('o aluno continua com ela')),
                (TaskReview.next, Icons.redo_rounded, tr('Próxima aula'), tr('volta como pendente e é enviada de novo na próxima aula')),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: Ds.s4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(icon, size: 16, color: AppColors.textDim),
                    const SizedBox(width: Ds.s8),
                    Expanded(child: Text.rich(TextSpan(children: [TextSpan(text: label, style: const TextStyle(fontWeight: FontWeight.w800)), TextSpan(text: ': $hint')]), style: Ds.support())),
                  ]),
                ),
              const SizedBox(height: Ds.s16),
              for (final t in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: Ds.s16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: Ds.fontBody)),
                    const SizedBox(height: Ds.s8),
                    Wrap(spacing: Ds.s8, runSpacing: Ds.s8, children: [
                      for (final (r, icon, label) in [
                        (TaskReview.ok, Icons.check_rounded, tr('Está boa')),
                        (TaskReview.back, Icons.replay_rounded, tr('Refazer')),
                        (TaskReview.next, Icons.redo_rounded, tr('Próxima aula')),
                      ])
                        ChoiceChip(
                          avatar: Icon(icon, size: 18),
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

/// Fila de validação: todas as tarefas que esperam decisão, de todos os alunos, numa tela só.
/// As que o aluno marcou como feitas vêm primeiro; "Validar as marcadas" resolve todas de uma vez.
class ValidationQueuePage extends StatefulWidget {
  final AppState app;
  const ValidationQueuePage({super.key, required this.app});

  @override
  State<ValidationQueuePage> createState() => _ValidationQueuePageState();
}

class _ValidationQueuePageState extends State<ValidationQueuePage> {
  /// null = automático: só as marcadas, se houver alguma; senão todas.
  bool? _onlyMarked;

  AppState get app => widget.app;

  Future<void> _validateMarked(List<ReviewGroup> queue, int n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Validar {0} tarefas?', [n])),
        content: Text(tr('Só as que os alunos marcaram como feitas. Cada aluno recebe o aviso.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Cancelar'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Validar'))),
        ],
      ),
    );
    if (ok != true) return;
    for (final g in queue) {
      for (final t in g.marked) {
        app.reviewAssignment(g.student, t.id, TaskReview.ok);
      }
    }
    app.say(tr('{0} tarefas confirmadas.', [n]));
  }

  Widget _row(ReviewGroup g, Assignment t, {required bool only}) {
    final marked = t.claimedAt != null;
    return DsTaskRow(
      icon: taskKindIcon(t.kind),
      title: t.title,
      support: tr('Enviada em {0}', [fmtDayMonth(t.created)]),
      status: marked && !only ? DsStatus(tr('Aluno marcou como feita'), Icons.fact_check_outlined, AppColors.accent) : null,
      onTap: () => showReviewSheet(context, app, g.student, t),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton.filledTonal(
          tooltip: tr('Está boa'),
          style: IconButton.styleFrom(minimumSize: const Size(Ds.tap, Ds.tap)),
          onPressed: () => app.reviewAssignment(g.student, t.id, TaskReview.ok),
          icon: const Icon(Icons.check_rounded),
        ),
        Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
      ]),
    );
  }

  Widget _header(ReviewGroup g, int shown) {
    final name = g.student.name;
    return InkWell(
      borderRadius: BorderRadius.circular(Ds.radiusControl),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StudentPage(app: app, studentId: g.student.id))),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Ds.tap),
        child: Row(children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.accent.withValues(alpha: 0.2),
            child: Text(name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(), style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800, fontSize: 14)),
          ),
          const SizedBox(width: Ds.s12),
          Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: Ds.fontBody))),
          Text(shown == 1 ? tr('1 tarefa') : tr('{0} tarefas', [shown]), style: Ds.support()),
          Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Para validar'))),
      body: DsPageSafe(
        child: ListenableBuilder(
          listenable: app,
          builder: (context, _) {
            final queue = reviewQueue(app.students, DateTime.now());
            if (queue.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(Ds.s32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    DsIconBadge(Icons.task_alt_rounded, size: 56, color: AppColors.inTune),
                    const SizedBox(height: Ds.s16),
                    Text(tr('Nada para validar'), style: Ds.title()),
                    const SizedBox(height: Ds.s8),
                    Text(tr('Quando os alunos marcarem tarefas como feitas, elas aparecem aqui.'), textAlign: TextAlign.center, style: Ds.support()),
                  ]),
                ),
              );
            }
            final markedTotal = queue.fold<int>(0, (a, g) => a + g.marked.length);
            final total = queue.fold<int>(0, (a, g) => a + g.total);
            final hasBoth = markedTotal > 0 && markedTotal < total;
            final only = markedTotal == 0 ? false : (hasBoth ? (_onlyMarked ?? true) : true);
            final groups = [
              for (final g in queue)
                if ((only ? g.marked : g.all).isNotEmpty) g,
            ];
            return ListView(
              padding: Ds.screen,
              children: [
                if (markedTotal > 0) ...[
                  SizedBox(
                    height: Ds.primaryHeight,
                    child: FilledButton.icon(
                      onPressed: () => _validateMarked(queue, markedTotal),
                      icon: const Icon(Icons.done_all_rounded),
                      label: Text(markedTotal == 1 ? tr('Validar a tarefa marcada') : tr('Validar as {0} marcadas', [markedTotal]),
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(height: Ds.s4),
                  Text(tr('Os alunos marcaram estas como feitas.'), textAlign: TextAlign.center, style: Ds.support()),
                  const SizedBox(height: Ds.gap),
                ],
                if (hasBoth) ...[
                  Wrap(spacing: Ds.s8, runSpacing: Ds.s8, children: [
                    ChoiceChip(label: Text(tr('Marcadas ({0})', [markedTotal])), selected: only, onSelected: (_) => setState(() => _onlyMarked = true)),
                    ChoiceChip(label: Text(tr('Todas ({0})', [total])), selected: !only, onSelected: (_) => setState(() => _onlyMarked = false)),
                  ]),
                  const SizedBox(height: Ds.gap),
                ],
                for (final g in groups) ...[
                  _header(g, (only ? g.marked : g.all).length),
                  const SizedBox(height: Ds.s8),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(children: [
                      for (var i = 0; i < (only ? g.marked : g.all).length; i++) ...[
                        if (i > 0) Divider(height: 1, color: AppColors.textDim.withValues(alpha: 0.15)),
                        _row(g, (only ? g.marked : g.all)[i], only: only),
                      ],
                    ]),
                  ),
                  const SizedBox(height: Ds.gap),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
