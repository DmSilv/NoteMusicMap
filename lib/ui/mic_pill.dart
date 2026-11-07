import 'package:flutter/material.dart';

import '../app_state.dart';
import 'theme.dart';

/// Aviso fixo na barra superior enquanto o microfone está captando: ponto
/// pulsante + "Ouvindo". Visível em qualquer aba; tocar desliga.
class MicPill extends StatefulWidget {
  final AppState app;
  const MicPill({super.key, required this.app});

  @override
  State<MicPill> createState() => _MicPillState();
}

class _MicPillState extends State<MicPill> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.app.micOn,
      builder: (context, on, _) {
        if (on) {
          if (!_c.isAnimating) _c.repeat(reverse: true);
        } else {
          _c.stop();
          return const SizedBox.shrink();
        }
        final color = AppColors.sharp;
        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Tooltip(
            message: 'Microfone ligado. Toque para desligar',
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => widget.app.stopListening(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withValues(alpha: 0.7)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  AnimatedBuilder(
                    animation: _c,
                    builder: (context, _) => Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: 0.45 + 0.55 * _c.value),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('Ouvindo',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: color)),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}
