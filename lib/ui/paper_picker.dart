import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

/// A partitura está escura agora? ("Igual ao app" segue o tema.)
bool paperIsDark(StaffPaper p) => switch (p) { StaffPaper.auto => AppColors.dark, StaffPaper.light => false, StaffPaper.dark => true };

/// Linha de controle da cor da partitura: o nome à esquerda e, à direita, o seletor padrão do app (o mesmo dos outros ajustes) com
/// duas opções com ícone E nome: sol "Clara" e lua "Escura". Ícone sozinho é ambíguo (mostra o estado ou o destino?); com o nome e a
/// opção marcada, não. Fica FORA do cartão da partitura, na cor do app, para ler bem em qualquer papel.
class PaperToggleRow extends StatelessWidget {
  final StaffPaper value;
  final ValueChanged<StaffPaper> onChanged;
  const PaperToggleRow({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final darkNow = paperIsDark(value);
    return Row(children: [
      Expanded(child: Text(tr('Cor da partitura'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textDim))),
      SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(value: false, icon: const Icon(Icons.light_mode_rounded, size: 18), label: Text(tr('Clara')), tooltip: tr('Partitura clara')),
          ButtonSegment(value: true, icon: const Icon(Icons.dark_mode_rounded, size: 18), label: Text(tr('Escura')), tooltip: tr('Partitura escura')),
        ],
        selected: {darkNow},
        onSelectionChanged: (v) => onChanged(v.first ? StaffPaper.dark : StaffPaper.light),
      ),
    ]);
  }
}
