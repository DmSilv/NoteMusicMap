import 'package:flutter/material.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'plan_page.dart';
import 'theme.dart';
import 'package:afina_core/afina_core.dart';

/// PROFESSOR: desativa ou reativa um aluno, com a explicação antes e o aviso do limite do plano grátis depois.
Future<void> togglePauseStudent(BuildContext context, AppState app, Student s) async {
  final name = app.labelOf(s);
  if (!s.paused) {
    final ok = await showDsConfirm(
      context,
      title: tr('Desativar {0}?', [name]),
      body: tr('O histórico, as tarefas e as observações ficam guardados. {0} sai do seu dia a dia, não recebe aulas novas e deixa de contar no limite do plano grátis. Você reativa quando quiser.', [name]),
      confirmLabel: tr('Desativar aluno'),
      icon: Icons.pause_circle_outline_rounded,
    );
    if (!ok) return;
  }
  final r = await app.setStudentPaused(s.id, !s.paused);
  if (!context.mounted) return;
  switch (r) {
    case null:
      app.say(s.paused ? tr('{0} foi desativado. O histórico ficou guardado.', [name]) : tr('{0} voltou para a sua lista.', [name]));
    case 'limit':
      final go = await showDsConfirm(
        context,
        title: tr('Limite do plano grátis'),
        body: tr('Você já tem {0} alunos ativos e o plano grátis vai até {1}. Desative outro aluno ou use o plano Pro, sem limite.', [app.activeStudentCount, AppState.kFreeStudents]),
        confirmLabel: tr('Ver o plano Pro'),
        icon: Icons.workspace_premium_rounded,
      );
      if (go && context.mounted) await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlanPage(app: app)));
    case 'wait':
      app.say(tr('Espere o vínculo com {0} ser confirmado e tente de novo.', [name]));
    default:
      app.say(tr('Sem conexão: não deu para avisar o servidor. Tente de novo.'));
  }
}

/// Faixa no topo da ficha do aluno desativado.
class PausedBanner extends StatelessWidget {
  final AppState app;
  final Student student;
  const PausedBanner({super.key, required this.app, required this.student});

  @override
  Widget build(BuildContext context) {
    if (!student.paused) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: Ds.gap),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Ds.s12),
        decoration: BoxDecoration(
          color: AppColors.attention.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(Ds.radiusControl),
          border: Border.all(color: AppColors.attention.withValues(alpha: 0.6)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.pause_circle_outline_rounded, color: AppColors.attention),
            const SizedBox(width: Ds.s8),
            Expanded(child: Text(tr('Aluno desativado'), style: const TextStyle(fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: Ds.s4),
          Text(tr('O histórico está guardado. Ele não recebe aulas novas nem conta no limite do plano grátis.'), style: Ds.support()),
          const SizedBox(height: Ds.s8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(Ds.tap)),
            onPressed: () => togglePauseStudent(context, app, student),
            icon: const Icon(Icons.play_circle_outline_rounded),
            label: Text(tr('Reativar aluno')),
          ),
        ]),
      ),
    );
  }
}
