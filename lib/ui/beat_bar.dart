import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'theme.dart';

/// A barra de "quanto já segurou afinada". Com o metrônomo ligado ela dá uma leve pulsada a cada tempo (mais forte no tempo
/// forte): a barra continua sendo só a medida, e o pulso ajuda a sentir o andamento. Sem metrônomo, ou se o aparelho pede
/// menos movimento, fica parada.
class BeatBar extends StatefulWidget {
  final AppState app;

  /// 0..1 do que já foi segurado.
  final double value;
  final Color color;
  const BeatBar({super.key, required this.app, required this.value, required this.color});

  @override
  State<BeatBar> createState() => _BeatBarState();
}

class _BeatBarState extends State<BeatBar> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 300), value: 1);
  double _strength = 0.6;
  MetroBeat? _last;

  @override
  void initState() {
    super.initState();
    widget.app.metroBeat.addListener(_onBeat);
  }

  @override
  void dispose() {
    widget.app.metroBeat.removeListener(_onBeat);
    _c.dispose();
    super.dispose();
  }

  void _onBeat() {
    final b = widget.app.metroBeat.value;
    if (identical(b, _last) || b.hidden || !widget.app.metroPlayer.running) return;
    _last = b;
    _strength = b.accent == Accent.strong ? 1.0 : 0.6;
    if (mounted) _c.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final k = still ? 0.0 : (1 - Curves.easeOut.transform(_c.value)) * _strength; // 1 no instante do tempo, cai até 0
        return SizedBox(
          height: 14,
          child: Center(
            child: Container(
              height: 10 + 4 * k,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: k > 0.02 ? [BoxShadow(color: widget.color.withValues(alpha: 0.45 * k), blurRadius: 10 * k, spreadRadius: 1 * k)] : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: widget.value),
                  duration: const Duration(milliseconds: 160),
                  builder: (context, v, _) => LinearProgressIndicator(minHeight: 14, value: v, backgroundColor: AppColors.surface2, color: widget.color),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
