import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'theme.dart';
import 'widgets.dart' show AppCard;

/// Alguém entrou pelo convite e o professor já tinha alunos cadastrados só pelo nome: é um deles? Juntar leva o vínculo para o
/// cadastro do professor (com as tarefas que esperavam). Um de cada vez; quem decide é o professor.
class JoinStudentCard extends StatelessWidget {
  final AppState app;
  const JoinStudentCard({super.key, required this.app});

  Future<void> _join(BuildContext context, Student linked, Student local) async {
    final waiting = local.tasks.where((t) => t.sent == false).length;
    final ok = await showDsConfirm(
      context,
      title: tr('É a mesma pessoa?'),
      body: waiting > 0
          ? tr('{0} fica no cadastro "{1}". As tarefas que esperavam serão enviadas.', [linked.name, local.name])
          : tr('{0} fica no cadastro "{1}".', [linked.name, local.name]),
      icon: Icons.link_rounded,
      confirmLabel: tr('Sim, é a mesma pessoa'),
    );
    if (!ok) return;
    final sent = app.joinStudents(linked, local);
    app.say(sent ?? tr('Pronto: "{0}" já recebe as suas tarefas.', [local.name]));
  }

  Future<void> _others(BuildContext context, Student linked, List<Student> all) => showDsSheet(
        context,
        title: tr('Quem é {0}?', [linked.name]),
        listenable: app,
        children: (c) => [
          for (final s in all)
            DsNavRow(Icons.person_outline, s.name, '', () {
              Navigator.of(c).pop();
              _join(context, linked, s);
            }),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final offers = app.joinOffers;
    if (offers.isEmpty) return const SizedBox.shrink();
    final (linked, candidates) = offers.first;
    final shown = candidates.take(3).toList();
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DsCardTitle(Icons.how_to_reg_outlined, tr('{0} entrou pelo seu convite', [linked.name]),
            subtitle: tr('É um aluno que você já cadastrou pelo nome?')),
        const SizedBox(height: Ds.s12),
        for (final s in shown) ...[
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(Ds.tap)),
            onPressed: () => _join(context, linked, s),
            child: Text(tr('É {0}', [s.name]), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(height: Ds.s8),
        ],
        Wrap(alignment: WrapAlignment.spaceBetween, children: [
          if (candidates.length > shown.length)
            TextButton(onPressed: () => _others(context, linked, candidates), child: Text(tr('Ver outros nomes'))),
          TextButton(
            onPressed: () => app.dismissJoin(linked),
            child: Text(tr('Não, é outro aluno'), style: TextStyle(color: AppColors.textDim)),
          ),
        ]),
      ]),
    );
  }
}
