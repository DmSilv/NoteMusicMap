import 'dart:async';

import 'package:flutter/material.dart';

import '../design_system.dart';
import '../theme.dart';
import 'package:afina_core/afina_core.dart';

/// Tutorial guiado: escurece a tela, deixa um buraco redondo no botão e mostra uma caixinha com o que ele faz.
/// Nunca é obrigatório (sempre tem "Pular") e nunca trava: se um botão não estiver na tela, o passo é pulado.
/// O mecanismo é um só; cada tutorial é só uma lista de [TourStep].

/// Um passo: qual elemento destacar (pela chave) e o texto.
class TourStep {
  final GlobalKey target;
  final String title;
  final String text;
  const TourStep(this.target, this.title, this.text);
}

/// Chaves dos elementos que os tutoriais destacam (uma por elemento, usadas em uma tela só de cada vez).
class TourKeys {
  static final startCard = GlobalKey(debugLabel: 'tour_start_card');
  static final hubAgenda = GlobalKey(debugLabel: 'tour_hub_agenda');
  static final hubOpenSlots = GlobalKey(debugLabel: 'tour_hub_open_slots');
  static final hubStudents = GlobalKey(debugLabel: 'tour_hub_students');
  static final agendaFab = GlobalKey(debugLabel: 'tour_agenda_fab');
  static final agendaPause = GlobalKey(debugLabel: 'tour_agenda_pause');
}

/// Roda o tutorial. Devolve true se chegou ao fim e false se a pessoa pulou ou nenhum passo cabia na tela.
Future<bool> runTour(BuildContext context, List<TourStep> steps) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null || steps.isEmpty) return Future.value(false);
  final done = Completer<bool>();
  late OverlayEntry entry;
  void finish(bool completed) {
    if (entry.mounted) entry.remove();
    if (!done.isCompleted) done.complete(completed);
  }

  entry = OverlayEntry(builder: (_) => _TourOverlay(steps: steps, onFinish: finish));
  overlay.insert(entry);
  return done.future;
}

class _TourOverlay extends StatefulWidget {
  final List<TourStep> steps;
  final void Function(bool completed) onFinish;
  const _TourOverlay({required this.steps, required this.onFinish});

  @override
  State<_TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<_TourOverlay> {
  int index = -1; // passo atual (-1 = ainda procurando o primeiro que cabe)
  int shown = 0;
  Rect? rect;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _goTo(0));
  }

  /// Vai para o passo [i] (ou o próximo que estiver na tela); acaba se não há mais.
  Future<void> _goTo(int i) async {
    if (_busy) return;
    _busy = true;
    try {
      var k = i;
      while (k < widget.steps.length) {
        final ctx = widget.steps[k].target.currentContext;
        if (ctx != null && ctx.mounted) {
          try {
            await Scrollable.ensureVisible(ctx, alignment: 0.35, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
          } catch (_) {/* sem rolagem: segue */}
          await Future<void>.delayed(const Duration(milliseconds: 60));
          final r = _measure(widget.steps[k].target);
          if (r != null && mounted) {
            setState(() {
              index = k;
              rect = r;
              shown++;
            });
            return;
          }
        }
        k++;
      }
      widget.onFinish(shown > 0);
    } finally {
      _busy = false;
    }
  }

  Rect? _measure(GlobalKey key) {
    final ctx = key.currentContext;
    final box = ctx?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final p = box.localToGlobal(Offset.zero);
    return p & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final r = rect;
    if (index < 0 || r == null) return const SizedBox.shrink();
    final step = widget.steps[index];
    final size = MediaQuery.of(context).size;
    final pad = MediaQuery.of(context).padding;
    const cardH = 190.0;
    final below = r.bottom + 14 + cardH < size.height - pad.bottom;
    final last = index >= widget.steps.length - 1;
    final card = Material(
      color: AppColors.surface,
      elevation: 8,
      borderRadius: BorderRadius.circular(Ds.radiusCard),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Ds.s16, Ds.s16, Ds.s16, Ds.s8),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(step.title, style: Ds.title().copyWith(fontSize: 18)),
          const SizedBox(height: Ds.s8),
          Text(step.text, style: const TextStyle(fontSize: 15, height: 1.35)),
          const SizedBox(height: Ds.s8),
          Row(children: [
            Text(tr('{0} de {1}', [index + 1, widget.steps.length]), style: Ds.support()),
            const Spacer(),
            TextButton(onPressed: () => widget.onFinish(false), child: Text(tr('Pular'))),
            const SizedBox(width: Ds.s4),
            FilledButton(onPressed: () => last ? widget.onFinish(true) : _goTo(index + 1), child: Text(last ? tr('Entendi') : tr('Próximo'))),
          ]),
        ]),
      ),
    );
    return Stack(children: [
      // O fundo escuro "come" os toques: o tutorial não deixa apertar o que está atrás sem querer.
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: TweenAnimationBuilder<Rect?>(
            tween: RectTween(begin: r, end: r),
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            builder: (c, hole, _) => CustomPaint(painter: _HolePainter(hole ?? r, AppColors.accent)),
          ),
        ),
      ),
      Positioned(
        left: Ds.screenPad,
        right: Ds.screenPad,
        top: below ? r.bottom + 14 : null,
        bottom: below ? null : size.height - r.top + 14,
        child: TweenAnimationBuilder<double>(
          key: ValueKey(index),
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          builder: (c, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, (below ? 12 : -12) * (1 - t)), child: child)),
          child: card,
        ),
      ),
    ]);
  }
}

class _HolePainter extends CustomPainter {
  final Rect hole;
  final Color ring;
  _HolePainter(this.hole, this.ring);

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(hole.inflate(6), const Radius.circular(14));
    // Camada própria: pinta o fundo escuro e "apaga" o buraco, para o botão aparecer inteiro e brilhante.
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black.withValues(alpha: 0.74));
    canvas.drawRRect(r, Paint()..blendMode = BlendMode.clear);
    canvas.restore();
    canvas.drawRRect(r, Paint()..color = ring..style = PaintingStyle.stroke..strokeWidth = 2.5);
  }

  @override
  bool shouldRepaint(_HolePainter old) => old.hole != hole || old.ring != ring;
}
