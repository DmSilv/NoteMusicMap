import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Logo do Notemusic: um mostrador de afinador (arco verde, a cor do app) com
/// uma nota musical branca no centro. Mesma geometria de tools/make_icons.mjs.
class AppLogo extends StatelessWidget {
  final double size;
  final bool rounded;
  const AppLogo({super.key, this.size = 64, this.rounded = true});

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Logo do Notemusic',
        image: true,
        child: SizedBox(width: size, height: size, child: CustomPaint(painter: _LogoPainter(rounded))),
      );
}

class _LogoPainter extends CustomPainter {
  final bool rounded;
  _LogoPainter(this.rounded);

  static const _top = Color(0xFF17323C);
  static const _bottom = Color(0xFF0A141C);
  static const _green = Color(0xFF1FE68F);

  // Geometria (0..1), ângulos em graus com y para cima.
  static const _pvx = 0.5, _pvy = 0.60;
  static const _r = 0.29, _sw = 0.085;
  static const _a0 = 205.0, _a1 = -25.0;
  static const _hx = 0.455, _hy = 0.655, _hrx = 0.088, _hry = 0.061, _tilt = 22.0;
  static const _nw = 0.042;

  /// Arco de uma cor só: a cor de destaque do app.
  static Color _arc(double t) => _green;

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

    // Nota musical (colcheia): cabeça inclinada, haste e bandeira.
    final white = Paint()..color = Colors.white;
    canvas.save();
    canvas.translate(_hx * w, _hy * w);
    canvas.rotate(-_tilt * math.pi / 180);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 2 * _hrx * w, height: 2 * _hry * w), white);
    canvas.restore();
    final line = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = _nw * w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawLine(Offset(0.531 * w, 0.645 * w), Offset(0.531 * w, 0.385 * w), line);
    final flag = Path()
      ..moveTo(0.531 * w, 0.385 * w)
      ..lineTo(0.58 * w, 0.418 * w)
      ..lineTo(0.617 * w, 0.47 * w)
      ..lineTo(0.602 * w, 0.535 * w);
    canvas.drawPath(flag, line);
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.rounded != rounded;
}
