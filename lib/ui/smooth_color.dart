import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Duas cores estão tão próximas que a diferença não aparece na tela.
bool colorsClose(Color a, Color b, {double tol = 0.004}) =>
    (a.r - b.r).abs() < tol &&
    (a.g - b.g).abs() < tol &&
    (a.b - b.b).abs() < tol &&
    (a.a - b.a).abs() < tol;

/// Cor que ESCORREGA até o alvo, quadro a quadro da tela.
///
/// O jeito comum (`TweenAnimationBuilder` com uma curva) reinicia a animação a
/// cada leitura do microfone (~30 por segundo); como as curvas começam devagar,
/// a cor fica "arrastando" e nunca chega. Aqui não há reinício: a cada quadro a
/// cor anda uma fração fixa do caminho (suavização exponencial, constante de
/// tempo [tau]), então segue o alvo de forma contínua e sem trancos. O relógio
/// só roda enquanto a cor ainda está se movendo.
class SmoothColor extends StatefulWidget {
  final Color target;

  /// Constante de tempo (s): menor = mais rápido. ~0,09 s dá um escorrer suave.
  final double tau;
  final Widget Function(BuildContext context, Color color) builder;

  const SmoothColor({super.key, required this.target, required this.builder, this.tau = 0.09});

  @override
  State<SmoothColor> createState() => _SmoothColorState();
}

class _SmoothColorState extends State<SmoothColor> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  late Color _color = widget.target;
  final ValueNotifier<int> _repaint = ValueNotifier(0);
  Duration _last = Duration.zero;

  @override
  void didUpdateWidget(SmoothColor old) {
    super.didUpdateWidget(old);
    if (!colorsClose(_color, widget.target) && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    _color = Color.lerp(_color, widget.target, 1 - math.exp(-dt / widget.tau))!;
    if (colorsClose(_color, widget.target)) {
      _color = widget.target;
      _ticker.stop();
    }
    _repaint.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _repaint,
        builder: (context, _) => widget.builder(context, _color),
      );
}
