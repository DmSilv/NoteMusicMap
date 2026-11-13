import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'design_system.dart';

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

/// Uma ajuda de leitura: título curto, uma frase e uma chave. Toda opção de ligar/desligar da partitura é assim (um jeito só de mexer).
Widget _helpSwitch(String title, String sub, bool value, ValueChanged<bool> onChanged) => SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: Ds.fontBody)),
      subtitle: Text(sub, style: Ds.support()),
      value: value,
      onChanged: onChanged,
    );

/// Ajustes da partitura, na ordem em que se pensa neles: mostrar ou não; como escrever (ritmo e nomes); e as ajudas de leitura, cada uma
/// com sua chave. A COR fica na própria tela (a linha "Cor da partitura" logo acima da partitura), não aqui, para não ter dois lugares.
/// Usado na folha de configurar a escala e na do exercício.
List<Widget> staffSettingRows(AppState app) => [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(tr('Mostrar a partitura'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: Ds.fontBody)),
        subtitle: Text(tr('Só muda como as notas aparecem; o exercício é o mesmo.'), style: Ds.support()),
        value: app.scaleStaff,
        onChanged: (v) => app.setStaff(on: v),
      ),
      if (app.scaleStaff) ...[
        const DsGap(Ds.s12),
        DsSettingRow(
          label: tr('Ritmo da escrita'),
          child: Wrap(spacing: Ds.s8, runSpacing: Ds.s8, children: [
            for (final r in StaffRhythm.values)
              ChoiceChip(label: Text(staffRhythmLabel(r)), selected: app.scaleRhythm == r, onSelected: (_) => app.setStaff(rhythm: r)),
          ]),
        ),
        DsSettingRow(
          label: tr('Nome das notas'),
          child: Wrap(spacing: Ds.s8, runSpacing: Ds.s8, children: [
            for (final n in StaffNames.values)
              ChoiceChip(label: Text(staffNamesLabel(n)), selected: app.scaleNames == n, onSelected: (_) => app.setStaff(names: n)),
          ]),
        ),
        DsSettingRow(
          label: tr('Ajudas de leitura'),
          child: Column(children: [
            _helpSwitch(tr('Dica ao demorar numa nota aguda'), tr('Mostra o nome da nota se você demorar.'), app.scaleHints, (v) => app.setStaff(hints: v)),
            _helpSwitch(tr('8va nas notas muito agudas'), tr('Escreve uma oitava abaixo, com o sinal 8va e o nome.'), app.scaleOttava, (v) => app.setStaff(ottava: v)),
            if (app.hasFingeringHere)
              _helpSwitch(tr('Dedilhado do Flesch'), tr('Números dos dedos, só nas escalas já conferidas.'), app.scaleFingers, (v) => app.setStaff(fingers: v)),
          ]),
        ),
      ],
    ];
