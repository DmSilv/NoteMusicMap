import 'dart:math' as math;

import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'theme.dart';

/// Camada "viva" de um quadrado da grade: o quadrado da nota que está tocando
/// agora ganha um CURSOR em forma de ponteiro de relógio de afinador, que se
/// mexe com a afinação, e a cor do quadrado acompanha o ponteiro (azul = grave,
/// verde no centro = afinado, laranja = agudo).
///
/// O desenho: fundo com degradê suave e brilho interno (destaque leve), um
/// arco de escala com a zona "afinada" e marcas, um ponteiro afilado com
/// sombra e um eixo central. Quando o ponteiro entra na zona afinada, a marca
/// do centro e a zona acendem e um anel aparece em volta do eixo ("travou").
///
/// Como a animação fica fluida:
///  - o ponteiro é uma mola amortecida ([NeedleSpring]) calculada a cada quadro
///    da tela (60 fps ou mais), então se move liso mesmo que o microfone entregue
///    só ~30 leituras por segundo;
///  - a cor é calculada da posição JÁ suavizada do ponteiro e ainda passa por um
///    leve "escorregar", então nunca dá salto de cor;
///  - a camada aparece e some com fade (e o ponteiro "cresce" ao aparecer); ao
///    trocar de nota, o ponteiro nasce direto na posição certa (não varre a
///    escala a partir do centro);
///  - o relógio só roda enquanto há movimento e fica numa camada própria
///    (RepaintBoundary): redesenhar o ponteiro não redesenha a grade inteira.
class LiveCellLayer extends StatefulWidget {
  /// Desvio ao vivo (cents) se este é o quadrado da nota que toca; senão null.
  final double? cents;

  /// Meia-largura da faixa "afinada" (cents), para a marca da zona.
  final double zone;

  /// Raio dos cantos (para casar com o quadrado).
  final double radius;

  /// Quadrados grandes mostram também o arco com a zona e as marcas.
  final bool detailed;

  /// Altura (px) reservada no topo para o nome da nota; o mostrador usa o resto.
  final double labelBand;

  /// Largura (px) reservada à esquerda para o nome da nota (quadrados largos:
  /// o nome fica ao lado e o mostrador usa o resto).
  final double labelLeft;

  /// true quando NENHUMA nota está em destaque (silêncio): a camada apaga mais
  /// devagar. Se outra nota assumiu, apaga mais rápido para dar lugar a ela.
  final bool silent;

  /// Conteúdo que acompanha a cor viva (ex.: o nome da nota). Recebe o quanto o
  /// quadrado está "vivo" (0..1) e a cor de tinta legível sobre o fundo atual.
  final Widget Function(BuildContext context, double live, Color ink)? builder;

  const LiveCellLayer({
    super.key,
    required this.cents,
    required this.zone,
    required this.radius,
    this.detailed = false,
    this.labelBand = 0,
    this.labelLeft = 0,
    this.silent = false,
    this.builder,
  });

  @override
  State<LiveCellLayer> createState() => _LiveCellLayerState();
}

/// Estado visual compartilhado entre o relógio e o pincel.
class _LiveValue {
  double alpha = 0; // 0 = invisível, 1 = totalmente "vivo"
  double pos = 0; // cents, já suavizado pela mola
  Color fill = const Color(0x00000000);
  Color ink = AppColors.onCell;
}

class _LiveCellLayerState extends State<LiveCellLayer> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  // Um pouco de "vida" no ponteiro: ultrapassa o alvo menos de 2%, como um
  // ponteiro analógico de verdade, mas assenta em ~0,25 s.
  final NeedleSpring _spring = NeedleSpring(omega: 21, zeta: 0.8);
  final _LiveValue _v = _LiveValue();
  final ValueNotifier<int> _repaint = ValueNotifier(0);
  Duration _last = Duration.zero;
  double _target = 0;

  // Constantes de tempo (s): menor = mais rápido.
  // (A espera antes de apagar já é feita pelo filtro de nota em destaque.)
  static const double _tauIn = 0.10; // aparecer
  static const double _tauOut = 0.24; // sumir no silêncio (devagar, suave)
  static const double _tauHandoff = 0.16; // sumir quando outra nota assumiu
  static const double _tauColor = 0.065; // cor "escorrega" até o alvo

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    final c = widget.cents;
    if (c != null) {
      _target = c.clamp(-60.0, 60.0);
      _spring.snap(_target);
      _v.pos = _target;
      _v.fill = _fillFor(_target);
      _v.ink = readableOn(_v.fill);
      _wake();
    }
  }

  Color _fillFor(double cents) => intonationColor(cents, widget.zone);

  void _wake() {
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(LiveCellLayer old) {
    super.didUpdateWidget(old);
    final c = widget.cents;
    if (c != null) {
      _target = c.clamp(-60.0, 60.0);
      _wake();
    } else if (old.cents != null || _v.alpha > 0.004) {
      _wake(); // precisa apagar com fade
    }
    if (old.zone != widget.zone && _v.alpha > 0.004) _wake();
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;

    final present = widget.cents != null;

    if (present) {
      // Nasce já na posição certa (sem varrer a escala a partir do centro).
      if (_v.alpha < 0.03) {
        _spring.snap(_target);
        _v.fill = _fillFor(_target);
      }
      _spring.step(dt, _target);
    }

    final tau = present ? _tauIn : (widget.silent ? _tauOut : _tauHandoff);
    _v.alpha += ((present ? 1.0 : 0.0) - _v.alpha) * (1 - math.exp(-dt / tau));
    _v.pos = _spring.pos;

    if (_v.alpha > 0.004) {
      final kc = 1 - math.exp(-dt / _tauColor);
      final goal = _fillFor(_spring.pos);
      _v.fill = Color.lerp(_v.fill, goal, kc)!;
      _v.ink = Color.lerp(_v.ink, readableOn(_v.fill), kc)!;
    }
    _repaint.value++;

    final settled = present
        ? (_spring.isSettled(_target) && (1 - _v.alpha) < 0.004)
        : _v.alpha < 0.004;
    if (settled) {
      if (present) {
        _v.alpha = 1;
        _v.pos = _target;
        _v.fill = _fillFor(_target);
        _v.ink = readableOn(_v.fill);
      } else {
        _v.alpha = 0;
      }
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
    return Stack(
      fit: StackFit.expand,
      children: [
        // Camada própria: o ponteiro redesenha a 60 fps sem redesenhar a grade.
        RepaintBoundary(
          child: CustomPaint(
            painter: _LivePainter(
              _v,
              zone: widget.zone,
              radius: widget.radius,
              detailed: widget.detailed,
              labelBand: widget.labelBand,
              labelLeft: widget.labelLeft,
              repaint: _repaint,
            ),
          ),
        ),
        if (widget.builder != null)
          ListenableBuilder(
            listenable: _repaint,
            builder: (context, _) => widget.builder!(context, _v.alpha, _v.ink),
          ),
      ],
    );
  }
}

class _LivePainter extends CustomPainter {
  final _LiveValue v;
  final double zone;
  final double radius;
  final bool detailed;
  final double labelBand;
  final double labelLeft;

  _LivePainter(this.v,
      {required this.zone,
      required this.radius,
      required this.detailed,
      required this.labelBand,
      required this.labelLeft,
      required Listenable repaint})
      : super(repaint: repaint);

  static double _smooth(double x) {
    final t = x.clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final a = v.alpha.clamp(0.0, 1.0);
    if (a < 0.008) return;
    final w = size.width, h = size.height;
    if (w < 6 || h < 6) return;
    final big = detailed && w >= 44 && h >= 38;
    // Unidade de escala dos traços: quadrados maiores têm desenho mais encorpado.
    final u = (math.min(w, h * 1.25) / 38).clamp(0.72, 1.7).toDouble();

    // 1) Fundo vivo: a cor segue o ponteiro, com um degradê leve (mais claro em
    //    cima) que dá volume sem mudar a cor lida.
    final rect = Offset.zero & size;
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final hsl = HSLColor.fromColor(v.fill);
    Color shade(double dl) =>
        hsl.withLightness((hsl.lightness + dl).clamp(0.0, 1.0)).toColor().withValues(alpha: a);
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [shade(0.07), shade(-0.05)],
        ).createShader(rect),
    );

    // 1b) Destaque leve: um brilho suave que corre por dentro do contorno,
    //     para achar de relance qual quadrado está tocando (sem brilho para
    //     fora: os vizinhos cobririam).
    canvas.save();
    canvas.clipRRect(rr);
    canvas.drawRRect(
      rr.deflate(0.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = big ? 6 : 4
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.30 * a)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, big ? 4 : 3),
    );
    canvas.restore();

    // 2) Geometria do mostrador: pivô embaixo, no centro da área livre; o
    //    ponteiro nunca passa das bordas nem do espaço do nome da nota.
    final maxDeg = big ? 56.0 : 42.0;
    final maxRad = maxDeg * math.pi / 180;
    final bottomPad = big ? math.max(4.5, h * 0.10) : math.max(3.6, h * 0.12);
    final areaW = w - labelLeft;
    final pivot = Offset(labelLeft + areaW / 2, h - bottomPad);
    final roomV = pivot.dy - labelBand - (big ? 11 : 7);
    final roomH = (areaW / 2 - (big ? 7 : 4)) / math.sin(maxRad);
    // O ponteiro "cresce" ao aparecer (e encolhe ao sumir).
    final len = math.max(5.0, math.min(roomV, roomH)) * (0.9 + 0.1 * a);

    final ink = v.ink;
    Paint line(double width, double alpha, {StrokeCap cap = StrokeCap.round}) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = cap
      ..strokeWidth = width
      ..color = ink.withValues(alpha: (alpha * a).clamp(0.0, 1.0));

    double rad(double cents) => needleAngleDeg(cents, maxDeg: maxDeg) * math.pi / 180;
    Offset at(double angle, double r) =>
        pivot + Offset(math.sin(angle) * r, -math.cos(angle) * r);

    // "Travou": 1 dentro da zona afinada, cai suavemente fora dela.
    final lock = 1 - _smooth((v.pos.abs() - zone * 0.7) / (zone * 0.9 + 0.001));

    // 3) Escala: arco de fundo, zona "afinada" e marcas (a zona e as marcas só
    //    nos quadrados grandes).
    final r = len + (big ? 4.5 : 3.0);
    final dial = Rect.fromCircle(center: pivot, radius: r);
    canvas.drawArc(
        dial, -math.pi / 2 - maxRad, 2 * maxRad, false, line(big ? 1.3 : 1.0, big ? 0.35 : 0.28));
    if (big) {
      final z0 = rad(-zone), z1 = rad(zone);
      canvas.drawArc(dial, -math.pi / 2 + z0, z1 - z0, false,
          line(3.4 * u, 0.42 + 0.5 * lock, cap: StrokeCap.butt));
      for (final c in const [-50.0, -25.0, 25.0, 50.0]) {
        canvas.drawLine(at(rad(c), r + 0.8 * u), at(rad(c), r + 4.2 * u), line(1.2, 0.5));
      }
    }
    // Marca do centro: um triângulo apontando para o eixo, onde o ponteiro
    // deve parar. Acende (fica mais forte) quando o ponteiro trava na zona.
    {
      final apex = at(0, r + 0.6 * u);
      final mark = Path()
        ..moveTo(apex.dx, apex.dy)
        ..lineTo(apex.dx - 3.0 * u, apex.dy - 4.6 * u)
        ..lineTo(apex.dx + 3.0 * u, apex.dy - 4.6 * u)
        ..close();
      canvas.drawPath(
          mark, Paint()..color = ink.withValues(alpha: ((0.55 + 0.45 * lock) * a).clamp(0.0, 1.0)));
    }

    // 4) Ponteiro afilado (largo no eixo, fino na ponta) com sombra suave.
    final ang = rad(v.pos);
    final tip = at(ang, len);
    final perp = Offset(math.cos(ang), math.sin(ang));
    final half = (big ? 2.5 : 2.0) * u;
    final needle = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(pivot.dx + perp.dx * half, pivot.dy + perp.dy * half)
      ..lineTo(pivot.dx - perp.dx * half, pivot.dy - perp.dy * half)
      ..close();
    canvas.drawPath(
      needle.shift(Offset(0.7 * u, 1.1 * u)),
      Paint()
        ..color = const Color(0xFF000000).withValues(alpha: 0.24 * a)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.2 * u),
    );
    final inkPaint = Paint()..color = ink.withValues(alpha: a);
    // Contorno na cor OPOSTA à tinta: garante contraste do ponteiro em qualquer
    // tom do fundo (inclusive nos tons médios, onde claro e escuro empatam).
    final halo = ink.computeLuminance() > 0.4 ? const Color(0xFF0B1116) : const Color(0xFFFFFFFF);
    canvas.drawPath(
        needle,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 2.6 * u
          ..color = halo.withValues(alpha: 0.55 * a));
    canvas.drawPath(needle, inkPaint);
    // Contorno fino arredonda a ponta e os cantos do ponteiro.
    canvas.drawPath(
        needle,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 1.1 * u
          ..color = ink.withValues(alpha: a));

    // 5) Eixo: disco com um furo na cor do fundo e, ao travar, um anel em volta.
    final hub = (big ? 4.0 : 3.0) * u;
    canvas.drawCircle(pivot, hub + 0.9 * u, Paint()..color = halo.withValues(alpha: 0.55 * a));
    canvas.drawCircle(pivot, hub, inkPaint);
    canvas.drawCircle(pivot, hub * 0.42, Paint()..color = v.fill.withValues(alpha: a));
    if (lock > 0.02) {
      canvas.drawCircle(
        pivot,
        hub + 2.6 * u,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 * u
          ..color = ink.withValues(alpha: (0.7 * lock * a).clamp(0.0, 1.0)),
      );
    }
  }

  @override
  bool shouldRepaint(_LivePainter old) =>
      old.zone != zone ||
      old.radius != radius ||
      old.detailed != detailed ||
      old.labelBand != labelBand ||
      old.labelLeft != labelLeft;
}
