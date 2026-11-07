import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../platform/web_install.dart';
import '../platform/web_vibrate.dart' show webIsIos;
import 'theme.dart';

/// Dá para oferecer a instalação? Só no navegador (não no app já instalado), em
/// celular/tablet, ou no computador quando o navegador libera a janela de instalação.
bool installAvailable(AppState app) =>
    kIsWeb && !webIsStandalone() && !app.installDone && (webIsMobileBrowser() || webCanPromptInstall());

/// Faz a instalação: no Chrome/Edge abre a janela de instalação do próprio navegador
/// (um toque); onde não existe (iPhone, Firefox…) mostra o passo a passo.
Future<void> runInstall(BuildContext context, AppState app) async {
  if (webCanPromptInstall()) {
    final ok = await webPromptInstall();
    if (ok) {
      app.markInstalled();
      app.say('Instalado! Procure o ícone do Notemusic na tela inicial.');
    } else {
      app.hideInstall(days: 3);
    }
    return;
  }
  final ios = webIsIos();
  final android = webIsAndroidBrowser();
  final steps = ios
      ? const [
          (Icons.ios_share, 'Toque em Compartilhar', 'O ícone do quadrado com uma seta para cima, na barra do Safari (no iPhone fica embaixo).'),
          (Icons.add_box_outlined, 'Toque em "Adicionar à Tela de Início"', 'Role a lista de opções até achar.'),
          (Icons.check_circle_outline, 'Toque em "Adicionar"', 'O ícone do Notemusic aparece na tela inicial.'),
        ]
      : android
          ? const [
              (Icons.more_vert, 'Abra o menu do navegador', 'Os três pontinhos no canto de cima. Funciona melhor no Chrome.'),
              (Icons.install_mobile, 'Toque em "Instalar app"', 'Em alguns navegadores o nome é "Adicionar à tela inicial".'),
              (Icons.check_circle_outline, 'Confirme', 'O ícone do Notemusic aparece na tela inicial.'),
            ]
          : const [
              (Icons.install_desktop, 'Procure o ícone de instalar', 'Na barra de endereço do Chrome ou do Edge, à direita.'),
              (Icons.more_vert, 'Ou use o menu do navegador', 'Três pontinhos › "Instalar Notemusic" (ou "Salvar e compartilhar › Instalar").'),
            ];
  if (!context.mounted) return;
  final installed = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.install_mobile),
      title: const Text('Instalar o Notemusic'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Fica na tela inicial como um app, abre em tela cheia e funciona sem internet.',
                style: TextStyle(color: AppColors.textDim, fontSize: 13)),
            const SizedBox(height: 12),
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: AppColors.accent.withValues(alpha: 0.2),
                    child: Text('${i + 1}', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(steps[i].$1, size: 18),
                        const SizedBox(width: 6),
                        Expanded(child: Text(steps[i].$2, style: const TextStyle(fontWeight: FontWeight.w700))),
                      ]),
                      const SizedBox(height: 2),
                      Text(steps[i].$3, style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
                    ]),
                  ),
                ]),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Fechar')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Já instalei')),
      ],
    ),
  );
  if (installed == true) app.markInstalled();
}

/// Aviso fixo no alto da tela inicial: "Instale o Notemusic no celular".
class InstallBanner extends StatefulWidget {
  final AppState app;
  const InstallBanner({super.key, required this.app});

  @override
  State<InstallBanner> createState() => _InstallBannerState();
}

class _InstallBannerState extends State<InstallBanner> {
  @override
  void initState() {
    super.initState();
    // O navegador libera a instalação um pouco depois de abrir a página.
    webOnInstallEvents(() {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        if (!installAvailable(app) || DateTime.now().millisecondsSinceEpoch < app.installHideUntil) {
          return const SizedBox.shrink();
        }
        final oneTap = webCanPromptInstall();
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
          child: Material(
            color: AppColors.accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => runInstall(context, app),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.6)),
                ),
                child: Row(children: [
                  Icon(Icons.install_mobile, color: AppColors.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      const Text('Instale o Notemusic no celular',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                      Text(
                          oneTap
                              ? 'Um toque: fica na tela inicial e abre como app.'
                              : 'Veja como colocar na tela inicial (30 segundos).',
                          style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                    ]),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 14)),
                    onPressed: () => runInstall(context, app),
                    child: const Text('Instalar'),
                  ),
                  IconButton(
                    tooltip: 'Agora não',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => app.hideInstall(days: 7),
                  ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}
