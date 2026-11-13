import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'scale_exercise_page.dart' show directionPicker;
import 'staff_settings.dart';
import 'theme.dart';
import 'tuning_pick.dart';

/// Os ajustes da escala num lugar só, sem modal dentro de modal: tudo aparece na própria folha, em seções, e é a MESMA folha na aba
/// Escalas e na tela do exercício (a pessoa não precisa lembrar onde está cada coisa). Só a Afinação abre uma folha própria, porque
/// é uma escolha longa.
void showScaleSettings(BuildContext context, AppState app, {required bool exercise, VoidCallback? onReport}) {
  showDsSheet(
    context,
    title: exercise ? tr('Ajustes do exercício') : tr('Configurar escala'),
    listenable: exercise ? Listenable.merge([app, app.live]) : app,
    children: (c) => scaleSettingsRows(c, app, exercise: exercise, onReport: onReport),
  );
}

Widget _section(String t) => Padding(
      padding: const EdgeInsets.only(top: Ds.s4, bottom: Ds.s12),
      child: Row(children: [
        Text(t.toUpperCase(), style: TextStyle(color: AppColors.accent, fontSize: 13, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
        const SizedBox(width: Ds.s12),
        Expanded(child: Divider(height: 1, color: AppColors.outline)),
      ]),
    );

/// "Lá♭" -> "Lá bemol": por extenso, que cabe certo no botão e é como se fala (os símbolos ♯ ♭ dependem de uma fonte de reserva).
String _spoken(String n) => n.replaceAll('♭', ' bemol').replaceAll('♯', ' sustenido');

/// Opções de tônica: onde a tonalidade existe nas duas grafias (Fá♯ e Sol♭ maiores, por exemplo) cada uma é uma opção (valor = classe + 100
/// para a outra grafia); nas demais, a tecla com os dois nomes.
List<(int, String)> tonicChoices(AppState app) {
  final minor = app.scaleType.isMinor;
  final base = app.cfg.copyWith(transpose: 0, keyFlats: null);
  final out = <(int, String)>[];
  for (var pc = 0; pc < 12; pc++) {
    final midi = 60 + pc;
    if (!app.scaleType.arpeggio && app.scaleType != ScaleType.chromatic && ScaleSpeller.hasAlt(midi, minor: minor)) {
      final (l1, a1) = ScaleSpeller(midi, app.scaleType).tonicSpelling;
      final (l2, a2) = ScaleSpeller(midi, app.scaleType, alt: true).tonicSpelling;
      out.add((pc, _spoken(SpelledNote(l1, a1, 4).name())));
      out.add((pc + 100, _spoken(SpelledNote(l2, a2, 4).name())));
    } else {
      final a = noteName(midi, base);
      final other = a.contains('♯') ? noteNamesFlat[pc] : (a.contains('♭') ? noteNamesSharp[pc] : a);
      out.add((pc, a == other ? _spoken(a) : '${_spoken(a)} · ${_spoken(other)}'));
    }
  }
  return out;
}

List<Widget> scaleSettingsRows(BuildContext context, AppState app, {required bool exercise, VoidCallback? onReport}) {
  final e = app.exercise;
  final tonicNow = app.scaleTonicMidi % 12 + (app.scaleAltActive ? 100 : 0);
  return [
    if (!exercise) ...[
      _section(tr('Escala')),
      DsSettingRow(
        label: tr('Tônica (nota inicial)'),
        child: Wrap(spacing: Ds.s8, runSpacing: Ds.s8, children: [
          for (final (v, l) in tonicChoices(app))
            ChoiceChip(
              label: Text(l),
              selected: v == tonicNow,
              onSelected: (_) {
                app.setScale(tonicPc: v % 100, alt: v >= 100);
                // Justa/pitagórica dependem da tônica: acompanha.
                if (app.system != TuningSystem.equal) app.setTuning(tonicPc: v % 100);
              },
            ),
        ]),
      ),
      DsSettingRow(
        label: app.scaleType.arpeggio ? tr('Tipo de arpejo') : tr('Tipo de escala'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: Ds.s8, runSpacing: Ds.s8, children: [
            for (final t in app.scaleType.arpeggio ? ScaleType.arpeggios : ScaleType.scales)
              ChoiceChip(label: Text(t.label), selected: t == app.scaleType, onSelected: (_) => app.setScale(type: t)),
          ]),
          if (app.scaleType.hint.isNotEmpty) ...[
            const DsGap(Ds.s8),
            Text(app.scaleType.hint, style: Ds.support()),
          ],
          if (app.scaleType == ScaleType.melodicMinor) ...[
            const DsGap(Ds.s8),
            Text(tr('A menor melódica é a menor do sistema de Flesch: sobe com 6ª e 7ª elevadas (Lá e Si naturais em Dó menor) e desce como menor natural (Si♭ e Lá♭). Os nomes das notas já mudam na subida e na descida.'), style: Ds.support()),
          ],
        ]),
      ),
      DsSettingRow(
        label: tr('Oitavas'),
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [for (var o = 1; o <= 4; o++) ButtonSegment(value: o, label: Text('$o'))],
            selected: {app.scaleOctaves},
            onSelectionChanged: (v) => app.setScale(octaves: v.first),
          ),
        ),
      ),
    ],
    DsSettingRow(
      label: tr('Direção'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: double.infinity, child: directionPicker(app, onChanged: exercise ? () => app.startExercise(demoMode: app.demo) : null)),
        if (exercise) ...[
          const DsGap(Ds.s8),
          Text(tr('Muda a ordem das notas e recomeça o exercício.'), style: Ds.support()),
        ],
      ]),
    ),
    _section(tr('Como tocar')),
    DsSettingRow(
      label: tr('Jeito de tocar'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: true, icon: const Icon(Icons.shuffle_rounded, size: 18), label: Text(tr('Livre'))),
              ButtonSegment(value: false, icon: const Icon(Icons.format_list_numbered_rounded, size: 18), label: Text(tr('Guiado'))),
            ],
            selected: {e?.flow ?? app.exerciseFlow},
            onSelectionChanged: (v) => app.setExerciseFlow(v.first),
          ),
        ),
        const DsGap(Ds.s8),
        Text((e?.flow ?? app.exerciseFlow) ? tr('Toque as notas na ordem que quiser.') : tr('Uma nota de cada vez, na ordem.'), style: Ds.support()),
      ]),
    ),
    if (!exercise)
      DsSettingRow(
        label: tr('Marcar a escala na grade'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(app.scaleMode ? tr('Ligado') : tr('Desligado'), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(tr('Destaca as notas na aba Grade.'), style: Ds.support()),
            value: app.scaleMode,
            onChanged: (v) => app.setScale(enabled: v),
          ),
          if (app.scaleMode && onReport != null)
            OutlinedButton.icon(onPressed: onReport, icon: const Icon(Icons.assessment_outlined), label: Text(tr('Ver relatório do que toquei'))),
        ]),
      ),
    _section(tr('Partitura')),
    ...staffSettingRows(app),
    _section(tr('Afinação')),
    DsSettingRow(
      label: tr('Afinação'),
      child: OutlinedButton.icon(
        onPressed: () => pickTuningSystem(context, app, tonicPc: app.scaleTonicMidi % 12),
        icon: const Icon(Icons.straighten, size: 20),
        label: Text(tuningSummary(app)),
      ),
    ),
  ];
}
