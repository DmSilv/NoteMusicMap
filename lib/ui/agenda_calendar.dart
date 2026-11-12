import 'package:flutter/material.dart';

import 'design_system.dart';
import 'theme.dart';
import 'package:afina_core/afina_core.dart';

final _heads = [tr('seg'), tr('ter'), tr('qua'), tr('qui'), tr('sex'), tr('sáb'), tr('dom')];
final _monthNames = [
  tr('janeiro'), tr('fevereiro'), tr('março'), tr('abril'), tr('maio'), tr('junho'), tr('julho'), tr('agosto'), tr('setembro'), tr('outubro'), tr('novembro'), tr('dezembro')
];

/// Calendário do mês para as agendas (professor e aluno): a semana começa na segunda, cada dia com aula leva
/// pontinhos (um por aula, até 3), o dia de hoje tem um anel e o dia escolhido fica preenchido.
class AgendaMonthGrid extends StatelessWidget {
  /// Qualquer dia do mês mostrado.
  final DateTime month;

  /// Quantas aulas há em cada dia (índice 1..31).
  final Map<int, int> counts;
  final DateTime picked;
  final DateTime today;
  final ValueChanged<DateTime> onPick;
  const AgendaMonthGrid({super.key, required this.month, required this.counts, required this.picked, required this.today, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final lead = first.weekday - 1;
    return Column(children: [
      Row(children: [
        for (final h in _heads)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: Ds.s8),
              child: Center(child: Text(h, style: TextStyle(color: AppColors.textDim, fontSize: 12, fontWeight: FontWeight.w700))),
            ),
          ),
      ]),
      GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        // Altura fixa da célula: em tela larga (tablet, navegador) o calendário não fica gigante.
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, mainAxisExtent: 58, mainAxisSpacing: 4, crossAxisSpacing: 4),
        children: [
          for (var i = 0; i < lead; i++) const SizedBox.shrink(),
          for (var d = 1; d <= days; d++) _cell(DateTime(first.year, first.month, d), counts[d] ?? 0),
        ],
      ),
    ]);
  }

  Widget _cell(DateTime d, int n) {
    final sel = d == picked;
    final isToday = d == today;
    final dots = n.clamp(0, 3);
    return Semantics(
      button: true,
      selected: sel,
      excludeSemantics: true, // o rótulo já diz tudo: sem ler o número do dia duas vezes
      onTap: () => onPick(d),
      label: tr('{0} de {1}, {2}', [d.day, _monthNames[d.month - 1], n == 0 ? tr('sem aulas') : (n == 1 ? tr('1 aula') : tr('{0} aulas', [n]))]),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onPick(d),
        child: Container(
          decoration: BoxDecoration(
            color: sel ? AppColors.accent : (n > 0 ? AppColors.accent.withValues(alpha: 0.10) : Colors.transparent),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isToday && !sel ? AppColors.accent : Colors.transparent, width: 1.6),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(
              '${d.day}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: sel || isToday || n > 0 ? FontWeight.w800 : FontWeight.w500,
                color: sel ? AppColors.onAccent : (isToday ? AppColors.accent : AppColors.text),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 6,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < dots; i++)
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(color: sel ? AppColors.onAccent : AppColors.accent, shape: BoxShape.circle),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
