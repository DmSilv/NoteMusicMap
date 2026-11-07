import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'needle.dart';
import 'theme.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.outline),
        ),
        // Material transparente: switches/listas desenham o toque aqui dentro.
        child: Material(type: MaterialType.transparency, child: child),
      );
}

/// Escala de -50 a +50 com faixa "afinada" e ponteiro de movimento fluido.
class NeedleGauge extends StatelessWidget {
  final double? cents;
  final double zone;
  const NeedleGauge({super.key, required this.cents, required this.zone});

  @override
  Widget build(BuildContext context) => SmoothNeedle(cents: cents, zone: zone);
}

/// Sensibilidade e ganho do microfone.
class MicSettingsCard extends StatelessWidget {
  final AppState app;
  const MicSettingsCard({super.key, required this.app});

  @override
  Widget build(BuildContext context) => AppCard(child: MicSettingsContent(app: app));
}

/// Conteúdo dos ajustes de microfone (sem moldura), para usar em seções.
class MicSettingsContent extends StatelessWidget {
  final AppState app;
  const MicSettingsContent({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Captação do microfone', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, children: [
            for (final s in MicSensitivity.values)
              ChoiceChip(
                label: Text(s.label),
                selected: app.sensitivity == s,
                onSelected: (_) => app.setMic(sensitivity: s),
              ),
          ]),
          const SizedBox(height: 4),
          Text(
            switch (app.sensitivity) {
              MicSensitivity.rigorous => 'Só notas limpas e fortes. Mais exato, mas perde sons fracos.',
              MicSensitivity.normal => 'Equilíbrio entre precisão e alcance.',
              MicSensitivity.free =>
                'Pega quase tudo: notas fracas, com ar, vibrato forte e ruído. Pode errar a oitava às vezes.',
            },
            style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.mic, size: 18, color: AppColors.textDim),
            Expanded(
              child: Slider(
                min: 1,
                max: 30,
                value: app.micGain.clamp(1.0, 30.0),
                onChanged: (v) => app.setMic(gain: v),
              ),
            ),
            SizedBox(
                width: 44,
                child: Text('${app.micGain.toStringAsFixed(app.micGain < 10 ? 1 : 0)}×',
                    textAlign: TextAlign.right)),
          ]),
          Text('Ganho: aumente se o instrumento estiver longe ou baixo.',
              style: TextStyle(color: AppColors.textDim, fontSize: 12)),
          const SizedBox(height: 8),
          LevelBar(level: app.level),
        ],
      ),
    );
  }
}

class LevelBar extends StatelessWidget {
  final double level;
  const LevelBar({super.key, required this.level});

  @override
  Widget build(BuildContext context) {
    final v = (level * 6).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        minHeight: 4,
        value: v,
        backgroundColor: AppColors.surface2,
        color: AppColors.textDim,
      ),
    );
  }
}

/// Uma opção de [showOptionSheet] / [PickerField].
class OptionItem<T> {
  final T value;
  final String title;
  final String? subtitle;
  final IconData? icon;
  const OptionItem(this.value, this.title, {this.subtitle, this.icon});
}

/// Campo de seleção que substitui o menu suspenso padrão: mostra a opção atual
/// e, ao tocar, abre uma folha com cartões grandes e fáceis de tocar.
class PickerField<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<OptionItem<T>> options;
  final ValueChanged<T> onChanged;
  final IconData? icon;

  const PickerField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cur = options.firstWhere((o) => o.value == value, orElse: () => options.first);
    return Semantics(
      button: true,
      label: '$label: ${cur.title}. Toque para trocar.',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showOptionSheet<T>(
          context,
          title: label,
          options: options,
          selected: value,
          onPick: onChanged,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.outline),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(cur.icon ?? icon ?? Icons.music_note, color: AppColors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                    Text(cur.title,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Icon(Icons.unfold_more, color: AppColors.textDim),
            ],
          ),
        ),
      ),
    );
  }
}

/// Folha de seleção com cartões. Fecha ao escolher.
Future<void> showOptionSheet<T>(
  BuildContext context, {
  required String title,
  required List<OptionItem<T>> options,
  required T selected,
  required ValueChanged<T> onPick,
  String? hint,
  bool showIcons = true,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.outline, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Text(title,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            if (hint != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(hint, style: TextStyle(color: AppColors.textDim, fontSize: 13)),
              ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
                itemCount: options.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final o = options[i];
                  final sel = o.value == selected;
                  return Material(
                    color: sel ? AppColors.accent.withValues(alpha: 0.16) : AppColors.surface2,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        onPick(o.value);
                        Navigator.pop(ctx);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: sel ? AppColors.accent : AppColors.outline,
                              width: sel ? 2 : 1),
                        ),
                        child: Row(
                          children: [
                            if (showIcons) ...[
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: (sel ? AppColors.accent : AppColors.textDim)
                                      .withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(o.icon ?? Icons.music_note,
                                    color: sel ? AppColors.accent : AppColors.textDim),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(o.title,
                                      style: const TextStyle(
                                          fontSize: 16, fontWeight: FontWeight.w700)),
                                  if (o.subtitle != null)
                                    Text(o.subtitle!,
                                        style: TextStyle(
                                            color: AppColors.textDim, fontSize: 12.5)),
                                ],
                              ),
                            ),
                            if (sel) Icon(Icons.check_circle, color: AppColors.accent),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Opções de instrumento para [PickerField]: nome, cordas e tipo de afinação.
List<OptionItem<String>> instrumentOptions(TuningConfig cfg) {
  final plain = cfg.copyWith(transpose: 0);
  return [
    for (final i in instruments)
      OptionItem<String>(
        i.id,
        i.name,
        subtitle:
            '${i.strings.map((s) => noteName(s.midi, plain)).join(' · ')}  |  ${i.fretted ? 'com trastes, afinação igual' : 'sem trastes, quintas puras'}',
        icon: i.fretted ? Icons.music_note : Icons.graphic_eq,
      ),
  ];
}
