import 'package:flutter/material.dart';

import 'theme.dart';

/// Uma aba da barra de baixo.
class BottomNavItem {
  final IconData icon;
  final String label;

  /// Ponto laranja de aviso (algo novo para ver nessa aba).
  final bool alert;
  const BottomNavItem({required this.icon, required this.label, this.alert = false});
}

/// Barra de baixo: todos os nomes ficam à vista; a aba atual ganha uma linha verde no topo,
/// uma cápsula neutra atrás do ícone e o nome em destaque. O ponto laranja avisa que há novidade.
class BottomNav extends StatelessWidget {
  final List<BottomNavItem> items;
  final int selected;
  final ValueChanged<int> onSelected;
  const BottomNav({super.key, required this.items, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 360;
    return Material(
      color: AppColors.surface,
      child: Container(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.outline, width: 0.8))),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 66,
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(child: _Item(item: items[i], on: i == selected, narrow: narrow, onTap: () => onSelected(i))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  final BottomNavItem item;
  final bool on;
  final bool narrow;
  final VoidCallback onTap;
  const _Item({required this.item, required this.on, required this.narrow, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = on ? AppColors.text : AppColors.textDim;
    return Semantics(
      button: true,
      selected: on,
      label: item.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            // Linha no topo: só na aba atual.
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 3,
              width: on ? 32 : 0,
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(3)),
              ),
            ),
            const SizedBox(height: 7),
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 52,
                  height: 28,
                  decoration: BoxDecoration(
                    color: on ? AppColors.text.withValues(alpha: 0.1) : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(item.icon, size: 22, color: color),
                ),
                if (item.alert)
                  Positioned(
                    top: -1,
                    right: 4,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: AppColors.sharp,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.surface, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  item.label,
                  maxLines: 1,
                  style: TextStyle(fontSize: narrow ? 10 : 11.5, fontWeight: on ? FontWeight.w800 : FontWeight.w600, color: on ? AppColors.text : AppColors.textDim),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
