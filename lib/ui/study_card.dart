import 'package:flutter/material.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'evolution_page.dart';
import 'study_timers.dart';
import 'theme.dart';
import 'widgets.dart';
import 'package:afina_core/afina_core.dart';

/// "Seu estudo": o tempo estudado hoje, os dias seguidos, a meta diária e o cronômetro/Pomodoro num cartão só.
/// Mora na aba Metrônomo (onde a pessoa já está praticando); os dados e gráficos ficam na tela "Evolução".
class StudyCard extends StatelessWidget {
  final AppState app;
  const StudyCard({super.key, required this.app});

  /// Modal de ajustes do estudo: meta diária e apagar o histórico.
  void _openSettings(BuildContext context) {
    showDsSheet(
      context,
      title: tr('Ajustes do estudo'),
      listenable: app,
      children: (c) => [
        DsSettingRow(
          label: tr('Meta diária: {0} min', [app.dailyGoalMinutes.round()]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Slider(
              min: 5,
              max: 120,
              divisions: 23,
              value: app.dailyGoalMinutes.clamp(5, 120),
              onChanged: (v) => app.setTuning(dailyGoalMinutes: v),
            ),
            Text(tr('Conta o tempo com o metrônomo ligado ou tocando no microfone.'), style: Ds.support()),
          ]),
        ),
        OutlinedButton.icon(
          onPressed: () => _confirmClear(c),
          icon: const Icon(Icons.delete_outline),
          label: Text(tr('Apagar histórico')),
        ),
      ],
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Apagar histórico?')),
        content: Text(tr('Isso remove o tempo de estudo e as escalas salvas deste aparelho. Não dá para desfazer.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancelar'))),
          FilledButton.icon(onPressed: () => Navigator.pop(ctx, true), icon: const Icon(Icons.delete_outline, size: 18), label: Text(tr('Apagar'))),
        ],
      ),
    );
    if (ok == true) await app.clearHistory();
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final goal = app.dailyGoalMinutes;
    final todayMin = app.todaySeconds / 60;
    var streak = 0;
    for (var i = 0;; i++) {
      final d = today.subtract(Duration(days: i));
      final s = app.studySeconds[AppState.dayKey(d)] ?? 0;
      if (s >= 60) {
        streak++;
      } else if (i == 0) {
        continue; // hoje ainda pode estar zerado
      } else {
        break;
      }
      if (i > 400) break;
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const DsIconBadge(Icons.auto_stories_rounded, size: 34),
            const SizedBox(width: Ds.s12),
            Expanded(child: Text(tr('Seu estudo'), style: TextStyle(fontSize: Ds.fontTitle - 2, fontWeight: FontWeight.w800))),
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EvolutionPage(app: app))),
              icon: const Icon(Icons.insights_rounded, size: 18),
              label: Text(tr('Evolução')),
            ),
          ]),
          const SizedBox(height: Ds.s8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Hoje'), style: Ds.support()),
                    Text('${todayMin.floor()} min', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(tr('Dias seguidos'), style: Ds.support()),
                  Text('$streak', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800)),
                ],
              ),
            ],
          ),
          const SizedBox(height: Ds.s8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: (todayMin / goal).clamp(0.0, 1.0),
              backgroundColor: AppColors.surface2,
              color: todayMin >= goal ? AppColors.inTune : AppColors.flat,
            ),
          ),
          const SizedBox(height: Ds.s8),
          Row(children: [
            Expanded(child: Text(tr('Meta diária: {0} min', [goal.round()]), style: Ds.support())),
            TextButton.icon(
              onPressed: () => _openSettings(context),
              icon: const Icon(Icons.tune, size: 18),
              label: Text(tr('Ajustar')),
            ),
          ]),
          const Divider(height: Ds.sectionGap),
          // O cronômetro entra no mesmo cartão (sem molduras próprias).
          FramelessScope(child: StudyTimerSection(app: app)),
        ],
      ),
    );
  }
}
