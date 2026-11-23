import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import 'design_system.dart';
import 'theme.dart';

/// Barra lateral do computador: as cinco telas em atalhos, no lugar da barra de baixo.
/// Mostra só os ícones numa janela média e os nomes numa janela larga.
class DesktopRail extends StatelessWidget {
  final List<IconData> icons;
  final List<String> titles;
  final int selected;

  /// A ferramenta do outro painel: aparece com fundo, mas sem a borda do painel em foco.
  final int? also;
  final ValueChanged<int> onSelected;
  final bool labels;
  final bool alertOnLast;

  /// O último item (Meu espaço) não é uma ferramenta: abre e fecha a coluna da direita. Aqui, se ela está aberta.
  final bool homeOn;

  /// Duas ferramentas abertas ao mesmo tempo (ou uma só) e o que fazer ao trocar.
  final bool two;
  final ValueChanged<bool> onTwo;

  /// Em duas telas: de qual tela (1 ou 2) é cada ferramenta aberta.
  final Map<int, String> tags;
  const DesktopRail({
    super.key,
    required this.icons,
    required this.titles,
    required this.selected,
    this.also,
    required this.onSelected,
    required this.labels,
    required this.homeOn,
    required this.two,
    required this.onTwo,
    this.tags = const {},
    this.alertOnLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: labels ? 208 : 72,
      decoration: BoxDecoration(
        color: Color.lerp(AppColors.bg, Colors.black, AppColors.dark ? 0.25 : 0.03),
        border: Border(right: BorderSide(color: AppColors.outline)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ScreensToggle(two: two, onChanged: onTwo, labels: labels),
          const SizedBox(height: 10),
          Divider(height: 1, color: AppColors.outline),
          const SizedBox(height: 10),
          for (var i = 0; i < icons.length; i++) ...[
            // O último item (Meu espaço) fica separado das ferramentas: ele abre a coluna da direita, não uma ferramenta.
            if (i == icons.length - 1) ...[
              const SizedBox(height: 6),
              Divider(height: 1, color: AppColors.outline),
              const SizedBox(height: 10),
            ],
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _RailItem(
                icon: icons[i],
                label: titles[i],
                showLabel: labels,
                on: i == icons.length - 1 ? homeOn : i == selected,
                divider: i == icons.length - 1,
                shown: i == also,
                tag: tags[i],
                alert: alertOnLast && i == icons.length - 1,
                onTap: () => onSelected(i),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A "telinha" que representa uma tela do app: um retângulo com o número dentro (1 ou 2). Duas delas lado a lado = duas telas.
class DeskMiniScreen extends StatelessWidget {
  final List<String> parts;
  final Color color;
  final double height;
  const DeskMiniScreen({super.key, required this.parts, required this.color, this.height = 20});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < parts.length; i++)
          Container(
            width: height * 0.85,
            height: height,
            margin: EdgeInsets.only(right: i == parts.length - 1 ? 0 : 3),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color, width: 1.6),
            ),
            child: Text(parts[i], style: TextStyle(fontSize: height * 0.5, fontWeight: FontWeight.w800, color: color, height: 1)),
          ),
      ]);
}

/// "Telas": escolhe entre uma ferramenta ou duas lado a lado. Sempre à vista no alto da barra lateral, com a telinha
/// de cada opção desenhada (uma ou duas), para mostrar o que muda. Selecionada: borda branca, fundo claro e telinha verde.
class _ScreensToggle extends StatelessWidget {
  final bool two, labels;
  final ValueChanged<bool> onChanged;
  const _ScreensToggle({required this.two, required this.onChanged, required this.labels});

  Widget _opt(IconData? _, String text, List<String> parts, bool value) {
    final on = two == value;
    final color = on ? AppColors.accent : AppColors.textDim;
    return Semantics(
      button: true,
      selected: on,
      label: text,
      child: Tooltip(
        message: text,
        child: Material(
          color: on ? AppColors.surface2 : AppColors.surface,
          borderRadius: BorderRadius.circular(Ds.radiusControl),
          child: InkWell(
            borderRadius: BorderRadius.circular(Ds.radiusControl),
            onTap: () => onChanged(value),
            child: Container(
              height: labels ? 48 : 52,
              padding: EdgeInsets.symmetric(horizontal: labels ? 12 : 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Ds.radiusControl),
                border: Border.all(color: on ? AppColors.text : AppColors.outline, width: on ? 1.6 : 1),
              ),
              child: Row(mainAxisAlignment: labels ? MainAxisAlignment.start : MainAxisAlignment.center, children: [
                DeskMiniScreen(parts: parts, color: color, height: labels ? 22 : 18),
                if (labels) ...[
                  const SizedBox(width: 12),
                  Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: on ? AppColors.text : AppColors.textDim))),
                  if (on) Icon(Icons.check_rounded, size: 18, color: AppColors.accent),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (labels) Padding(padding: const EdgeInsets.only(left: 4, bottom: 6), child: Text(tr('Telas'), style: Ds.section())),
      _opt(null, tr('Uma tela'), const ['1'], false),
      const SizedBox(height: 6),
      _opt(null, tr('Duas telas'), const ['1', '2'], true),
    ]);
  }
}

class _RailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool showLabel, on, shown, alert, divider;
  final String? tag;
  final VoidCallback onTap;
  const _RailItem({required this.icon, required this.label, required this.showLabel, required this.on, this.shown = false, this.tag, this.divider = false, required this.alert, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: on,
      label: label,
      child: Tooltip(
        message: showLabel ? '' : label,
        child: Material(
          color: (on || shown) ? AppColors.surface2 : Colors.transparent,
          borderRadius: BorderRadius.circular(Ds.radiusControl),
          child: InkWell(
            borderRadius: BorderRadius.circular(Ds.radiusControl),
            onTap: onTap,
            child: Container(
              height: 48,
              padding: EdgeInsets.symmetric(horizontal: showLabel ? 12 : 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Ds.radiusControl),
                border: Border.all(color: on ? AppColors.text : Colors.transparent),
              ),
              child: Row(
                mainAxisAlignment: showLabel ? MainAxisAlignment.start : MainAxisAlignment.center,
                children: [
                  Badge(
                    smallSize: 8,
                    label: tag == null ? null : Text(tag!, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.onAccent)),
                    isLabelVisible: alert || (tag != null && !showLabel),
                    backgroundColor: tag != null ? AppColors.accent : AppColors.sharp,
                    child: Icon(icon, size: 22, color: (on || shown) ? AppColors.text : AppColors.textDim),
                  ),
                  if (showLabel) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: (on || shown) ? AppColors.text : AppColors.textDim),
                      ),
                    ),
                    if (tag != null) DeskMiniScreen(parts: [tag!], color: AppColors.accent, height: 20),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
