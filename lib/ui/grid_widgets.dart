import 'package:flutter/material.dart';

import '../app_state.dart';
import 'theme.dart';

/// Seletor de oitavas: uma faixa fixa com as oitavas 0 a 8 sempre visíveis.
/// As que estão na grade ficam numa "janela" destacada. Toque num número ou
/// arraste o dedo para mover a janela; as setas movem uma oitava por vez.
class OctaveNav extends StatelessWidget {
  final AppState app;

  /// Mantido por compatibilidade; o seletor tem um só visual agora.
  final bool compact;

  /// Se informado, mostra um botão com mais opções (quantas oitavas, seguir nota).
  final VoidCallback? onMore;

  /// Mostra uma linha de ajuda sob a faixa.
  final bool showHint;

  const OctaveNav({
    super.key,
    required this.app,
    this.compact = false,
    this.onMore,
    this.showHint = false,
  });

  @override
  Widget build(BuildContext context) {
    final (lo, hi) = app.gridOctaves;
    final canDown = lo > AppState.minOct;
    final canUp = hi < AppState.maxOct;

    Widget arrow(IconData i, String tip, VoidCallback? on) => IconButton(
          tooltip: tip,
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(backgroundColor: AppColors.surface2),
          icon: Icon(i, size: 24),
          onPressed: on,
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            arrow(Icons.chevron_left, 'Oitava abaixo',
                canDown ? () => app.shiftOctaves(-1) : null),
            const SizedBox(width: 8),
            Expanded(child: _OctaveTrack(app: app)),
            const SizedBox(width: 8),
            arrow(Icons.chevron_right, 'Oitava acima',
                canUp ? () => app.shiftOctaves(1) : null),
            if (onMore != null) ...[
              const SizedBox(width: 8),
              arrow(Icons.tune, 'Mais opções de oitavas', onMore),
            ],
          ],
        ),
        if (showHint)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Toque num número ou arraste para escolher as oitavas. '
              'Oitava 4 é a do Lá 440 Hz.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _OctaveTrack extends StatelessWidget {
  final AppState app;
  const _OctaveTrack({required this.app});

  static const int _count = 9; // oitavas 0..8

  @override
  Widget build(BuildContext context) {
    final (lo, hi) = app.gridOctaves;
    final first = lo - 1; // rótulo da primeira oitava visível
    final n = hi - lo + 1;

    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final cell = w / _count;

      void goTo(double dx) {
        final label = (dx / cell).floor().clamp(0, _count - 1);
        app.goToOctave(label);
      }

      return Semantics(
        label: 'Oitavas $first a ${hi - 1}. Toque ou arraste para mudar.',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => goTo(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => goTo(d.localPosition.dx),
          child: SizedBox(
            height: 44,
            child: Stack(
              children: [
                // trilho
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                // janela das oitavas visíveis
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  left: first * cell,
                  width: n * cell,
                  top: 3,
                  bottom: 3,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.accent, width: 1.5),
                    ),
                  ),
                ),
                // números
                Row(
                  children: [
                    for (var label = 0; label < _count; label++)
                      Expanded(
                        child: Center(
                          child: Text(
                            '$label',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: (label + 1 >= lo && label + 1 <= hi)
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              color: (label + 1 >= lo && label + 1 <= hi)
                                  ? AppColors.text
                                  : AppColors.textDim,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

/// Legenda de cores com valores em cents e o que fazer para corrigir.
class IntonationLegend extends StatelessWidget {
  final double zone;
  final bool compact;
  const IntonationLegend({super.key, required this.zone, this.compact = false});

  @override
  Widget build(BuildContext context) {
    const range = 30.0;
    final colors = [for (var c = -range; c <= range; c += 3) intonationColor(c, zone)];
    final z = (zone / range).clamp(0.0, 1.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 14,
          child: LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth;
            return Stack(children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    gradient: LinearGradient(colors: colors),
                  ),
                ),
              ),
              // zona "afinada"
              Positioned(
                left: w / 2 - w / 2 * z,
                width: w * z,
                top: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.text.withValues(alpha: 0.85), width: 1.5),
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
              ),
            ]);
          }),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LegendTag(
              icon: Icons.arrow_upward,
              color: AppColors.flat,
              title: 'Grave',
              sub: compact ? 'suba' : 'afinação baixa: suba',
            ),
            const SizedBox(width: 6),
            _LegendTag(
              icon: Icons.check_circle,
              color: AppColors.inTune,
              title: 'Afinado',
              sub: compact ? '±${zone.round()}' : 'até ${zone.round()} de desvio',
            ),
            const SizedBox(width: 6),
            _LegendTag(
              icon: Icons.arrow_downward,
              color: AppColors.sharp,
              title: 'Agudo',
              sub: compact ? 'desça' : 'afinação alta: desça',
            ),
          ],
        ),
        if (!compact)
          Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'A cor mostra a distância do som ideal em cents (100 cents = 1 semitom). '
              'Quanto mais forte a cor, mais longe você está.',
              style: TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _LegendTag extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? sub;
  const _LegendTag({required this.icon, required this.color, required this.title, this.sub});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.7)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)),
                  if (sub != null)
                    Text(sub!,
                        style: TextStyle(color: AppColors.text, fontSize: 11, height: 1.2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
/// Dica de correção para a nota atual: "Grave ♭15 · suba um pouco".
class CorrectionHint extends StatelessWidget {
  final double? cents;
  final double zone;
  const CorrectionHint({super.key, required this.cents, required this.zone});

  @override
  Widget build(BuildContext context) {
    final c = cents;
    String text;
    IconData icon;
    Color color;
    if (c == null) {
      text = 'Toque uma nota';
      icon = Icons.hearing;
      color = AppColors.textDim;
    } else if (c.abs() <= zone) {
      text = 'Afinada';
      icon = Icons.check_circle;
      color = AppColors.inTune;
    } else {
      final a = c.abs();
      final how = a <= zone * 2.5 ? 'um pouco' : (a <= zone * 6 ? '' : 'bastante');
      final dir = c < 0 ? 'suba' : 'desça';
      text = '${c < 0 ? 'Grave ♭' : 'Aguda ♯'}${a.round()} · $dir ${how.isEmpty ? '' : how}'.trim();
      icon = c < 0 ? Icons.arrow_upward : Icons.arrow_downward;
      color = intonationColor(c, zone);
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      child: Row(
        // só troca com animação quando muda a direção, não a cada cent
        key: ValueKey(icon.codePoint),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15)),
        ],
      ),
    );
  }
}

/// Modal com as opções extras de oitavas: quantas mostrar e seguir a nota.
void showOctaveSheet(BuildContext context, AppState app) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(
      child: ListenableBuilder(
        listenable: app,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Oitavas na grade',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              Text('Quantas oitavas mostrar: ${app.gridOctCount}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Slider(
                min: 2,
                max: 7,
                divisions: 5,
                value: app.gridOctCount.toDouble(),
                onChanged: (v) => app.setOctCount(v.round()),
              ),
              Text('Menos oitavas = quadrados maiores e mais fáceis de ler.',
                  style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Seguir a nota que eu toco'),
                subtitle: const Text('A grade muda de oitava sozinha quando você sobe ou desce.'),
                value: app.gridFollow,
                onChanged: app.setFollow,
              ),
              const SizedBox(height: 4),
              Text('Atalhos: toque no número da oitava (Dó4 é a oitava do Lá 440 Hz).',
                  style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Pergunta antes de apagar as cores acumuladas da grade.
Future<void> confirmResetGrid(BuildContext context, AppState app) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Zerar a grade?'),
      content: const Text(
          'As cores acumuladas das notas serão apagadas. Seu tempo de estudo e as escalas salvas não mudam.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Zerar')),
      ],
    ),
  );
  if (ok == true) {
    app.resetGrid();
    app.say('Grade zerada');
  }
}
