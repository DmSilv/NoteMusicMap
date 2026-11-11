import 'package:flutter/material.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'evolution_page.dart';
import 'feedback_sheet.dart';
import 'hub_section.dart';
import 'perf.dart';
import 'study_timers.dart';
import 'theme.dart';
import 'widgets.dart';

/// "Meu espaço": o foco é a AGENDA (próxima aula e o que vem depois). Embaixo, o estudo de hoje
/// num bloco só (resumo + cronômetro); dados e gráficos ficam na tela "Evolução".
class StudyPage extends StatelessWidget {
  final AppState app;
  final bool active;
  const StudyPage({super.key, required this.app, this.active = true});

  /// Modal de ajustes do estudo: meta diária e apagar o histórico.
  void _openSettings(BuildContext context) {
    showDsSheet(
      context,
      title: 'Ajustes do estudo',
      listenable: app,
      children: (c) => [
        DsSettingRow(
          label: 'Meta diária: ${app.dailyGoalMinutes.round()} min',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Slider(
              min: 5,
              max: 120,
              divisions: 23,
              value: app.dailyGoalMinutes.clamp(5, 120),
              onChanged: (v) => app.setTuning(dailyGoalMinutes: v),
            ),
            Text('Conta o tempo com o metrônomo ligado ou tocando no microfone.', style: Ds.support()),
          ]),
        ),
        OutlinedButton.icon(
          onPressed: () => _confirmClear(c),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Apagar histórico'),
        ),
      ],
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
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
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: active ? app : kNeverNotifies,
      builder: (context, _) {
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

        return ListView(
          padding: Ds.screen,
          children: [
            // Agenda: próxima aula, as seguintes e os atalhos (marcar, horários livres, agenda completa).
            HubSection(app: app),
            const DsGap(Ds.gap),
            // Estudo: resumo de hoje e cronômetro no MESMO bloco.
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Expanded(child: Text('Seu estudo', style: TextStyle(fontSize: Ds.fontTitle - 2, fontWeight: FontWeight.w800))),
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EvolutionPage(app: app))),
                      icon: const Icon(Icons.show_chart, size: 18),
                      label: const Text('Evolução'),
                    ),
                  ]),
                  const SizedBox(height: Ds.s8),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Hoje', style: Ds.support()),
                            Text('${todayMin.floor()} min', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Dias seguidos', style: Ds.support()),
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
                    Expanded(child: Text('Meta diária: ${goal.round()} min', style: Ds.support())),
                    TextButton.icon(
                      onPressed: () => _openSettings(context),
                      icon: const Icon(Icons.tune, size: 18),
                      label: const Text('Ajustar'),
                    ),
                  ]),
                  const Divider(height: Ds.sectionGap),
                  // O cronômetro entra no mesmo cartão (sem molduras próprias).
                  FramelessScope(child: StudyTimerSection(app: app)),
                ],
              ),
            ),
            const DsGap(Ds.gap),
            FeedbackInviteCard(app: app),
          ],
        );
      },
    );
  }
}
