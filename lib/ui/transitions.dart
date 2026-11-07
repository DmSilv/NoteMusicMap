import 'package:flutter/material.dart';

/// Troca "sai e depois entra" para usar no `AnimatedSwitcher`.
///
/// O padrão (fade cruzado) deixa os dois textos um em cima do outro por um
/// instante, o que parece bagunçado. Aqui quem sai some depressa (e encolhe um
/// pouco) e quem entra só começa a aparecer quando o outro já foi (crescendo
/// até o tamanho normal), então a troca fica limpa e fluida.
Widget fadeThroughTransition(Widget child, Animation<double> animation,
    {double scaleFrom = 0.92}) {
  return AnimatedBuilder(
    animation: animation,
    builder: (context, _) {
      final t = animation.value;
      // O widget que está saindo anda de 1 para 0; o que entra, de 0 para 1.
      final outgoing = animation.status == AnimationStatus.reverse;
      final opacity = outgoing
          ? Curves.easeIn.transform(t)
          : const Interval(0.45, 1.0, curve: Curves.easeOut).transform(t);
      final scale = outgoing
          ? 0.96 + 0.04 * t
          : scaleFrom + (1 - scaleFrom) * const Interval(0.3, 1.0, curve: Curves.easeOutCubic).transform(t);
      return Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.scale(scale: scale, child: child),
      );
    },
  );
}
