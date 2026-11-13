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

/// Botão sol/lua do cartão da partitura: um trilho dividido ao meio (metade branca com o sol, metade preta com a lua) e um anel verde que
/// desliza para a cor que vale agora. Cada metade é um botão de 50 × 48; um toque troca na hora, sem abrir nada.
class PaperToggle extends StatelessWidget {
  final StaffPaper value;
  final ValueChanged<StaffPaper> onChanged;
  const PaperToggle({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final darkNow = paperIsDark(value);
    Widget half(bool dark) {
      final label = dark ? tr('Partitura escura') : tr('Partitura clara');
      final colors = dark ? StaffColors.dark : StaffColors.light;
      return Expanded(
        child: Semantics(
          button: true,
          selected: darkNow == dark,
          label: label,
          excludeSemantics: true,
          child: Tooltip(
            message: label,
            child: InkWell(
              borderRadius: BorderRadius.horizontal(left: Radius.circular(dark ? 0 : 22), right: Radius.circular(dark ? 22 : 0)),
              onTap: () => onChanged(dark ? StaffPaper.dark : StaffPaper.light),
              child: Container(
                alignment: Alignment.center,
                child: Icon(dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded, size: 22, color: colors.ink),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: 108,
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Stack(children: [
          // trilho: metade branca, metade preta
          Positioned.fill(
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: AppColors.textDim, width: 1.5)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(21),
                child: Row(children: [Expanded(child: Container(color: StaffColors.light.paper)), Expanded(child: Container(color: StaffColors.dark.paper))]),
              ),
            ),
          ),
          // anel que desliza para a cor que vale
          AnimatedAlign(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: darkNow ? Alignment.centerRight : Alignment.centerLeft,
            child: IgnorePointer(
              child: Container(
                width: 52,
                height: 46,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: AppColors.accent, width: 3)),
              ),
            ),
          ),
          Positioned.fill(child: Row(children: [half(false), half(true)])),
        ]),
      ),
    );
  }
}
