import 'dart:async';

import 'package:flutter/material.dart';

import 'design_system.dart';
import 'theme.dart';

/// "Momento de sucesso": uma folha que sobe de baixo com um ✓ desenhado, uma frase e um detalhe,
/// e some sozinha. Serve para os poucos momentos em que algo importante deu certo (pegar um
/// horário, marcar uma aula, enviar uma tarefa). Um toque (ou arrastar para baixo) fecha na hora.
/// Erros e avisos comuns continuam no aviso do topo ([showToast]).
Future<void> showSuccessMoment(
  BuildContext context,
  String title, {
  String detail = '',
}) async {
  try {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(Ds.radiusCard),
        ),
      ),
      builder: (c) => _SuccessBody(title: title, detail: detail),
    );
  } catch (_) {
    // Se a folha não puder abrir, o aviso comum ainda cobre o caso.
  }
}

class _SuccessBody extends StatefulWidget {
  final String title;
  final String detail;
  const _SuccessBody({required this.title, required this.detail});

  @override
  State<_SuccessBody> createState() => _SuccessBodyState();
}

class _SuccessBodyState extends State<_SuccessBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
  );
  Timer? _close;

  @override
  void initState() {
    super.initState();
    _c.forward();
    _close = Timer(const Duration(milliseconds: 2400), () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _close?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    if (still) _c.value = 1;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).maybePop(),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Ds.screenPad,
              Ds.s24,
              Ds.screenPad,
              Ds.s24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) => SizedBox(
                    width: 96,
                    height: 96,
                    child: CustomPaint(
                      painter: _CheckPainter(_c.value, AppColors.inTune),
                    ),
                  ),
                ),
                const SizedBox(height: Ds.s16),
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: Ds.title().copyWith(fontSize: 22),
                ),
                if (widget.detail.isNotEmpty) ...[
                  const SizedBox(height: Ds.s8),
                  Text(
                    widget.detail,
                    textAlign: TextAlign.center,
                    style: Ds.support().copyWith(fontSize: 15),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Círculo que cresce e um ✓ que é traçado na sequência.
class _CheckPainter extends CustomPainter {
  final double t;
  final Color color;
  _CheckPainter(this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final grow = Curves.easeOutBack.transform((t / 0.45).clamp(0.0, 1.0));
    canvas.drawCircle(
      c,
      r * 0.92 * grow,
      Paint()..color = color.withValues(alpha: 0.16),
    );
    canvas.drawCircle(
      c,
      r * 0.92 * grow,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    final p = ((t - 0.35) / 0.55).clamp(0.0, 1.0);
    if (p <= 0) return;
    final path = Path()
      ..moveTo(c.dx - r * 0.34, c.dy + r * 0.02)
      ..lineTo(c.dx - r * 0.10, c.dy + r * 0.28)
      ..lineTo(c.dx + r * 0.38, c.dy - r * 0.24);
    final m = path.computeMetrics().first;
    canvas.drawPath(
      m.extractPath(0, m.length * Curves.easeOut.transform(p)),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.t != t || old.color != color;
}
