import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'theme.dart';

/// Ponteiro do afinador com movimento fluido.
///
/// Em vez de reiniciar uma animação a cada leitura do microfone (o que dá
/// trancos), um relógio a 60 fps aproxima o ponteiro do valor alvo com
/// suavização exponencial. O resultado desliza continuamente mesmo que as
/// leituras cheguem só ~28 vezes por segundo, e a cor acompanha a posição.
/// O relógio para sozinho quando o ponteiro assenta, para poupar bateria.
class SmoothNeedle extends StatefulWidget {
  final double? cents;
  final double zone;

  /// true = versão fina para a barra da tela cheia.
  final bool mini;
  const SmoothNeedle({super.key, required this.cents, required this.zone, this.mini = false});

  @override
  State<SmoothNeedle> createState() => _SmoothNeedleState();
}

class _NeedleValue {
  double pos = 0; // -50..50, suavizado
  double alpha = 0; // 0 = oculto, 1 = visível
}

class _SmoothNeedleState extends State<SmoothNeedle> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _NeedleValue _v = _NeedleValue();
  final ValueNotifier<int> _repaint = ValueNotifier(0);
  Duration _last = Duration.zero;

  // Constantes de tempo (s): menor = mais rápido.
  static const double _tauPos = 0.075;
  static const double _tauAlpha = 0.14;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    _wake();
  }

  void _wake() {
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(SmoothNeedle old) {
    super.didUpdateWidget(old);
    if (old.cents != widget.cents || old.zone != widget.zone) _wake();
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    final has = widget.cents != null;
    final target = (widget.cents ?? _v.pos).clamp(-50.0, 50.0);

    // Ao reaparecer depois de ficar oculto, nasce já na posição certa
    // (sem varrer a escala inteira).
    if (has && _v.alpha < 0.02) _v.pos = target;

    final kp = 1 - math.exp(-dt / _tauPos);
    final ka = 1 - math.exp(-dt / _tauAlpha);
    final dPos = (target - _v.pos) * kp;
    final dAlpha = ((has ? 1.0 : 0.0) - _v.alpha) * ka;
    _v.pos += dPos;
    _v.alpha += dAlpha;
    _repaint.value++;

    final settled = dPos.abs() < 0.005 && dAlpha.abs() < 0.002;
    if (settled) {
      _v.pos = target;
      _v.alpha = has ? 1.0 : 0.0;
      _ticker.stop();
      _repaint.value++;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.cents == null ? 'Sem nota' : 'Desvio de ${widget.cents!.round()} centésimos de semitom',
      child: SizedBox(
        height: widget.mini ? 60 : 74,
        width: double.infinity,
        child: CustomPaint(
          painter: _NeedlePainter(_v, widget.zone, widget.mini, _repaint),
        ),
      ),
    );
  }
}

class _NeedlePainter extends CustomPainter {
  final _NeedleValue v;
  final double zone;
  final bool mini;

  _NeedlePainter(this.v, this.zone, this.mini, Listenable repaint) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final y = mini ? size.height / 2 : 30.0;
    final half = mini ? 6.0 : 7.0;
    double x(double c) => w / 2 + c / 50 * (w / 2 - (mini ? 8 : 10));

    // trilho
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(0, y - half, w, y + half), Radius.circular(half)),
        Paint()..color = AppColors.surface2);
    // zona "afinada"
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTRB(x(-zone), y - half, x(zone), y + half), Radius.circular(half)),
        Paint()..color = AppColors.inTune.withValues(alpha: 0.35));

    if (mini) {
      canvas.drawLine(Offset(w / 2, y - 14), Offset(w / 2, y + 14),
          Paint()
            ..color = AppColors.textDim
            ..strokeWidth = 1.5);
    } else {
      final tick = Paint()
        ..color = AppColors.textDim
        ..strokeWidth = 1.5;
      for (var c = -50; c <= 50; c += 10) {
        final major = c % 25 == 0;
        canvas.drawLine(Offset(x(c.toDouble()), y + 12),
            Offset(x(c.toDouble()), y + (major ? 24 : 18)), tick);
      }
      for (final c in [-50, -25, 0, 25, 50]) {
        final tp = TextPainter(
          text: TextSpan(
              text: c > 0 ? '+$c' : (c < 0 ? '−${-c}' : '0'),
              style: TextStyle(color: AppColors.textDim, fontSize: 11)),
          textDirection: TextDirection.ltr,
        )..layout();
        // Centrado no traço, mas sem passar das bordas do medidor.
        final left = (x(c.toDouble()) - tp.width / 2).clamp(0.0, w - tp.width);
        tp.paint(canvas, Offset(left, y + 26));
      }
    }

    // ponteiro (some e aparece com fade; a cor segue a posição suavizada)
    if (v.alpha > 0.01) {
      final col = intonationColor(v.pos, zone).withValues(alpha: v.alpha.clamp(0.0, 1.0));
      final px = x(v.pos);
      canvas.drawLine(Offset(px, y - (mini ? 18 : 16)), Offset(px, y + (mini ? 18 : 16)),
          Paint()
            ..color = col
            ..strokeWidth = mini ? 5 : 5
            ..strokeCap = StrokeCap.round);
      if (!mini) canvas.drawCircle(Offset(px, y - 18), 6, Paint()..color = col);
    }
  }

  @override
  bool shouldRepaint(_NeedlePainter old) => old.zone != zone || old.mini != mini;
}
