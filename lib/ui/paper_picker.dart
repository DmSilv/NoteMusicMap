import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import 'staff_view.dart';
import 'theme.dart';

/// A partitura está escura agora? ("Igual ao app" segue o tema.)
bool paperIsDark(StaffPaper p) => switch (p) { StaffPaper.auto => AppColors.dark, StaffPaper.light => false, StaffPaper.dark => true };

/// Escolha da cor da partitura com amostras de verdade: um cartão branco com a clave em preto, um preto com a clave em
/// branco e um dividido ao meio para "igual ao app". Dá para ver o que cada opção faz sem ler nada.
class PaperPicker extends StatelessWidget {
  final StaffPaper value;
  final ValueChanged<StaffPaper> onChanged;
  const PaperPicker({super.key, required this.value, required this.onChanged});

  Widget _clef(Color ink) => Text('', style: TextStyle(fontFamily: 'Leland', fontSize: 38, color: ink, height: 1));

  Widget _preview(StaffPaper p) {
    switch (p) {
      case StaffPaper.light:
        return Container(color: StaffColors.light.paper, alignment: Alignment.center, child: _clef(StaffColors.light.ink));
      case StaffPaper.dark:
        return Container(color: StaffColors.dark.paper, alignment: Alignment.center, child: _clef(StaffColors.dark.ink));
      case StaffPaper.auto:
        return Stack(alignment: Alignment.center, children: [
          Row(children: [Expanded(child: Container(color: StaffColors.light.paper)), Expanded(child: Container(color: StaffColors.dark.paper))]),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF8FA0B1), border: Border.all(color: const Color(0xFF4C5C6C), width: 1.5)),
            child: const Icon(Icons.brightness_6_rounded, size: 22, color: Color(0xFF0F1419)),
          ),
        ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget tile(StaffPaper p, String label) {
      final sel = value == p;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Semantics(
            button: true,
            selected: sel,
            label: label,
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => onChanged(p),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: sel ? AppColors.accent : AppColors.outline, width: sel ? 3 : 1),
                  color: sel ? AppColors.accent.withValues(alpha: 0.12) : null,
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(11)), child: SizedBox(height: 60, width: double.infinity, child: _preview(p))),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: sel ? AppColors.text : AppColors.textDim)),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
    }

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      tile(StaffPaper.light, tr('Clara')),
      tile(StaffPaper.dark, tr('Escura')),
      tile(StaffPaper.auto, tr('Igual ao app')),
    ]);
  }
}

/// Botão sol/lua que fica no cartão da partitura: duas amostras (uma branca com o sol, uma preta com a lua) e a que vale agora
/// ganha a borda de destaque. Um toque troca na hora, sem abrir nada.
class PaperToggle extends StatelessWidget {
  final StaffPaper value;
  final ValueChanged<StaffPaper> onChanged;
  const PaperToggle({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final darkNow = paperIsDark(value);
    Widget swatch(bool dark) {
      final sel = darkNow == dark;
      final colors = dark ? StaffColors.dark : StaffColors.light;
      final label = dark ? tr('Partitura escura') : tr('Partitura clara');
      return Semantics(
        button: true,
        selected: sel,
        label: label,
        excludeSemantics: true,
        child: Tooltip(
          message: label,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onChanged(dark ? StaffPaper.dark : StaffPaper.light),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.paper,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: sel ? AppColors.accent : AppColors.outline, width: sel ? 3 : 1),
                ),
                child: Icon(dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded, size: 22, color: colors.ink),
              ),
            ),
          ),
        ),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [swatch(false), swatch(true)]);
  }
}
