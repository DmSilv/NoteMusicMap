import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'evolution_page.dart';
import 'theme.dart';
import 'widgets.dart';

/// "Seu estudo" no Meu espaço de quem ainda não tem professor: o essencial numa olhada (hoje, dias seguidos e a meta).
/// O resto (gráficos, resumo da semana) fica na Evolução, um toque adiante.
class StudyGlanceCard extends StatelessWidget {
  final AppState app;
  const StudyGlanceCard({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final goal = app.dailyGoalMinutes;
    final todayMin = app.todaySeconds / 60;
    final streak = studyStreak(app.studySeconds, DateTime.now());
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DsCardTitle(
          Icons.auto_stories_rounded,
          tr('Seu estudo'),
          trailing: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EvolutionPage(app: app))),
            child: Text(tr('Evolução')),
          ),
        ),
        const SizedBox(height: Ds.s16),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Hoje'), style: Ds.support()),
              Text('${todayMin.floor()} min', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, height: 1.1)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(tr('Dias seguidos'), style: Ds.support()),
            Text('${streak.days}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, height: 1.1)),
          ]),
        ]),
        const SizedBox(height: Ds.s12),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            minHeight: 8,
            value: (todayMin / goal).clamp(0.0, 1.0),
            backgroundColor: AppColors.surface2,
            color: todayMin >= goal ? AppColors.inTune : AppColors.accent,
          ),
        ),
        const SizedBox(height: Ds.s8),
        Text(todayMin >= goal ? tr('Meta de hoje feita!') : tr('Meta diária: {0} min', [goal.round()]), style: Ds.support()),
      ]),
    );
  }
}
