import 'package:flutter/material.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'feedback_sheet.dart';
import 'hub_section.dart';
import 'library_page.dart';
import 'perf.dart';
import 'theme.dart';
import 'widgets.dart';
import 'package:afina_core/afina_core.dart';

/// "Meu espaço": o foco é a AGENDA (próxima aula e o que vem depois), os alunos, as tarefas e o acervo.
/// O estudo (resumo, cronômetro e Pomodoro) mora na aba Metrônomo (`study_card.dart`).
class StudyPage extends StatelessWidget {
  final AppState app;
  final bool active;
  const StudyPage({super.key, required this.app, this.active = true});

  /// Há o que mostrar no cartão de material (acervo próprio de quem não é professor, ou material dos professores dele)?
  bool _hasMaterial() {
    if (app.hubView == HubView.teacher) return false;
    final own = app.libraryOn && !app.teacherMode;
    return own || app.myTeachers.any((t) => app.libraryTeachers.contains(t.code));
  }

  /// Acervo e repertório (só para professores liberados e seus alunos).
  Widget _materialCard(BuildContext context) {
    // Na visão de professor o acervo mora no cartão "Organização" do Meu espaço; aqui fica só o material de quem ensina o aluno.
    final asTeacher = app.hubView == HubView.teacher;
    final teachers = [for (final t in app.myTeachers) if (!asTeacher && app.libraryTeachers.contains(t.code)) t];
    // Quem também é professor tem o próprio acervo na visão de professor; na de aluno aparece só o material dos professores dele.
    final ownHere = app.libraryOn && !asTeacher && !app.teacherMode;
    final both = ownHere && teachers.isNotEmpty;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        if (ownHere)
          _row(Icons.library_books_rounded, tr('Acervo e repertório'), tr('Seus métodos e peças, com link'), () => openLibrary(context, app)),
        if (both) const Divider(height: 1),
        for (final t in teachers)
          _row(Icons.folder_open_rounded, tr('Material de {0}', [t.name.isEmpty ? tr('seu professor') : t.name]), tr('Métodos e peças indicados'), () => openLibrary(context, app, teacher: t.code, teacherName: t.name)),
      ]),
    );
  }

  Widget _row(IconData icon, String title, String sub, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Ds.cardPad, vertical: Ds.s12),
          child: Row(children: [
            DsIconBadge(icon, size: 36),
            const SizedBox(width: Ds.s12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: Ds.fontBody, fontWeight: FontWeight.w700)),
                Text(sub, style: Ds.support()),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: active ? app : kNeverNotifies,
      builder: (context, _) {
        // Puxar para baixo atualiza (aluno: aulas e tarefas novas; professor: o que os alunos fizeram).
        return RefreshIndicator(
          onRefresh: app.syncLinks,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: Ds.screen,
            children: [
              // Agenda: próxima aula, as seguintes e os atalhos (marcar, horários livres, agenda completa).
              HubSection(app: app),
              const DsGap(Ds.gap),
              if (_hasMaterial()) ...[_materialCard(context), const DsGap(Ds.gap)],
              FeedbackInviteCard(app: app),
            ],
          ),
        );
      },
    );
  }
}
