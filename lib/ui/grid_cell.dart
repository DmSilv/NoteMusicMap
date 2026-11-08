import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../app_state.dart';
import 'cell_gauge.dart';
import 'note_widgets.dart';
import 'theme.dart';

/// Sustenido/bemol (teclas pretas): Dó♯, Ré♯, Fá♯, Sol♯, Lá♯.
bool _isAccidental(int midi) => const {1, 3, 6, 8, 10}.contains(midi % 12);

/// Dá a [c] um tom azul-ardósia leve (brilho parecido, para não sumir no
/// fundo do cartão nem competir com as cores de afinação).
Color _accidentalTone(Color c) =>
    Color.lerp(c, AppColors.dark ? const Color(0xFF2B4766) : const Color(0xFFB4C9E2), 0.65)!;

/// Um quadrado da grade: nota, cor do histórico e, na nota que toca, o afinador
/// horizontal vivo. Usado na grade em tela cheia e no teclado do cartão da aba.
class GridCell extends StatelessWidget {
  final AppState app;
  final int midi;
  final Set<int> scale;
  final double labelSize;
  final double radius;
  final VoidCallback? onTap;
  const GridCell({
    super.key,
    required this.app,
    required this.midi,
    required this.scale,
    this.labelSize = 17,
    this.radius = 10,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final zone = app.zone.cents;
    final v = app.grid.view(midi, app.now);
    final cur = app.shown;
    final playing = cur?.midi == midi;
    final inScale = scale.isEmpty || scale.contains(midi);
    final isTarget = scale.contains(midi);

    // Sustenidos/bemóis (teclas pretas do piano) ganham um tom azulado leve,
    // diferente das notas naturais. Só muda o fundo sem histórico; as cores de afinação
    // continuam iguais, porque elas carregam o significado.
    final accidental = _isAccidental(midi);
    final restFill = accidental ? _accidentalTone(AppColors.surface2) : AppColors.surface2;
    var fill = restFill;
    if (v != null) {
      // A nota que soa agora tem a cor cheia; as outras perdem força depressa (ficam só como pista),
      // para a grade não virar uma mancha de cores e dar para ver onde está a nota atual.
      final recency = playing ? 1.0 : (0.12 + 0.43 * (1 - v.age / 6).clamp(0.0, 1.0));
      final a = (0.5 + 0.5 * v.confidence) * v.alpha * recency;
      fill = Color.lerp(restFill, intonationColor(v.avgCents, zone), a)!;
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

    final cell = Padding(
      padding: const EdgeInsets.all(2),
      // Cor e borda animam juntas: nada "pula" entre leituras. Por cima fica a
      // camada viva (o afinador horizontal), só no quadrado da nota que toca.
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 750),
        curve: Curves.easeInOutCubic,
        decoration: BoxDecoration(
          color: dim
              ? (accidental ? _accidentalTone(AppColors.surface) : AppColors.surface).withValues(alpha: 0.5)
              : fill,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: playing
                ? AppColors.text
                : (isTarget && v == null ? AppColors.textDim : Colors.transparent),
            width: playing ? 3 : 1.2,
          ),
        ),
        child: LiveCellLayer(
          cents: playing ? cur?.cents : null,
          zone: zone,
          radius: radius - 3,
          silent: cur == null,
          builder: (context, live, ink) {
            // `live` (0..1) comanda tudo junto: o nome vai para o meio, a seta
            // de histórico some e o texto fica claro sobre o campo escuro.
            final color = Color.lerp(labelColor, ink, live)!;
            final weight = FontWeight.lerp(
                v == null ? FontWeight.w500 : FontWeight.w800, FontWeight.w800, live)!;
            return Stack(
              fit: StackFit.expand,
              children: [
                Align(
                  alignment: Alignment(0, lerpDouble(-0.34, 0.0, live)!),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      // Nome da nota com ♯/♭ elevado e oitava pequena, alinhados.
                      child: NoteLabel.midi(midi, app.cfg, size: labelSize, weight: weight, color: color),
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
        ),
      ),
    );
    if (onTap == null) return cell;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: cell);
  }
}
