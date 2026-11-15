import 'package:flutter/material.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'progress_cards.dart';
import 'theme.dart';
import 'widgets.dart';
import 'package:afina_core/afina_core.dart';

/// "Evolução": segunda tela do Meu espaço, com os dados de estudo e os gráficos
/// (últimos 7 dias, taxa de acerto nas escalas e orientações do treinador).
class EvolutionPage extends StatelessWidget {
  final AppState app;
  const EvolutionPage({super.key, required this.app});

  static final _dias = [tr('seg'), tr('ter'), tr('qua'), tr('qui'), tr('sex'), tr('sáb'), tr('dom')];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Evolução'))),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: app,
          builder: (context, _) => ListView(
            padding: Ds.screen,
            children: [
              _summary(),
              const DsGap(Ds.gap),
              _week(),
              const DsGap(Ds.gap),
              EvolutionCard(app: app),
              const DsGap(Ds.gap),
              CoachCard(app: app),
            ],
          ),
        ),
      ),
    );
  }

  /// Resumo da semana: total de minutos, dias estudados, dias da meta e a comparação com a semana anterior.
  Widget _summary() {
    final w = weekSummary(app.studySeconds, DateTime.now(), app.dailyGoalMinutes);
    final cmp = w.delta == 0
        ? tr('Igual à semana passada.')
        : w.delta > 0
            ? tr('{0} min a mais que na semana passada.', [w.delta])
            : tr('{0} min a menos que na semana passada.', [-w.delta]);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Esta semana'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: Ds.fontBody)),
          const SizedBox(height: Ds.s8),
          if (w.empty)
            Text(tr('Comece com poucos minutos hoje: o resumo da semana aparece aqui.'), style: Ds.support())
          else ...[
            Text(tr('{0} min', [w.minutes]), style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800)),
            const SizedBox(height: Ds.s4),
            Text(tr('{0} de 7 dias estudados · meta batida {1}×', [w.daysStudied, w.goalDays]), style: Ds.support()),
            const SizedBox(height: Ds.s4),
            Text(cmp, style: Ds.support()),
          ],
        ],
      ),
    );
  }

  /// Minutos estudados nos últimos 7 dias, em barras; verde quando bateu a meta.
  Widget _week() {
    final today = DateTime.now();
    final days = [for (var i = 6; i >= 0; i--) today.subtract(Duration(days: i))];
    final mins = [for (final d in days) (app.studySeconds[AppState.dayKey(d)] ?? 0) / 60];
    final goal = app.dailyGoalMinutes;
    final maxV = [goal, ...mins].reduce((a, b) => a > b ? a : b).clamp(5.0, 600.0);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Últimos 7 dias'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: Ds.fontBody)),
          const SizedBox(height: Ds.s16),
          SizedBox(
            height: 130,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(mins[i] < 1 ? '' : '${mins[i].round()}',
                            style: TextStyle(fontSize: Ds.fontLabel, color: AppColors.textDim)),
                        const SizedBox(height: 2),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          height: (mins[i] / maxV * 90).clamp(3.0, 90.0),
                          decoration: BoxDecoration(
                            color: mins[i] >= goal ? AppColors.inTune : AppColors.flat,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(_dias[days[i].weekday - 1],
                            style: TextStyle(fontSize: Ds.fontLabel, color: AppColors.textDim)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Ds.s8),
          Text(tr('Meta diária: {0} min', [goal.round()]), style: Ds.support()),
        ],
      ),
    );
  }
}
