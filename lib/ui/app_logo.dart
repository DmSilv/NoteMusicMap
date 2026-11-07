import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Logo do Tom e Tempo: um mostrador de afinador. O arco vai do azul (grave)
/// ao laranja (agudo) passando pelo verde (afinado); o ponteiro branco aponta
/// quase para o centro. Mesma geometria de tools/make_icons.mjs.
class AppLogo extends StatelessWidget {
  final double size;
  final bool rounded;
  const AppLogo({super.key, this.size = 64, this.rounded = true});

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Logo do Tom e Tempo',
        image: true,
        child: SizedBox(width: size, height: size, child: CustomPaint(painter: _LogoPainter(rounded))),
      );
}

class _LogoPainter extends CustomPainter {
  final bool rounded;
  _LogoPainter(this.rounded);

  static const _top = Color(0xFF17323C);
  static const _bottom = Color(0xFF0A141C);
  static const _blue = Color(0xFF2E9BFF);
  static const _green = Color(0xFF1FE68F);
  static const _orange = Color(0xFFFF9226);
  static const _hub = Color(0xFF0F1B24);

  // Geometria (0..1), ângulos em graus com y para cima.
  static const _pvx = 0.5, _pvy = 0.60;
  static const _r = 0.29, _sw = 0.085;
  static const _a0 = 205.0, _a1 = -25.0;
  static const _na = 84.0, _nl = 0.25, _nw = 0.038;
  static const _hubR = 0.058, _hubIn = 0.022;

  /// Azul → verde → laranja, misturando pelo matiz (sem passar por cinza).
  static Color _arc(double t) {
    final a = t < 0.5 ? _blue : _green;
    final b = t < 0.5 ? _green : _orange;
    final u = t < 0.5 ? t * 2 : (t - 0.5) * 2;
    return HSLColor.lerp(HSLColor.fromColor(a), HSLColor.fromColor(b), u)!.toColor();
  }

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

    final center = Offset(_pvx * w, _pvy * w);
    final arcRect = Rect.fromCircle(center: center, radius: _r * w);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _sw * w
      ..strokeCap = StrokeCap.butt;

    // Arco em pequenos trechos, cada um na sua cor.
    const n = 72;
    for (var i = 0; i < n; i++) {
      final t1 = i / n, t2 = (i + 1) / n;
      final a1 = _a0 - (_a0 - _a1) * t1;
      final sweepDeg = (_a0 - _a1) * (t2 - t1) + (i < n - 1 ? 0.5 : 0);
      canvas.drawArc(arcRect, -a1 * math.pi / 180, sweepDeg * math.pi / 180, false,
          stroke..color = _arc((t1 + t2) / 2));
    }
    // Pontas arredondadas.
    Offset endPoint(double a) => Offset(
          (_pvx + _r * math.cos(a * math.pi / 180)) * w,
          (_pvy - _r * math.sin(a * math.pi / 180)) * w,
        );
    canvas.drawCircle(endPoint(_a0), _sw * w / 2, Paint()..color = _arc(0));
    canvas.drawCircle(endPoint(_a1), _sw * w / 2, Paint()..color = _arc(1));

    // Ponteiro e cubo.
    final tip = Offset(
      (_pvx + _nl * math.cos(_na * math.pi / 180)) * w,
      (_pvy - _nl * math.sin(_na * math.pi / 180)) * w,
    );
    canvas.drawLine(
        center,
        tip,
        Paint()
          ..color = Colors.white
          ..strokeWidth = _nw * w
          ..strokeCap = StrokeCap.round);
    canvas.drawCircle(center, _hubR * w, Paint()..color = Colors.white);
    canvas.drawCircle(center, _hubIn * w, Paint()..color = _hub);
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.rounded != rounded;
}
