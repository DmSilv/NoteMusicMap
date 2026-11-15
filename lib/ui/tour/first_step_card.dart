import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../design_system.dart';
import '../home_tabs.dart';
import '../theme.dart';
import '../widgets.dart';

/// "Seu primeiro passo": para o músico que chegou sozinho (afinar, tocar uma escala, estudar 5 min).
/// Aparece no Afinador depois da primeira corda afinada, numa linha só (para não empurrar o afinador): mostra o
/// progresso e o PRÓXIMO passo, e um toque leva até ele. Some sozinho quando os três foram feitos; dá para esconder.
class FirstStepCard extends StatelessWidget {
  final AppState app;
  const FirstStepCard({super.key, required this.app});

  void _open(StartItem i) {
    switch (i.id) {
      case 'scale':
        app.goTab?.call(kTabScales);
      case 'study':
        app.goTab?.call(kTabMetronome);
      default:
        break; // afinar: a pessoa já está no Afinador
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = app.firstStepItems;
    final done = startDoneCount(list);
    final next = nextStartItem(list);
    if (next == null) return const SizedBox.shrink();
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          borderRadius: BorderRadius.circular(Ds.radiusCard),
          onTap: () => _open(next),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Ds.tap),
            child: Row(children: [
              Icon(Icons.flag_outlined, color: AppColors.accent, size: 22),
              const SizedBox(width: Ds.s12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(tr('Seu primeiro passo · {0} de {1}', [done, list.length]), style: Ds.support()),
                  Text(next.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ]),
              ),
              if (next.id != 'tune') Icon(Icons.chevron_right, color: AppColors.textDim),
              IconButton(
                tooltip: tr('Esconder'),
                visualDensity: VisualDensity.compact,
                onPressed: app.hideFirstStep,
                icon: Icon(Icons.close, size: 18, color: AppColors.textDim),
              ),
            ]),
          ),
        ),
        const SizedBox(height: Ds.s8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: done / list.length),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            builder: (c, v, _) => LinearProgressIndicator(value: v, minHeight: 4, backgroundColor: AppColors.outline, color: AppColors.accent),
          ),
        ),
      ]),
    );
  }
}
