import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'hello_bar.dart';
import 'install_banner.dart';
import 'theme.dart';

/// Sugestões do app (não são avisos de aula): ficam no sino, não presas no topo da tela.
/// Hoje: informar o apelido e instalar no celular.
bool nicknameSuggested(AppState app) {
  final n = app.profile.name;
  return (n == null || n.trim().isEmpty) && DateTime.now().millisecondsSinceEpoch >= app.nickHideUntil;
}

bool installSuggested(AppState app) =>
    installAvailable(app) && DateTime.now().millisecondsSinceEpoch >= app.installHideUntil;

/// Quantas sugestões estão pendentes (entra na bolinha do sino).
int suggestionCount(AppState app) => (nicknameSuggested(app) ? 1 : 0) + (installSuggested(app) ? 1 : 0);

/// Cartões de sugestão no alto do painel de avisos.
class SuggestionTiles extends StatelessWidget {
  final AppState app;
  final VoidCallback closeSheet;
  const SuggestionTiles({super.key, required this.app, required this.closeSheet});

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      if (nicknameSuggested(app))
        _tile(
          context,
          icon: Icons.waving_hand_outlined,
          title: '${greetingFor(DateTime.now().hour)}! Como posso te chamar?',
          text: 'Coloque seu apelido para o app falar com você.',
          action: 'Informar',
          onAction: () {
            closeSheet();
            askNickname(context, app);
          },
          onLater: () => app.hideNickPrompt(days: 7),
        ),
      if (installSuggested(app))
        _tile(
          context,
          icon: Icons.install_mobile,
          title: 'Instale o Notemusic no celular',
          text: 'Fica na tela inicial e abre como app.',
          action: 'Instalar',
          onAction: () {
            closeSheet();
            runInstall(context, app);
          },
          onLater: () => app.hideInstall(days: 7),
        ),
    ];
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final t in tiles) ...[t, const DsGap(Ds.s12)],
    ]);
  }

  Widget _tile(BuildContext context,
      {required IconData icon,
      required String title,
      required String text,
      required String action,
      required VoidCallback onAction,
      required VoidCallback onLater}) {
    return Container(
      padding: const EdgeInsets.all(Ds.s16),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Ds.radiusCard),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: AppColors.accent),
          const SizedBox(width: Ds.s12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: Ds.fontBody)),
              const SizedBox(height: Ds.s4),
              Text(text, style: Ds.support()),
            ]),
          ),
        ]),
        const SizedBox(height: Ds.s12),
        Row(children: [
          Expanded(child: FilledButton(onPressed: onAction, child: Text(action))),
          const SizedBox(width: Ds.s8),
          TextButton(onPressed: onLater, child: const Text('Agora não')),
        ]),
      ]),
    );
  }
}
