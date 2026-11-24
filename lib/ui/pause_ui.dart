import 'package:flutter/material.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'plan_page.dart';
import 'theme.dart';
import 'widgets.dart';
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
      final code = s.code;
      final n = s.paused && code != null ? app.futureClassesOf(code) : 0;
      if (n > 0) {
        final cancel = await showDsConfirm(
          context,
          title: tr('Cancelar as aulas futuras de {0}?', [name]),
          body: tr('{0} ainda tem aulas marcadas pela frente. Se cancelar, ele é avisado e a sua agenda fica livre. Dá para desfazer logo depois.', [name]),
          confirmLabel: tr('Cancelar as aulas'),
          cancelLabel: tr('Manter as aulas'),
          icon: Icons.event_busy_rounded,
        );
        if (cancel) app.cancelStudentClasses(code!);
      }
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

/// PROFESSOR: o que ESTE aluno pode fazer na agenda (pegar horários livres e mandar avisos). Tudo ligado por padrão.
Future<void> showStudentControlSheet(BuildContext context, AppState app, Student s) {
  return showDsSheet(context, title: tr('Controle do aluno'), listenable: app, children: (c) {
    final linked = s.code != null && s.linkState == 'active';
    if (!linked) {
      return [Text(tr('Estas opções valem quando o aluno está vinculado online. Depois do vínculo, você decide aqui o que {0} pode fazer na agenda.', [app.labelOf(s)]), style: Ds.support())];
    }
    return [
      Text(tr('A agenda é sua. Aqui você escolhe o que {0} pode fazer sozinho.', [app.labelOf(s)]), style: Ds.support()),
      const SizedBox(height: Ds.s12),
      AppCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          SwitchListTile(
            secondary: Icon(Icons.add_task_rounded, color: AppColors.textDim),
            title: Text(tr('Pode pegar horários livres'), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              s.noPick ? tr('Desligado: {0} não vê os seus horários livres. Você marca as aulas com ele.', [app.labelOf(s)]) : tr('Ligado: {0} vê os horários livres (os que você liberou) e pega ou pede.', [app.labelOf(s)]),
              style: Ds.support(),
            ),
            value: !s.noPick,
            onChanged: (v) async {
              final err = await app.setStudentCanPick(s, v);
              if (err != null) app.say(err);
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: Icon(Icons.mark_email_unread_outlined, color: AppColors.textDim),
            title: Text(tr('Recebo os avisos dele'), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              s.muted ? tr('Silenciado: se {0} tentar avisar, ele vê que deve falar com você direto.', [app.labelOf(s)]) : tr('Ligado: {0} pode avisar "não vou" ou "queria remarcar". A aula só muda quando você decide.', [app.labelOf(s)]),
              style: Ds.support(),
            ),
            value: !s.muted,
            onChanged: (v) async {
              final err = await app.setStudentWarnsMuted(s, !v);
              if (err != null) app.say(err);
            },
          ),
        ]),
      ),
    ];
  });
}
