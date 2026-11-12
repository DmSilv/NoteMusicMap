import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'theme.dart';
import 'trainer_editor.dart';
import 'widgets.dart';

/// "Acelerar aos poucos" na tela do metrônomo: liga e desliga num toque, mostra o resumo em frase e, tocando, mostra o BPM que
/// subiu, quanto falta para o próximo aumento e o caminho até o teto. Os ajustes ficam numa janela ("Ajustar").
class SpeedTrainerCard extends StatelessWidget {
  final AppState app;
  const SpeedTrainerCard({super.key, required this.app});

  void _openSheet(BuildContext context) {
    showDsSheet(
      context,
      title: tr('Acelerar aos poucos'),
      listenable: app,
      children: (c) {
        final m = app.metro;
        return [
          TrainerEditor(
            value: m.trainer ?? app.trainerForNow(),
            startBpm: m.bpm,
            beatsPerBar: m.beatsPerBar,
            onChanged: app.setTrainer,
          ),
        ];
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final m = app.metro;
        final t = m.trainer;
        final on = t != null;
        return AppCard(
          padding: const EdgeInsets.symmetric(horizontal: Ds.cardPad, vertical: Ds.s8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(Icons.speed_rounded, color: on ? AppColors.accent : AppColors.textDim),
              title: Text(tr('Acelerar aos poucos'), style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(
                on ? trainerSummary(t, m.bpm, m.beatsPerBar) : tr('O metrônomo sobe a velocidade sozinho, de tempos em tempos.'),
                style: const TextStyle(fontSize: Ds.fontLabel, height: 1.35),
              ),
              value: on,
              onChanged: (v) => app.setTrainer(v ? app.trainerForNow() : null),
            ),
            if (on) ...[
              ValueListenableBuilder<MetroBeat>(
                valueListenable: app.metroBeat,
                builder: (context, b, _) => app.metroRunning && b.bar >= 0 && b.bpm > 0 ? _live(t, m.bpm, b) : const SizedBox.shrink(),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: Ds.s8),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _openSheet(context),
                    icon: const Icon(Icons.tune, size: 18),
                    label: Text(tr('Ajustar')),
                  ),
                ),
              ),
            ],
          ]),
        );
      },
    );
  }

  /// Enquanto toca: o BPM de agora, o caminho até o teto e quanto falta para o próximo aumento.
  Widget _live(TempoTrainer t, double startBpm, MetroBeat b) {
    final span = t.maxBpm - startBpm;
    final path = span <= 0 ? 1.0 : ((b.bpm - startBpm) / span).clamp(0.0, 1.0);
    final total = t.byTime ? t.everySeconds.toDouble() : t.everyBars.toDouble();
    final left = b.trainerLeft;
    final next = (left == null || b.trainerAtMax || total <= 0) ? (b.trainerAtMax ? 1.0 : 0.0) : (1 - left / total).clamp(0.0, 1.0);
    return Container(
      margin: const EdgeInsets.only(bottom: Ds.s8),
      padding: const EdgeInsets.all(Ds.s12),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Ds.radiusControl + 4),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${b.bpm.round()}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, height: 1.0)),
          const SizedBox(width: Ds.s8),
          Expanded(child: Text(tr('BPM agora · teto {0}', [t.maxBpm.round()]), style: Ds.support())),
        ]),
        const SizedBox(height: Ds.s8),
        Text(trainerLiveText(atMax: b.trainerAtMax, byTime: b.trainerByTime, left: left, stepBpm: t.stepBpm),
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: b.trainerAtMax ? AppColors.inTune : AppColors.text)),
        const SizedBox(height: Ds.s8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(minHeight: 8, value: next, backgroundColor: AppColors.surface2, color: AppColors.accent),
        ),
        const SizedBox(height: Ds.s8),
        Row(children: [
          Text(tr('Até o teto'), style: Ds.support().copyWith(fontSize: 12.5)),
          const SizedBox(width: Ds.s8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(minHeight: 4, value: path, backgroundColor: AppColors.surface2, color: AppColors.flat),
            ),
          ),
        ]),
      ]),
    );
  }
}
