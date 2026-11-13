import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'design_system.dart';

/// Texto curto do que está valendo na partitura (para o resumo do ajuste).
String staffSummary(AppState app) => app.scaleStaff ? '${staffRhythmLabel(app.scaleRhythm)} · ${staffNamesLabel(app.scaleNames).toLowerCase()}' : tr('Desligada');

String staffRhythmLabel(StaffRhythm r) => switch (r) {
      StaffRhythm.quarter => tr('Semínimas'),
      StaffRhythm.half => tr('Mínimas'),
      StaffRhythm.eighth => tr('Colcheias'),
      StaffRhythm.triplet => tr('Tercinas'),
    };

String staffNamesLabel(StaffNames n) => switch (n) {
      StaffNames.none => tr('Sem nomes'),
      StaffNames.ledger => tr('Só agudas'),
      StaffNames.all => tr('Todas'),
    };

/// Linhas de ajuste da partitura: ligar/desligar, como se escreve o ritmo e quando mostrar o nome das notas.
/// Usadas no modal de configurar a escala e no do exercício.
List<Widget> staffSettingRows(AppState app) => [
      DsSettingRow(
        label: tr('Partitura'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: true, icon: const Icon(Icons.queue_music_rounded, size: 18), label: Text(tr('Ligada'))),
                ButtonSegment(value: false, icon: const Icon(Icons.format_list_bulleted_rounded, size: 18), label: Text(tr('Desligada'))),
              ],
              selected: {app.scaleStaff},
              onSelectionChanged: (v) => app.setStaff(on: v.first),
            ),
          ),
          const DsGap(Ds.s8),
          Text(tr('Só muda como as notas são mostradas; o exercício é o mesmo.'), style: Ds.support()),
        ]),
      ),
      if (app.scaleStaff) ...[
        DsSettingRow(
          label: tr('Como escrever as notas'),
          child: Wrap(spacing: Ds.s8, runSpacing: Ds.s8, children: [
            for (final r in StaffRhythm.values)
              ChoiceChip(
                label: Text(staffRhythmLabel(r)),
                selected: app.scaleRhythm == r,
                onSelected: (_) => app.setStaff(rhythm: r),
              ),
          ]),
        ),
        DsSettingRow(
          label: tr('Nome das notas'),
          child: Wrap(spacing: Ds.s8, runSpacing: Ds.s8, children: [
            for (final n in StaffNames.values)
              ChoiceChip(
                label: Text(staffNamesLabel(n)),
                selected: app.scaleNames == n,
                onSelected: (_) => app.setStaff(names: n),
              ),
          ]),
        ),
        DsSettingRow(
          label: tr('Dica nas notas agudas'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: true, label: Text(tr('Ligada'))),
                  ButtonSegment(value: false, label: Text(tr('Desligada'))),
                ],
                selected: {app.scaleHints},
                onSelectionChanged: (v) => app.setStaff(hints: v.first),
              ),
            ),
            const DsGap(Ds.s8),
            Text(tr('Se você demorar numa nota bem aguda (acima da pauta), o nome dela aparece embaixo.'), style: Ds.support()),
          ]),
        ),
      ],
    ];
