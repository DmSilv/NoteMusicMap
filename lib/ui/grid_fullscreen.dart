import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app_state.dart';
import 'cell_gauge.dart';
import 'grid_widgets.dart';
import 'needle.dart';
import 'note_widgets.dart';
import 'smooth_color.dart';
import 'theme.dart';

/// Grade em tela cheia para usar durante o estudo. Em pé: notas nas linhas
/// (agudos no topo) e oitavas nas colunas. Deitado: notas nas colunas e
/// oitavas nas linhas. Embaixo: legenda de cores e navegação de oitavas.
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
    Widget cell(int midi) => Expanded(child: _Cell(app: app, midi: midi, scale: scale));

    if (landscape) {
      return Column(children: [
        for (final o in octs.reversed)
          Expanded(child: Row(children: [for (final p in pcs) cell(o * 12 + p)])),
      ]);
    }
    return Column(children: [
      for (final p in pcs.reversed)
        Expanded(child: Row(children: [for (final o in octs) cell(o * 12 + p)])),
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

class _Cell extends StatelessWidget {
  final AppState app;
  final int midi;
  final Set<int> scale;
  const _Cell({required this.app, required this.midi, required this.scale});

  @override
  Widget build(BuildContext context) {
    final zone = app.zone.cents;
    final v = app.grid.view(midi, app.now);
    final cur = app.shown;
    final playing = cur?.midi == midi;
    final inScale = scale.isEmpty || scale.contains(midi);
    final isTarget = scale.contains(midi);

    var fill = AppColors.surface2;
    if (v != null) {
      final a = (0.5 + 0.5 * v.confidence) * v.alpha;
      fill = Color.lerp(AppColors.surface2, intonationColor(v.avgCents, zone), a)!;
    }
    final dim = !inScale && v == null;
    // Texto sempre legível: ajusta o fundo da célula se o contraste ficar baixo.
    var dark = AppColors.textDim;
    if (v != null) {
      final leg = legibleCell(fill);
      fill = leg.fill;
      dark = leg.text;
    }
    final inTune = v != null && v.avgCents.abs() <= zone;
    final labelColor = v == null ? (dim ? AppColors.outline : AppColors.textDim) : dark;

    return Padding(
      padding: const EdgeInsets.all(2),
      // Cor e borda animam juntas: nada "pula" entre leituras. Por cima fica a
      // camada viva, que só aparece no quadrado da nota que está tocando.
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 750),
        curve: Curves.easeInOutCubic,
        decoration: BoxDecoration(
          color: dim ? AppColors.surface.withValues(alpha: 0.5) : fill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: playing
                ? AppColors.text
                : (isTarget && v == null ? AppColors.textDim : Colors.transparent),
            width: playing ? 3 : 1.2,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            // Quadrado largo (ex.: grade em pé): o nome da nota fica à esquerda e
            // o mostrador ocupa o resto, com ponteiro bem maior. Quadrado alto ou
            // quase quadrado: o nome fica em cima e o mostrador embaixo.
            final wide = box.maxWidth >= 50 && box.maxWidth >= box.maxHeight * 1.6;
            final sideW = math.min(46.0, box.maxWidth * 0.46);
            return LiveCellLayer(
              cents: playing ? cur?.cents : null,
              zone: zone,
              radius: 7,
              detailed: true,
              labelBand: wide ? 0 : 24,
              labelLeft: wide ? sideW : 0,
              silent: cur == null,
              builder: (context, live, ink) {
                // `live` (0..1) comanda tudo junto: o nome da nota vai para o canto
                // (ou o topo), a seta de histórico some e a cor do texto acompanha
                // o fundo vivo.
                final color = Color.lerp(labelColor, ink, live)!;
                final weight = FontWeight.lerp(
                    v == null ? FontWeight.w500 : FontWeight.w800, FontWeight.w800, live)!;
                final ax = wide ? lerpDouble(0, -0.92, live)! : 0.0;
                final ay = wide ? lerpDouble(-0.34, -0.05, live)! : lerpDouble(-0.34, -0.86, live)!;
                final labelW = wide ? lerpDouble(box.maxWidth, sideW - 4, live)! : box.maxWidth;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Align(
                      alignment: Alignment(ax, ay),
                      child: SizedBox(
                        width: labelW,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: wide && live > 0.5 ? Alignment.centerLeft : Alignment.center,
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            // Nome da nota com ♯/♭ elevado e oitava pequena, alinhados.
                            child: NoteLabel.midi(midi, app.cfg,
                                size: 17, weight: weight, color: color),
                          ),
                        ),
                      ),
                    ),
                    if (v != null)
                      Align(
                        alignment: const Alignment(0, 0.58),
                        child: Opacity(
                          opacity: (1 - live).clamp(0.0, 1.0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                inTune
                                    ? Icons.check
                                    : (v.avgCents < 0 ? Icons.arrow_upward : Icons.arrow_downward),
                                size: 13,
                                color: dark,
                              ),
                              // Só o símbolo (♯ agudo / ♭ grave): o número não ajuda aqui.
                              if (!inTune)
                                Padding(
                                  padding: const EdgeInsets.only(left: 2),
                                  child: Text(v.avgCents > 0 ? '♯' : '♭',
                                      style: TextStyle(
                                          fontSize: 15,
                                          height: 1.0,
                                          fontWeight: FontWeight.w800,
                                          color: dark)),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
