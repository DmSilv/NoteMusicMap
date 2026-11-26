import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../hub_section.dart' show shareTeacherInvite;
import '../link_bar.dart' show ensureTeacherLink;
import '../student_page.dart' show StudentPage, openStudentNewTask;
import '../design_system.dart';
import '../undo_snack.dart';
import '../teacher_page.dart';
import '../theme.dart';
import 'tour.dart';

/// Os primeiros passos do professor, abertos pela promessa do app: ajudar o aluno a estudar entre uma aula e outra.
/// Três passos (aluno, tarefa, tarefa entregue) e UM botão grande para o próximo. Some quando tudo foi feito; dá para esconder.
class StartCard extends StatelessWidget {
  final AppState app;
  const StartCard({super.key, required this.app});

  /// Mostrar o cartão? (professor, não escondido, e ainda falta algum passo)
  static bool visibleFor(AppState app) => !app.startCardHidden && !allStartDone(items(app));

  /// O cartão está escondido (e ainda faltam passos)? Aí o Meu espaço mostra uma linha para trazê-lo de volta.
  static bool hiddenFor(AppState app) => app.startCardHidden && !allStartDone(items(app));

  static List<StartItem> items(AppState app) => teacherStartItems(
        hasStudent: app.students.isNotEmpty,
        hasTask: app.students.any((s) => s.tasks.isNotEmpty),
        delivered: app.students.any((s) => s.linkState == 'active' && s.tasks.any((t) => t.sent != false)),
      );

  String _first(Student s) => app.labelOf(s).split(' ').first;

  /// O botão grande: o que fazer agora para o próximo passo que falta.
  (String, IconData, VoidCallback) _next(BuildContext context, StartItem i) {
    final active = [for (final s in app.students) if (!s.paused) s];
    void open(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    switch (i.id) {
      case 'student':
        return (tr('Adicionar o primeiro aluno'), Icons.person_add_alt_1, () => showAddStudent(context, app));
      case 'task':
        // Quem já pode receber vem primeiro; senão, o cadastrado por último.
        final linked = active.where((s) => s.linkState == 'active').toList();
        final recent = [...active]..sort((a, b) => b.created.compareTo(a.created));
        final s = linked.isNotEmpty ? linked.first : (recent.isEmpty ? null : recent.first);
        return (tr('Passar a primeira tarefa'), Icons.add_task_rounded, () => s == null ? open(TeacherPage(app: app)) : openStudentNewTask(context, app, s.id));
      default:
        final waiting = active.where((s) => s.linkState == 'active' && s.tasks.any((t) => t.sent == false)).toList();
        if (waiting.isEmpty) return (tr('Convidar o aluno para receber'), Icons.send_rounded, () => shareTeacherInvite(context, app));
        final s = waiting.first;
        return app.deliveryFor(s).canSend
            ? (tr('Enviar a tarefa para {0}', [_first(s)]), Icons.send_rounded, () async {
                if (await ensureTeacherLink(context, app, tr('Para a tarefa chegar ao aluno, o app precisa conectar.'))) app.say(app.sendPendingTasks(s));
              })
            : (tr('Ficha de {0}', [_first(s)]), Icons.person_outline, () => open(StudentPage(app: app, studentId: s.id)));
    }
  }

  Widget _step(int n, StartItem i, bool current) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i.done ? AppColors.accent : Colors.transparent,
              border: Border.all(color: i.done || current ? AppColors.accent : AppColors.outline, width: current ? 2 : 1),
            ),
            child: i.done
                ? Icon(Icons.check, size: 16, color: AppColors.bg)
                : Text('$n', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: current ? AppColors.text : AppColors.textDim)),
          ),
          const SizedBox(width: Ds.s12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(i.title,
                    style: TextStyle(
                        fontSize: Ds.fontBody,
                        height: 1.25,
                        fontWeight: current ? FontWeight.w800 : FontWeight.w600,
                        decoration: i.done ? TextDecoration.lineThrough : null,
                        color: current ? AppColors.text : AppColors.textDim)),
              ),
              if (current) Text(i.hint, style: Ds.support()),
            ]),
          ),
        ]),
      );

  Future<void> _tour(BuildContext context) async {
    final ok = await runTour(context, [
      TourStep(TourKeys.startCard, tr('O que fazer primeiro'), tr('Adicione um aluno, passe a tarefa da aula e faça ela chegar nele. O botão leva ao próximo passo.')),
      TourStep(TourKeys.hubStudents, tr('Seus alunos'), tr('A ficha de cada aluno, as tarefas que você passou e o que ele já fez.')),
      TourStep(TourKeys.hubAgenda, tr('Agenda completa'), tr('Veja a semana ou o mês, marque aulas e mude horários. Tem remarcar só uma aula e pausar as férias.')),
      TourStep(TourKeys.hubOpenSlots, tr('Horários livres'), tr('Publique horários e o primeiro aluno que pegar fica com ele. A aula entra na agenda dos dois.')),
    ]);
    if (ok) app.markTourSeen('hub_teacher');
  }

  @override
  Widget build(BuildContext context) {
    final list = items(app);
    final next = nextStartItem(list) ?? list.last;
    final (label, icon, action) = _next(context, next);
    return Container(
      key: TourKeys.startCard,
      padding: const EdgeInsets.fromLTRB(Ds.s20, Ds.s20, Ds.s20, Ds.s8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Ds.radiusCard),
        border: Border.all(color: AppColors.accent, width: 1.6),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Ajude seu aluno a estudar entre uma aula e outra'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, height: 1.2)),
        const SizedBox(height: Ds.s12),
        for (var n = 0; n < list.length; n++) _step(n + 1, list[n], identical(list[n], next)),
        const SizedBox(height: Ds.s12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: action,
            icon: Icon(icon, size: 20),
            label: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        ),
        const SizedBox(height: Ds.s4),
        Row(children: [
          TextButton.icon(onPressed: () => _tour(context), icon: const Icon(Icons.play_circle_outline, size: 18), label: Text(tr('Ver como funciona'))),
          const Spacer(),
          TextButton(
            onPressed: () {
              final messenger = ScaffoldMessenger.of(context); // antes de esconder: o cartão some e leva o contexto junto
              app.hideStartCard();
              showUndoSnack(messenger,
                  message: tr('Primeiros passos escondidos. Para ver de novo, toque em "Mostrar o tutorial" no Meu espaço.'),
                  undoLabel: tr('Desfazer'),
                  onUndo: app.showStartCard);
            },
            child: Text(tr('Esconder')),
          ),
        ]),
      ]),
    );
  }
}

/// Linha que fica no lugar do cartão escondido: um toque traz o "Comece por aqui" de volta (e o "Ver como funciona" está nele).
class StartCardReturn extends StatelessWidget {
  final AppState app;
  const StartCardReturn({super.key, required this.app});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Ds.s8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(Ds.tap, Ds.tap)),
            onPressed: app.showStartCard,
            icon: const Icon(Icons.school_outlined, size: 20),
            label: Text(tr('Mostrar o tutorial')),
          ),
        ),
      );
}
