
import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

/// Nome de nota com o acidente (♯/♭) elevado e a oitava pequena embaixo,
/// alinhados à linha de base: "Sol" + ♯ + 4. Largura sempre previsível.
class NoteLabel extends StatelessWidget {
  /// Ex.: 'Sol♯' ou 'Dó'.
  final String name;
  final int? octave;
  final double size;
  final Color color;
  final FontWeight weight;

  const NoteLabel({
    super.key,
    required this.name,
    this.octave,
    required this.size,
    required this.color,
    this.weight = FontWeight.w800,
  });

  /// Cria a partir de um número MIDI e da configuração de afinação.
  factory NoteLabel.midi(
    int midi,
    TuningConfig cfg, {
    Key? key,
    bool withOctave = true,
    required double size,
    required Color color,
    FontWeight weight = FontWeight.w800,
  }) {
    final shown = midi + cfg.transpose;
    return NoteLabel(
      key: key,
      name: noteName(midi, cfg),
      octave: withOctave ? (shown ~/ 12) - 1 : null,
      size: size,
      color: color,
      weight: weight,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasAcc = name.endsWith('♯') || name.endsWith('♭');
    final base = hasAcc ? name.substring(0, name.length - 1) : name;
    final acc = hasAcc ? name.substring(name.length - 1) : null;
    TextStyle st(double s, {FontWeight? w, Color? c}) => TextStyle(
        fontSize: s, fontWeight: w ?? weight, color: c ?? color, height: 1.0);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(base, style: st(size)),
        if (acc != null)
          Padding(
            padding: EdgeInsets.only(left: size * 0.03),
            child: Transform.translate(
              offset: Offset(0, -size * 0.30),
              child: Text(acc, style: st(size * 0.64)),
            ),
          ),
        if (octave != null)
          Padding(
            padding: EdgeInsets.only(left: size * 0.05),
            child: Transform.translate(
              offset: Offset(0, size * 0.10),
              child: Text('$octave', style: st(size * 0.46, w: FontWeight.w700, c: color.withValues(alpha: 0.8))),
            ),
          ),
      ],
    );
  }
}

/// Desvio em cents: símbolo ♯/♭ + número, alinhados. O número "rola" até o
/// novo valor em vez de saltar.
class CentsLabel extends StatelessWidget {
  final double? cents;
  final double size;
  final Color color;
  const CentsLabel({super.key, required this.cents, required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    final target = cents;
    final r = target?.round() ?? 0;
    final symbol = target == null ? '' : (r > 0 ? '♯' : (r < 0 ? '♭' : ''));
    return TweenAnimationBuilder<double>(
      tween: Tween(end: (target ?? 0).abs()),
      duration: const Duration(milliseconds: 170),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) {
        if (target == null) return SizedBox(height: size);
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            if (symbol.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(right: size * 0.06),
                child: Text(symbol,
                    style: TextStyle(
                        fontSize: size * 0.9,
                        fontWeight: FontWeight.w800,
                        color: color,
                        height: 1.0)),
              ),
            Text(v.round().toString(),
                style: TextStyle(
                    fontSize: size,
                    fontWeight: FontWeight.w800,
                    color: color,
                    height: 1.0,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        );
      },
    );
  }
}

/// Leitura da nota atual com troca animada (desliza e some/aparece) e cor que
/// escorre entre grave, afinado e agudo. Ocupa sempre a mesma área.
class NoteReadout extends StatelessWidget {
  final TrackedNote? note;
  final TuningConfig cfg;
  final double zone;
  final double size;
  final bool withOctave;
  const NoteReadout({
    super.key,
    required this.note,
    required this.cfg,
    required this.zone,
    this.size = 40,
    this.withOctave = true,
  });

  @override
  Widget build(BuildContext context) {
    final n = note;
    final target = n == null ? AppColors.textDim : intonationColor(n.cents, zone);
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: target),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOutCubic,
      builder: (context, c, _) {
        final color = c ?? target;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.centerLeft,
            children: [...previous, ?current],
          ),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.18), end: Offset.zero).animate(anim),
              child: ScaleTransition(scale: Tween(begin: 0.9, end: 1.0).animate(anim), child: child),
            ),
          ),
          child: n == null
              ? Text('–',
                  key: const ValueKey('none'),
                  style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: color, height: 1.0))
              : NoteLabel.midi(n.midi, cfg,
                  key: ValueKey(n.midi), size: size, color: color, withOctave: withOctave),
        );
      },
    );
  }
}
