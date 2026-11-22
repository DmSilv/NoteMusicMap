import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:afina_core/afina_core.dart';

/// Logo do Notemusic: mostrador de afinador "Marcas e ponteiro" (opção 2B do
/// laboratório de logo). Sete marcas em leque, ponteiro verde no centro (afinado)
/// e pivô branco, sobre petróleo. Mesma geometria de tools/make_icons.mjs.
class AppLogo extends StatelessWidget {
  final double size;
  final bool rounded;
  const AppLogo({super.key, this.size = 64, this.rounded = true});

  @override
  Widget build(BuildContext context) => Semantics(
        label: tr('Logo do Notemusic'),
        image: true,
        child: SizedBox(width: size, height: size, child: CustomPaint(painter: _LogoPainter(rounded))),
      );
}

class _LogoPainter extends CustomPainter {
  final bool rounded;
  _LogoPainter(this.rounded);

  static const _top = Color(0xFF2D7790);
  static const _bottom = Color(0xFF2A6F83);
  static const _green = Color(0xFF1FE68F);
  static const _tick = Color(0xFFD5E9EF);

  // Geometria (0..1); ângulos em graus a partir da vertical, no sentido horário.
  static const _pvx = 0.5, _pvy = 0.62;
  static const _tickAngles = [-63.0, -42.0, -21.0, 21.0, 42.0, 63.0];
  static const _r0 = 0.22, _r1 = 0.30, _tw = 0.065;
  static const _hubR = 0.075, _needlePad = 0.015;

  Offset _pt(double a, double r, double w) =>
      Offset((_pvx + r * math.sin(a * math.pi / 180)) * w, (_pvy - r * math.cos(a * math.pi / 180)) * w);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final rect = Rect.fromLTWH(0, 0, w, w);
    final shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [_top, _bottom],
    ).createShader(rect);
    if (rounded) {
      canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(w * 0.22)), Paint()..shader = shader);
    } else {
      canvas.drawRect(rect, Paint()..shader = shader);
    }

    final tick = Paint()
      ..color = _tick
      ..style = PaintingStyle.stroke
      ..strokeWidth = _tw * w
      ..strokeCap = StrokeCap.round;
    for (final a in _tickAngles) {
      canvas.drawLine(_pt(a, _r0, w), _pt(a, _r1, w), tick);
    }

    // Ponteiro: triângulo com pontas arredondadas.
    final needle = Path()
      ..moveTo(0.455 * w, 0.62 * w)
      ..lineTo(0.545 * w, 0.62 * w)
      ..lineTo(0.5 * w, 0.32 * w)
      ..close();
    canvas.drawPath(needle, Paint()..color = _green);
    canvas.drawPath(
      needle,
      Paint()
        ..color = _green
        ..style = PaintingStyle.stroke
        ..strokeWidth = _needlePad * 2 * w
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.drawCircle(Offset(_pvx * w, _pvy * w), _hubR * w, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.rounded != rounded;
}
