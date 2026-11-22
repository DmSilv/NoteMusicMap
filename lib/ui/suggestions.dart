import 'undo_snack.dart';
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
          title: tr('{0}! Como posso te chamar?', [greetingFor(DateTime.now().hour)]),
          text: tr('Coloque seu apelido para o app falar com você.'),
          action: tr('Informar'),
          onAction: () {
            closeSheet();
            askNickname(context, app);
          },
          onLater: () {
            final before = app.nickHideUntil;
            dismissWithUndo(context,
                message: tr('Tudo bem: perguntamos o apelido depois.'),
                undoLabel: tr('Desfazer'),
                action: () => app.hideNickPrompt(days: 7),
                undo: () => app.restoreNickHide(before));
            closeSheet(); // a folha cobriria o aviso com Desfazer
          },
        ),
      if (installSuggested(app))
        _tile(
          context,
          icon: Icons.install_mobile,
          title: tr('Instale o Notemusic no celular'),
          text: tr('Fica na tela inicial e abre como app.'),
          action: tr('Instalar'),
          onAction: () {
            closeSheet();
            runInstall(context, app);
          },
          onLater: () {
            final before = app.installHideUntil;
            dismissWithUndo(context,
                message: tr('Tudo bem: o convite para instalar volta em alguns dias.'),
                undoLabel: tr('Desfazer'),
                action: () => app.hideInstall(days: 7),
                undo: () => app.restoreInstallHide(before));
            closeSheet(); // a folha cobriria o aviso com Desfazer
          },
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
        color: AppColors.info.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Ds.radiusCard),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: AppColors.info),
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
          TextButton(onPressed: onLater, child: Text(tr('Agora não'))),
        ]),
      ]),
    );
  }
}

/// As dicas numa folha própria (vem da lâmpada da barra de cima, que só existe enquanto há dica). Fecha sozinha quando a
/// última dica some.
Future<void> showTipsSheet(BuildContext context, AppState app) {
  return showDsSheet(
    context,
    title: tr('Dicas'),
    listenable: app,
    children: (c) => [
      if (suggestionCount(app) == 0)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Ds.s24),
          child: Text(tr('Nenhuma dica por agora.'), textAlign: TextAlign.center, style: Ds.support()),
        )
      else
        SuggestionTiles(app: app, closeSheet: () => Navigator.of(c).pop()),
    ],
  );
}

/// A lâmpada da barra de cima: só aparece quando há alguma dica.
class TipsButton extends StatelessWidget {
  final AppState app;
  final Widget Function(Widget child) wrap;
  const TipsButton({super.key, required this.app, required this.wrap});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final n = suggestionCount(app);
          if (n == 0) return const SizedBox.shrink();
          return IconButton(
            tooltip: tr('Dicas'),
            onPressed: () => showTipsSheet(context, app),
            icon: Badge(
              smallSize: 8,
              backgroundColor: AppColors.sharp,
              child: wrap(Icon(Icons.lightbulb_outline_rounded, size: 22, color: AppColors.text)),
            ),
          );
        },
      );
}
