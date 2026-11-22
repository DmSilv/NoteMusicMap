import 'package:flutter/material.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'progress_cards.dart';
import 'theme.dart';
import 'widgets.dart';
import 'package:afina_core/afina_core.dart';

/// "Evolução": os dados de estudo e os gráficos (resumo da semana, últimos 7 dias e taxa de acerto nas escalas). Mora na página Estudo,
/// na aba Evolução; as orientações ficam na aba Treinador.
class EvolutionBody extends StatelessWidget {
  final AppState app;
  const EvolutionBody({super.key, required this.app});

  static List<String> get _dias => [tr('seg'), tr('ter'), tr('qua'), tr('qui'), tr('sex'), tr('sáb'), tr('dom')];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => ListView(
        padding: Ds.screen,
        children: [
          _summary(),
          const DsGap(Ds.gap),
          _week(),
          const DsGap(Ds.gap),
          EvolutionCard(app: app),
        ],
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

  /// Minutos estudados em cada um dos últimos 7 dias: verde quando bateu a meta, cinza quando ficou abaixo; a linha tracejada é a meta.
  Widget _week() {
    final today = DateTime.now();
    final days = [for (var i = 6; i >= 0; i--) today.subtract(Duration(days: i))];
    final mins = [for (final d in days) (app.studySeconds[AppState.dayKey(d)] ?? 0) / 60];
    final goal = app.dailyGoalMinutes;
    final maxV = [goal, ...mins].reduce((a, b) => a > b ? a : b).clamp(5.0, 600.0);
    const barArea = 96.0; // altura da maior barra
    const labelH = 22.0; // espaço do nome do dia embaixo
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DsCardTitle(Icons.bar_chart_rounded, tr('Minutos por dia'), subtitle: tr('Os últimos 7 dias. A linha tracejada é a sua meta.')),
          const SizedBox(height: Ds.s16),
          SizedBox(
            height: barArea + labelH + 20,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: labelH + goal / maxV * barArea,
                  child: CustomPaint(size: const Size(double.infinity, 1), painter: _DashPainter(AppColors.inTune.withValues(alpha: 0.7))),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(mins[i] < 1 ? '' : '${mins[i].round()}',
                                style: TextStyle(fontSize: Ds.fontLabel, fontWeight: FontWeight.w700, color: mins[i] >= goal ? AppColors.inTune : AppColors.textDim)),
                            const SizedBox(height: 2),
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 7),
                              height: (mins[i] / maxV * barArea).clamp(3.0, barArea),
                              decoration: BoxDecoration(
                                color: mins[i] >= goal ? AppColors.inTune : AppColors.textDim.withValues(alpha: mins[i] < 1 ? 0.25 : 0.5),
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                            SizedBox(
                              height: labelH,
                              child: Center(
                                child: Text(i == 6 ? tr('hoje') : _dias[days[i].weekday - 1],
                                    style: TextStyle(fontSize: Ds.fontLabel, fontWeight: i == 6 ? FontWeight.w800 : FontWeight.w400, color: i == 6 ? AppColors.text : AppColors.textDim)),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: Ds.s8),
          Wrap(spacing: Ds.s12, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
            _key(AppColors.inTune, tr('Bateu a meta')),
            _key(AppColors.textDim.withValues(alpha: 0.5), tr('Abaixo da meta')),
            Text(tr('Meta diária: {0} min', [goal.round()]), style: Ds.support()),
          ]),
        ],
      ),
    );
  }

  Widget _key(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 5),
        Text(t, style: Ds.support()),
      ]);
}

class _DashPainter extends CustomPainter {
  final Color color;
  _DashPainter(this.color);

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    for (var x = 0.0; x < s.width; x += 9) {
      canvas.drawLine(Offset(x, 0), Offset(x + 5, 0), p);
    }
  }

  @override
  bool shouldRepaint(_DashPainter o) => o.color != color;
}
