import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../agenda_page.dart';
import '../design_system.dart';
import '../teacher_page.dart';
import '../theme.dart';
import 'tour.dart';

/// "Comece por aqui": três passos para o professor novo (vincular, marcar aula, passar tarefa), com o progresso,
/// um atalho para cada passo e o tutorial "Ver como funciona". Some sozinho quando tudo foi feito e dá para esconder.
class StartCard extends StatelessWidget {
  final AppState app;
  const StartCard({super.key, required this.app});

  /// Mostrar o cartão? (professor, não escondido, e ainda falta algum passo)
  static bool visibleFor(AppState app) => !app.startCardHidden && !allStartDone(items(app));

  static List<StartItem> items(AppState app) => teacherStartItems(
        hasLinkedStudent: app.students.any((s) => s.linkState == 'active'),
        hasClass: app.agenda.any((s) => !s.canceled),
        hasTask: app.students.any((s) => s.tasks.isNotEmpty),
      );

  void _open(BuildContext context, StartItem i) {
    final nav = Navigator.of(context);
    switch (i.id) {
      case 'link':
        nav.push(MaterialPageRoute<void>(builder: (_) => TeacherPage(app: app)));
      case 'class':
        nav.push(MaterialPageRoute<void>(builder: (_) => AgendaPage(app: app)));
      default:
        final s = app.students.isEmpty ? null : app.students.first;
        nav.push(MaterialPageRoute<void>(builder: (_) => s == null ? TeacherPage(app: app) : StudentPage(app: app, studentId: s.id)));
    }
  }

  Future<void> _tour(BuildContext context) async {
    final ok = await runTour(context, [
      TourStep(TourKeys.startCard, 'Comece por aqui', 'Três passos para o app render: vincular um aluno, marcar uma aula e passar uma tarefa.'),
      TourStep(TourKeys.hubAgenda, 'Agenda completa', 'Veja a semana ou o mês, marque aulas e mude horários. Tem remarcar só uma aula e pausar as férias.'),
      TourStep(TourKeys.hubOpenSlots, 'Horários livres', 'Publique horários e o primeiro aluno que pegar fica com ele. A aula entra na agenda dos dois.'),
      TourStep(TourKeys.hubStudents, 'Seus alunos', 'A ficha de cada aluno, as tarefas que você passou e o que ele já fez.'),
    ]);
    if (ok) app.markTourSeen('hub_teacher');
  }

  @override
  Widget build(BuildContext context) {
    final list = items(app);
    final done = startDoneCount(list);
    final next = nextStartItem(list);
    return Container(
      key: TourKeys.startCard,
      margin: const EdgeInsets.only(top: Ds.s12),
      padding: const EdgeInsets.fromLTRB(Ds.s16, Ds.s16, Ds.s16, Ds.s8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Ds.radiusCard),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Comece por aqui', style: Ds.title())),
          Text('$done de ${list.length}', style: Ds.support()),
        ]),
        const SizedBox(height: Ds.s8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: done / list.length),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            builder: (c, v, _) => LinearProgressIndicator(value: v, minHeight: 6, backgroundColor: AppColors.outline, color: AppColors.accent),
          ),
        ),
        const SizedBox(height: Ds.s8),
        for (final i in list)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(i.done ? Icons.check_circle : Icons.radio_button_unchecked,
                color: i.done ? AppColors.accent : (identical(i, next) ? AppColors.text : AppColors.textDim)),
            title: Text(i.title,
                style: TextStyle(
                    fontWeight: identical(i, next) ? FontWeight.w800 : FontWeight.w600,
                    decoration: i.done ? TextDecoration.lineThrough : null,
                    color: i.done ? AppColors.textDim : null)),
            subtitle: i.done ? null : Text(i.hint, style: Ds.support()),
            trailing: i.done ? null : const Icon(Icons.chevron_right),
            onTap: i.done ? null : () => _open(context, i),
          ),
        Row(children: [
          TextButton.icon(onPressed: () => _tour(context), icon: const Icon(Icons.play_circle_outline, size: 18), label: const Text('Ver como funciona')),
          const Spacer(),
          TextButton(onPressed: app.hideStartCard, child: const Text('Esconder')),
        ]),
      ]),
    );
  }
}
