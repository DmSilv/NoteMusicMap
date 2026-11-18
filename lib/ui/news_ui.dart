import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'theme.dart';

/// Uma novidade do boletim num aviso pequeno: título, texto curto e um botão só. Marca como vista ao abrir.
Future<void> showNewsDialog(BuildContext context, AppState app, NewsItem n) {
  app.markNewsSeen(n);
  return showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      icon: Icon(Icons.campaign_outlined, color: AppColors.accent, size: 32),
      title: Text(n.shownTitle, textAlign: TextAlign.center),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(child: Text(n.shownBody, style: TextStyle(height: 1.4, color: AppColors.textDim))),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [FilledButton(onPressed: () => Navigator.pop(c), child: Text(tr('Entendi')))],
    ),
  );
}

/// "Novidades" dentro da central de avisos: as que estão publicadas, a mais nova primeiro. Toque abre a novidade.
class NewsTiles extends StatelessWidget {
  final AppState app;
  const NewsTiles({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final list = app.news;
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.only(bottom: Ds.s4), child: Text(tr('Novidades'), style: Ds.section())),
      for (final n in list)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.campaign_outlined, color: app.isNewsSeen(n) ? AppColors.textDim : AppColors.accent),
          title: Text(n.shownTitle, style: TextStyle(fontWeight: app.isNewsSeen(n) ? FontWeight.w500 : FontWeight.w800, height: 1.25)),
          subtitle: Text(n.shownBody, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
          trailing: app.isNewsSeen(n) ? null : Icon(Icons.circle, size: 9, color: AppColors.accent),
          onTap: () => showNewsDialog(context, app, n),
        ),
      const SizedBox(height: Ds.s12),
    ]);
  }
}
