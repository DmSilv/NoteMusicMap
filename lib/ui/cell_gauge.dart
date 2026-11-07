import 'dart:math' as math;

import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'theme.dart';

/// Camada "viva" de um quadrado da grade: o quadrado da nota que está tocando
/// agora vira um pequeno AFINADOR HORIZONTAL.
///
/// O desenho (inspirado no cursor do Tonemap): o fundo do quadrado fica escuro;
/// uma faixa central escura é a zona "afinada"; dos dois lados, faixas na cor
/// viva (azul = grave, verde = afinado, laranja = agudo) e uma linha vertical
/// clara que desliza para a esquerda (grave) ou para a direita (aguda). Quando
/// a linha entra na zona do meio, ela fica verde e a zona acende ("travou").
///
/// Como a animação fica fluida:
///  - a linha é uma mola amortecida ([NeedleSpring]) calculada a cada quadro da
///    tela (60 fps ou mais), então se move lisa mesmo que o microfone entregue
///    só ~30 leituras por segundo;
///  - a cor das faixas é calculada da posição JÁ suavizada da linha e ainda
///    passa por um leve "escorregar", então nunca dá salto de cor;
///  - a camada aparece e some com fade; ao trocar de nota, a linha nasce direto
///    na posição certa (não varre a escala a partir do centro);
///  - o relógio só roda enquanto há movimento e fica numa camada própria
///    (RepaintBoundary): redesenhar a linha não redesenha a grade inteira.
class LiveCellLayer extends StatefulWidget {
  /// Desvio ao vivo (cents) se este é o quadrado da nota que toca; senão null.
  final double? cents;

  /// Meia-largura da faixa "afinada" (cents).
  final double zone;

  /// Raio dos cantos (para casar com o quadrado).
  final double radius;

  /// true quando NENHUMA nota está em destaque (silêncio): a camada apaga mais
  /// devagar. Se outra nota assumiu, apaga mais rápido para dar lugar a ela.
  final bool silent;

  /// Conteúdo que acompanha a camada (ex.: o nome da nota, desenhado POR CIMA
  /// da linha, como no Tonemap). Recebe o quanto o quadrado está "vivo" (0..1)
  /// e a cor do texto sobre o fundo escuro.
  final Widget Function(BuildContext context, double live, Color ink)? builder;

  const LiveCellLayer({
    super.key,
    required this.cents,
    required this.zone,
    required this.radius,
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
  Color fill = const Color(0x00000000); // cor viva das faixas laterais
}

class _LiveCellLayerState extends State<LiveCellLayer> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  // Um pouco de "vida" na linha: ultrapassa o alvo menos de 2%, como um
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
      _v.fill = Color.lerp(_v.fill, _fillFor(_spring.pos), kc)!;
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
        // Camada própria: a linha redesenha a 60 fps sem redesenhar a grade.
        RepaintBoundary(
          child: CustomPaint(
            painter: _LivePainter(_v, zone: widget.zone, radius: widget.radius, repaint: _repaint),
          ),
        ),
        // O nome fica por cima da linha.
        if (widget.builder != null)
          ListenableBuilder(
            listenable: _repaint,
            builder: (context, _) => widget.builder!(context, _v.alpha, Colors.white),
          ),
      ],
    );
  }
}

class _LivePainter extends CustomPainter {
  final _LiveValue v;
  final double zone;
  final double radius;

  /// Desvio (cents) em que a linha encosta na borda do quadrado.
  static const double _range = 35;

  /// Campo escuro do quadrado vivo (igual nos dois temas, como no Tonemap).
  static const Color _field = Color(0xFF05090D);

  _LivePainter(this.v, {required this.zone, required this.radius, required Listenable repaint})
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
    // Unidade de escala dos traços: quadrados maiores têm linha mais grossa.
    final u = (math.min(w, h * 1.25) / 38).clamp(0.72, 1.7).toDouble();

    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));

    // 1) Campo escuro.
    canvas.drawRect(rect, Paint()..color = _field.withValues(alpha: a));

    // Posição horizontal para um desvio em cents. A curva é esticada perto do
    // centro (expoente < 1): poucos cents já mexem a linha de forma visível.
    final half = w / 2;
    double xOf(double cents) {
      final m = math.pow(math.min(1.0, cents.abs() / _range), 0.75).toDouble();
      return half + (cents < 0 ? -m : m) * half * 0.9;
    }

    final zl = xOf(-zone), zr = xOf(zone);
    // "Travou": 1 dentro da zona afinada, cai suavemente fora dela.
    final lock = 1 - _smooth((v.pos.abs() - zone * 0.7) / (zone * 0.9 + 0.001));

    // 2) Faixas laterais na cor viva (fora da zona) e zona do meio, que acende
    //    em verde quando a linha trava.
    final side = Paint()..color = v.fill.withValues(alpha: 0.92 * a);
    canvas.drawRect(Rect.fromLTRB(0, 0, zl, h), side);
    canvas.drawRect(Rect.fromLTRB(zr, 0, w, h), side);
    if (lock > 0.01) {
      canvas.drawRect(Rect.fromLTRB(zl, 0, zr, h),
          Paint()..color = AppColors.inTune.withValues(alpha: 0.30 * lock * a));
    }
    // Divisórias finas da zona.
    final edge = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.30 * a)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(zl, 0), Offset(zl, h), edge);
    canvas.drawLine(Offset(zr, 0), Offset(zr, h), edge);

    // 3) A linha: clara, de ponta a ponta, com contorno escuro (aparece sobre
    //    qualquer faixa) e verde-menta quando trava. Cresce um pouco ao aparecer.
    final nx = xOf(v.pos);
    final nw = 3.2 * u;
    final pad = 2.5 * u * (1.6 - 0.6 * a);
    final lineColor = Color.lerp(const Color(0xFFFFFFFF), AppColors.inTuneBright, lock)!;
    final bar = RRect.fromLTRBR(nx - nw / 2, pad, nx + nw / 2, h - pad, Radius.circular(nw / 2));
    canvas.drawRRect(
        bar.inflate(1.4 * u), Paint()..color = const Color(0xFF000000).withValues(alpha: 0.55 * a));
    canvas.drawRRect(bar, Paint()..color = lineColor.withValues(alpha: a));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LivePainter old) => old.zone != zone || old.radius != radius;
}
