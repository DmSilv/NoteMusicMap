import 'package:flutter/material.dart';

import '../app_state.dart';
import 'feedback_sheet.dart';
import 'study_timers.dart';
import 'progress_cards.dart';
import 'hub_section.dart';
import 'perf.dart';
import 'theme.dart';
import 'widgets.dart';

class StudyPage extends StatelessWidget {
  final AppState app;
  final bool active;
  const StudyPage({super.key, required this.app, this.active = true});

  static const _dias = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: active ? app : kNeverNotifies,
      builder: (context, _) {
        final today = DateTime.now();
        final days = [for (var i = 6; i >= 0; i--) today.subtract(Duration(days: i))];
        final mins = [for (final d in days) (app.studySeconds[AppState.dayKey(d)] ?? 0) / 60];
        final goal = app.dailyGoalMinutes;
        final todayMin = app.todaySeconds / 60;
        final maxV = [goal, ...mins].reduce((a, b) => a > b ? a : b).clamp(5.0, 600.0);
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

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            // Hub por papel: destaque (o que importa agora), blocos que pedem ação e ferramentas.
            HubSection(app: app),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
              child: Text('Seu estudo', style: TextStyle(color: AppColors.textDim, fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
            FeedbackInviteCard(app: app),
            StudyTimerSection(app: app),
            const SizedBox(height: 12),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Hoje', style: TextStyle(color: AppColors.textDim)),
                            Text('${todayMin.floor()} min',
                                style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Dias seguidos', style: TextStyle(color: AppColors.textDim)),
                          Text('$streak',
                              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      minHeight: 10,
                      value: (todayMin / goal).clamp(0.0, 1.0),
                      backgroundColor: AppColors.surface2,
                      color: todayMin >= goal ? AppColors.inTune : AppColors.flat,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('Meta diária: ${goal.round()} min',
                      style: TextStyle(color: AppColors.textDim, fontSize: 13)),
                  Slider(
                    min: 5,
                    max: 120,
                    divisions: 23,
                    value: goal.clamp(5, 120),
                    onChanged: (v) => app.setTuning(dailyGoalMinutes: v),
                  ),
                  Text(
                    'Conta o tempo com o metrônomo ligado ou tocando no microfone.',
                    style: TextStyle(color: AppColors.textDim, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Últimos 7 dias', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
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
                                    style: TextStyle(fontSize: 11, color: AppColors.textDim)),
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
                                    style: TextStyle(fontSize: 12, color: AppColors.textDim)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            EvolutionCard(app: app),
            const SizedBox(height: 12),
            CoachCard(app: app),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Apagar histórico?'),
                    content: const Text('Isso remove o tempo de estudo e as escalas salvas deste aparelho. Não dá para desfazer.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                      FilledButton.icon(onPressed: () => Navigator.pop(ctx, true), icon: const Icon(Icons.delete_outline, size: 18), label: const Text('Apagar')),
                    ],
                  ),
                );
                if (ok == true) await app.clearHistory();
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Apagar histórico'),
            ),
          ],
        );
      },
    );
  }
}
