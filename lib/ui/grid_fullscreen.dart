import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app_state.dart';
import 'grid_board.dart';
import 'grid_widgets.dart';
import 'note_widgets.dart';
import 'smooth_color.dart';
import 'theme.dart';

/// Grade em tela cheia para usar durante o estudo: notas nas colunas (Dó a Si)
/// e oitavas nas linhas (agudos no topo), em pé ou deitado. Embaixo: legenda de cores e navegação de oitavas.
class GridFullscreen extends StatefulWidget {
  final AppState app;
  const GridFullscreen({super.key, required this.app});

  @override
  State<GridFullscreen> createState() => _GridFullscreenState();
}

class _GridFullscreenState extends State<GridFullscreen> {
  bool _lockLandscape = false;
  bool _showControls = true;

  AppState get app => widget.app;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable().catchError((_) {});
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const []);
    if (!app.listening && !app.metroRunning) {
      WakelockPlus.disable().catchError((_) {});
    }
    super.dispose();
  }

  void _toggleRotate() {
    setState(() => _lockLandscape = !_lockLandscape);
    SystemChrome.setPreferredOrientations(_lockLandscape
        ? const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        : const []);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: app.live,
          builder: (context, _) {
            final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
            final zone = app.zoneCents;
            return Column(
              children: [
                if (_showControls) _topBar(landscape),
                if (_showControls)
                  // Altura fixa: a dica troca de texto sem empurrar a grade.
                  SizedBox(
                    height: 30,
                    child: Center(
                        child: CorrectionHint(
                            cents: app.shown?.cents, zone: zone, target: app.shown?.target)),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 2, 6, 4),
                    child: Stack(children: [
                      // Troca suave ao mudar de oitava ou de orientação.
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween(begin: const Offset(0, 0.03), end: Offset.zero)
                                .animate(anim),
                            child: child,
                          ),
                        ),
                        child: KeyedSubtree(
                          key: ValueKey('${app.gridOctaves}-$landscape'),
                          child: GridBoard(app: app),
                        ),
                      ),
                      if (!_showControls) _revealButton(),
                    ]),
                  ),
                ),
                if (_showControls)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SessionChips(app: app),
                        const SizedBox(height: 8),
                        IntonationLegend(zone: zone, compact: true),
                        const SizedBox(height: 10),
                        OctaveNav(app: app, compact: true, onMore: () => showOctaveSheet(context, app)),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _topBar(bool landscape) {
    final cur = app.shown;
    final zone = app.zoneCents;
    final col = cur == null ? AppColors.textDim : intonationColor(cur.cents, zone);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Fechar',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 0),
          // Área fixa: o tamanho da nota nunca muda, então nada "pula" na tela.
          SizedBox(
            width: 88,
            height: 52,
            child: Align(
              alignment: Alignment.centerLeft,
              child: NoteReadout(note: cur, cfg: app.cfg, zone: zone, size: 38),
            ),
          ),
          // Desvio em Hz e frequência, sempre no mesmo lugar.
          SizedBox(
            width: 84,
            height: 52,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // A cor escorre quadro a quadro (sem reiniciar a cada leitura).
                SmoothColor(
                  target: col,
                  builder: (context, c) => Text(
                    cur == null ? '' : fmtHz(hzOff(cur.cents, cur.target)),
                    style: TextStyle(
                        color: c,
                        fontSize: 19,
                        height: 1.0,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  cur == null ? '' : '${cur.freq.toStringAsFixed(1).replaceAll('.', ',')} Hz',
                  style: TextStyle(color: AppColors.textDim, fontSize: 12, height: 1.0),
                ),
              ],
            ),
          ),
          const Expanded(child: SizedBox.shrink()),
          // Zerar a sessão: em destaque, ao lado do microfone.
          IconButton.filled(
            tooltip: 'Zerar a sessão',
            style: IconButton.styleFrom(
              minimumSize: const Size(44, 44),
              backgroundColor: AppColors.sharp.withValues(alpha: 0.22),
              foregroundColor: AppColors.sharp,
              side: BorderSide(color: AppColors.sharp.withValues(alpha: 0.7), width: 1.5),
            ),
            icon: const Icon(Icons.restart_alt),
            onPressed: () => confirmResetGrid(context, app),
          ),
          const SizedBox(width: 6),
          // Ação principal, bem visível e com área de toque grande.
          IconButton.filled(
            tooltip: app.listening ? 'Parar de ouvir' : 'Ouvir',
            style: IconButton.styleFrom(
              minimumSize: const Size(48, 48),
              backgroundColor: app.listening ? AppColors.surface2 : AppColors.accent,
              foregroundColor: app.listening ? AppColors.text : AppColors.onAccent,
            ),
            icon: Icon(app.listening ? Icons.mic_off : Icons.mic),
            onPressed: () => app.listening ? app.stopListening() : app.startListening(),
          ),
          const SizedBox(width: 6),
          // Ações secundárias ficam num menu, para a barra respirar.
          PopupMenuButton<String>(
            tooltip: 'Mais opções',
            icon: const Icon(Icons.more_vert),
            color: AppColors.surface,
            onSelected: (v) {
              switch (v) {
                case 'rotate':
                  _toggleRotate();
                case 'hide':
                  setState(() => _showControls = false);
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'rotate',
                child: ListTile(
                  dense: true,
                  leading: Icon(_lockLandscape
                      ? Icons.screen_lock_landscape
                      : Icons.screen_rotation),
                  title: Text(_lockLandscape ? 'Liberar rotação' : 'Forçar horizontal'),
                ),
              ),
              const PopupMenuItem(
                value: 'hide',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.fullscreen),
                  title: Text('Esconder controles'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _revealButton() => Positioned(
        right: 4,
        top: 4,
        child: IconButton.filledTonal(
          tooltip: 'Mostrar controles',
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => setState(() => _showControls = true),
        ),
      );
}
