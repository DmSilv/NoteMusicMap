import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'my_lessons_page.dart' show taskKindIcon;
import 'person_avatar.dart';
import 'student_identity.dart' show studentTint;
import 'teacher_page.dart' show StudentPage;
import 'theme.dart';
import 'widgets.dart';

/// Modal "Avaliar tarefa": quem é o aluno e o que foi passado, o que o app já mediu (melhor acerto contra a meta), um recado
/// opcional ao aluno e as três saídas: está boa (valida), refazer (o aluno continua nela) ou levar para a próxima aula.
/// O recado vai ao aluno como observação (pelo mesmo caminho das observações do professor).
Future<void> showReviewSheet(BuildContext context, AppState app, Student student, Assignment task) {
  final note = TextEditingController();
  return showDsSheet(
    context,
    title: tr('Avaliar tarefa'),
    listenable: app,
    children: (c) {
      final t = student.tasks.where((x) => x.id == task.id).firstOrNull ?? task;
      void pick(TaskReview r, String msg) {
        final recado = note.text.trim();
        app.reviewAssignment(student, t.id, r);
        Navigator.of(c).pop();
        // O recado entra como observação do aluno e segue a regra de entrega (agora, na fila ou só na ficha).
        app.say(recado.isEmpty ? msg : '$msg ${app.addTeacherNote(student, '${t.title}: $recado')}');
      }

      // O que o app mediu desta mesma escala/arpejo: melhor acerto e quantas vezes esta semana.
      final weekAgo = DateTime.now().subtract(const Duration(days: 7));
      final mine = t.isScale ? [for (final s in student.sessions) if (s.title == t.title) s] : <SessionRecord>[];
      final best = mine.isEmpty ? null : mine.map((s) => s.accuracy).reduce((x, y) => x > y ? x : y);
      final week = mine.where((s) => s.date.isAfter(weekAgo)).length;

      return [
        Row(children: [
          PersonAvatar(name: student.name, photo: app.photoOfStudent(student), tint: studentTint(student), radius: 22),
          const SizedBox(width: Ds.s12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              Text(tr('{0} · passada em {1}', [app.labelOf(student), fmtDayMonth(t.created)]), style: Ds.support()),
            ]),
          ),
        ]),
        if (t.awaitsValidation) ...[
          const SizedBox(height: Ds.s12),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.fact_check_outlined, size: 15, color: AppColors.accent),
                const SizedBox(width: 6),
                Text(tr('{0} marcou como feita', [student.name]), style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: Ds.fontLabel)),
              ]),
            ),
          ),
        ],
        if (t.note.isNotEmpty) ...[
          const SizedBox(height: Ds.s12),
          Text(t.note, style: Ds.support()),
        ],
        if (best != null) ...[
          const SizedBox(height: Ds.s16),
          DsGroupRow(
            tr('Medido pelo app'),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Melhor acerto {0}% · meta {1}%', [(best * 100).round(), (t.goal * 100).round()]),
                  style: TextStyle(fontWeight: FontWeight.w700, color: best >= t.goal ? AppColors.inTune : AppColors.flat)),
              const SizedBox(height: Ds.s8),
              LayoutBuilder(builder: (_, box) {
                final w = box.maxWidth;
                return SizedBox(
                  height: 12,
                  child: Stack(clipBehavior: Clip.none, children: [
                    Container(height: 8, margin: const EdgeInsets.only(top: 2), decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(4))),
                    Container(
                      height: 8,
                      width: w * best.clamp(0.0, 1.0),
                      margin: const EdgeInsets.only(top: 2),
                      decoration: BoxDecoration(color: best >= t.goal ? AppColors.inTune : AppColors.flat, borderRadius: BorderRadius.circular(4)),
                    ),
                    Positioned(left: w * t.goal.clamp(0.0, 1.0) - 1, top: 0, bottom: 0, child: Container(width: 2, color: AppColors.text)),
                  ]),
                );
              }),
              const SizedBox(height: Ds.s4),
              Text(week == 1 ? tr('1 sessão nesta semana') : tr('{0} sessões nesta semana', [week]), style: Ds.support()),
            ]),
          ),
        ],
        const SizedBox(height: Ds.s16),
        TextField(
          controller: note,
          maxLines: 3,
          minLines: 1,
          maxLength: 300,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: tr('Recado para {0} (opcional)', [student.name]), helperText: tr('Vai junto, como observação.')),
        ),
        const SizedBox(height: Ds.s12),
        if (!t.done)
          SizedBox(
            height: Ds.primaryHeight,
            child: FilledButton.icon(
              onPressed: () => pick(TaskReview.ok, tr('Tarefa validada.')),
              icon: const Icon(Icons.check_rounded),
              label: Text(tr('Está boa'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
          ),
        const SizedBox(height: Ds.s12),
        Row(children: [
          Expanded(
            child: SizedBox(
              height: Ds.primaryHeight,
              child: OutlinedButton.icon(
                onPressed: () => pick(TaskReview.back, tr('Devolvida para refazer.')),
                icon: const Icon(Icons.replay_rounded),
                label: Text(tr('Refazer'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
          const SizedBox(width: Ds.s12),
          Expanded(
            child: SizedBox(
              height: Ds.primaryHeight,
              child: OutlinedButton.icon(
                onPressed: () => pick(TaskReview.next, tr('A tarefa vai de novo ao aluno na próxima aula.')),
                icon: const Icon(Icons.redo_rounded),
                label: Text(tr('Próxima aula'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ]),
        const SizedBox(height: Ds.s8),
        Text(tr('Refazer: o aluno continua nesta tarefa. Próxima aula: ela volta como pendente e é enviada de novo.'), textAlign: TextAlign.center, style: Ds.support()),
      ];
    },
  ).whenComplete(note.dispose);
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
              subtitle: tr('Como foi a semana de {0}? Valide, mande refazer ou passe para a próxima aula.', [app.labelOf(student)]),
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
        title: Text(n == 1 ? tr('Validar 1 tarefa?') : tr('Validar {0} tarefas?', [n])),
        content: Text(tr('Só as que os alunos marcaram como feitas. Cada aluno recebe o aviso.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Cancelar'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Validar'))),
        ],
      ),
    );
    if (ok != true) return;
    // A fila pode ter mudado com o diálogo aberto (o aluno desmarcou, a sincronização trouxe outra): vale a de agora.
    var done = 0;
    for (final g in reviewQueue(app.students, DateTime.now())) {
      for (final t in g.marked) {
        app.reviewAssignment(g.student, t.id, TaskReview.ok);
        done++;
      }
    }
    if (done > 0) app.say(done == 1 ? tr('1 tarefa confirmada.') : tr('{0} tarefas confirmadas.', [done]));
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
    final name = app.labelOf(g.student);
    final tint = studentTint(g.student);
    return InkWell(
      borderRadius: BorderRadius.circular(Ds.radiusControl),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StudentPage(app: app, studentId: g.student.id))),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Ds.tap),
        child: Row(children: [
          PersonAvatar(name: g.student.name, photo: app.photoOfStudent(g.student), tint: tint, radius: 16),
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
