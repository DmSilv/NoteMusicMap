import 'package:flutter/material.dart';

import '../app_state.dart';
import 'note_widgets.dart';
import 'theme.dart';

/// Sustenido/bemol (teclas pretas): Dó♯, Ré♯, Fá♯, Sol♯, Lá♯.
bool _isAccidental(int midi) => const {1, 3, 6, 8, 10}.contains(midi % 12);

/// Dá a [c] um tom azul-ardósia leve (brilho parecido, para não sumir no
/// fundo do cartão nem competir com as cores de afinação).
Color _accidentalTone(Color c) =>
    Color.lerp(c, AppColors.dark ? const Color(0xFF2B4766) : const Color(0xFFB4C9E2), 0.65)!;

/// Um quadrado da grade: nota, cor do histórico, quantas vezes foi tocada e,
/// na nota que toca, uma borda de destaque. Usado na aba Grade e na tela cheia.
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
      // Histórico: a cor das notas já tocadas fica (só muda quando a nota é tocada de novo), um pouco
      // mais suave que a da nota atual, que ganha a borda e a agulha.
      final recency = playing ? 1.0 : 0.78;
      final a = playing ? 1.0 : (0.5 + 0.5 * v.confidence) * v.alpha * recency;
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
    final labelColor = v == null ? (dim ? AppColors.outline : AppColors.textDim) : dark;
    final weight = v == null ? FontWeight.w500 : FontWeight.w800;

    // Sem ponteiro: a nota que toca só ganha uma borda forte e um leve "pulo".
    // Dentro do quadrado ficam o nome e, embaixo, quantas vezes foi tocada (×3).
    final cell = Padding(
      padding: const EdgeInsets.all(2),
      child: AnimatedScale(
        scale: playing ? 1.06 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: Duration(milliseconds: playing ? 90 : 750),
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
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Nome da nota com ♯/♭ elevado e oitava pequena, alinhados.
                    NoteLabel.midi(midi, app.cfg,
                        size: labelSize, weight: weight, color: labelColor),
                    if (v != null)
                      Text('×${v.plays}',
                          style: TextStyle(
                              fontSize: 11,
                              height: 1.1,
                              fontWeight: FontWeight.w700,
                              color: dark.withValues(alpha: 0.85))),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (onTap == null) return cell;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: cell);
  }
}
