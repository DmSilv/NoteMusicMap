import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app_state.dart';
import 'grid_cell.dart';
import 'grid_widgets.dart';
import 'needle.dart';
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
            final zone = app.zone.cents;
            return Column(
              children: [
                if (_showControls) _topBar(landscape),
                if (_showControls)
                  // Altura fixa: a dica troca de texto sem empurrar a grade.
                  SizedBox(
                    height: 30,
                    child: Center(child: CorrectionHint(cents: app.shown?.cents, zone: zone)),
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
                          child: _grid(landscape),
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
    final zone = app.zone.cents;
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
          const SizedBox(width: 4),
          // Área fixa: o tamanho da nota nunca muda, então nada "pula" na tela.
          SizedBox(
            width: 112,
            height: 52,
            child: Align(
              alignment: Alignment.centerLeft,
              child: NoteReadout(note: cur, cfg: app.cfg, zone: zone, size: 38),
            ),
          ),
          // Desvio e frequência, sempre no mesmo lugar.
          SizedBox(
            width: 86,
            height: 52,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // A cor escorre quadro a quadro (sem reiniciar a cada leitura).
                SmoothColor(
                  target: col,
                  builder: (context, c) => CentsLabel(cents: cur?.cents, size: 26, color: c),
                ),
                const SizedBox(height: 3),
                Text(
                  cur == null ? '' : '${cur.freq.toStringAsFixed(1)} Hz',
                  style: TextStyle(color: AppColors.textDim, fontSize: 12, height: 1.0),
                ),
              ],
            ),
          ),
          Expanded(
            child: landscape
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: SmoothNeedle(cents: cur?.cents, zone: zone, mini: true),
                  )
                : const SizedBox.shrink(),
          ),
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
                case 'reset':
                  confirmResetGrid(context, app);
                case 'rotate':
                  _toggleRotate();
                case 'hide':
                  setState(() => _showControls = false);
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'reset',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.restart_alt),
                  title: Text('Zerar grade'),
                ),
              ),
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

  Widget _grid(bool landscape) {
    final (lo, hi) = app.gridOctaves;
    final scale = app.scaleMode ? app.scaleNotes.toSet() : <int>{};
    final octs = [for (var o = lo; o <= hi; o++) o]; // grave → agudo
    final pcs = [for (var p = 0; p < 12; p++) p];
    Widget cell(int midi) => Expanded(child: GridCell(app: app, midi: midi, scale: scale));

    // Como no Tonemap: 12 colunas (Dó a Si) e uma linha por oitava, agudos em cima,
    // tanto em pé quanto deitado.
    return Column(children: [
      for (final o in octs.reversed)
        Expanded(child: Row(children: [for (final p in pcs) cell(o * 12 + p)])),
    ]);
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
