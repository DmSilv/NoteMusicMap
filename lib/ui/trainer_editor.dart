import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import 'design_system.dart';
import 'theme.dart';

/// Ajustes do "Acelerar aos poucos", em quatro perguntas simples e um resumo em frase:
/// 1. Quando aumentar (por tempo ou por compassos), 2. Quanto aumentar, 3. Até quantos BPM, 4. "Fica assim: …".
/// Só botões de escolha e um "−/+" para o teto (nada de controle deslizante com centenas de passos).
/// Não conhece o app: recebe o treino atual e devolve o novo em [onChanged].
class TrainerEditor extends StatelessWidget {
  final TempoTrainer value;

  /// BPM de partida (o que está na tela do metrônomo) e tempos por compasso, para o resumo.
  final double startBpm;
  final int beatsPerBar;
  final ValueChanged<TempoTrainer> onChanged;
  const TrainerEditor({super.key, required this.value, required this.startBpm, required this.beatsPerBar, required this.onChanged});

  Widget _title(String t, {String? help}) => Padding(
        padding: const EdgeInsets.only(top: Ds.s20, bottom: Ds.s8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: const TextStyle(fontSize: Ds.fontBody, fontWeight: FontWeight.w800)),
          if (help != null) Text(help, style: Ds.support()),
        ]),
      );

  /// Uma fileira de botões de escolha; se o valor atual não estiver nas opções (dado antigo), ele aparece também.
  Widget _chips<T extends num>(List<T> options, T current, String Function(T) label, ValueChanged<T> on) {
    final all = options.contains(current) ? options : ([...options, current]..sort());
    return Wrap(spacing: Ds.s8, runSpacing: Ds.s8, children: [
      for (final o in all)
        ChoiceChip(
          label: Text(label(o), style: const TextStyle(fontWeight: FontWeight.w700)),
          selected: o == current,
          onSelected: (_) => on(o),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final t = value;
    final max = t.maxBpm.round();
    final up = (t.maxBpm - startBpm).round();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title('Quando aumentar', help: t.byTime ? 'O aumento entra no começo do próximo compasso.' : 'Conta os compassos tocados (depois da contagem inicial).'),
      SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: true, icon: Icon(Icons.timer_outlined, size: 18), label: Text('Por tempo')),
          ButtonSegment(value: false, icon: Icon(Icons.queue_music_rounded, size: 18), label: Text('Por compassos')),
        ],
        selected: {t.byTime},
        onSelectionChanged: (s) => onChanged(s.first ? t.copyWith(everySeconds: 30) : t.copyWith(everySeconds: 0)),
      ),
      const SizedBox(height: Ds.s12),
      if (t.byTime)
        _chips<int>(kTrainerSecondsOptions, t.everySeconds, (s) => s < 60 ? '$s s' : '${s ~/ 60} min${s % 60 == 0 ? '' : ' ${s % 60} s'}', (v) => onChanged(t.copyWith(everySeconds: v)))
      else
        _chips<int>(kTrainerBarsOptions, t.everyBars, (b) => '$b compassos', (v) => onChanged(t.copyWith(everyBars: v))),
      _title('Quanto aumentar a cada vez'),
      _chips<int>(kTrainerStepOptions, t.stepBpm.round(), (s) => '+$s BPM', (v) => onChanged(t.copyWith(stepBpm: v.toDouble()))),
      _title('Até quantos BPM (o teto)', help: 'Quando chegar aqui, o metrônomo para de acelerar e segue nesse andamento.'),
      Row(children: [
        IconButton.filledTonal(
          tooltip: 'Diminuir o teto em 5',
          iconSize: 26,
          onPressed: t.maxBpm - 5 >= kTrainerMinBpm ? () => onChanged(t.copyWith(maxBpm: t.maxBpm - 5)) : null,
          icon: const Icon(Icons.remove),
        ),
        Expanded(
          child: Semantics(
            label: 'Teto de $max batidas por minuto',
            child: Column(children: [
              Text('$max', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, height: 1.1)),
              Text('BPM', style: Ds.support()),
            ]),
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Aumentar o teto em 5',
          iconSize: 26,
          onPressed: t.maxBpm + 5 <= kTrainerMaxBpm ? () => onChanged(t.copyWith(maxBpm: t.maxBpm + 5)) : null,
          icon: const Icon(Icons.add),
        ),
      ]),
      const SizedBox(height: Ds.s8),
      Wrap(spacing: Ds.s8, runSpacing: Ds.s8, children: [
        for (final u in kTrainerUpOptions)
          ChoiceChip(
            label: Text('${(startBpm + u).round()} (+$u)', style: const TextStyle(fontWeight: FontWeight.w700)),
            selected: up == u,
            onSelected: (_) => onChanged(t.copyWith(maxBpm: (startBpm + u).clamp(kTrainerMinBpm, kTrainerMaxBpm).toDouble())),
          ),
      ]),
      const SizedBox(height: Ds.s20),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Ds.s16),
        decoration: BoxDecoration(
          color: (startBpm >= t.maxBpm ? AppColors.sharp : AppColors.accent).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(Ds.radiusControl + 4),
          border: Border.all(color: (startBpm >= t.maxBpm ? AppColors.sharp : AppColors.accent).withValues(alpha: 0.4)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(startBpm >= t.maxBpm ? Icons.error_outline_rounded : Icons.speed_rounded, color: startBpm >= t.maxBpm ? AppColors.sharp : AppColors.accent),
          const SizedBox(width: Ds.s12),
          Expanded(child: Text(trainerSummary(t, startBpm, beatsPerBar), style: const TextStyle(fontSize: 15, height: 1.4, fontWeight: FontWeight.w600))),
        ]),
      ),
    ]);
  }
}
