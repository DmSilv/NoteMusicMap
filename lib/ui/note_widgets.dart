
import 'dart:math' as math;

import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'smooth_color.dart';
import 'theme.dart';

/// Nome de nota com o acidente (♯/♭) elevado e a oitava pequena embaixo,
/// alinhados à linha de base: "Sol" + ♯ + 4. Largura sempre previsível.
class NoteLabel extends StatelessWidget {
  /// Ex.: 'Sol♯' ou 'Dó'.
  final String name;
  final int? octave;
  final double size;
  final Color color;
  final FontWeight weight;

  const NoteLabel({
    super.key,
    required this.name,
    this.octave,
    required this.size,
    required this.color,
    this.weight = FontWeight.w800,
  });

  /// Cria a partir de um número MIDI e da configuração de afinação.
  factory NoteLabel.midi(
    int midi,
    TuningConfig cfg, {
    Key? key,
    bool withOctave = true,
    required double size,
    required Color color,
    FontWeight weight = FontWeight.w800,
  }) {
    final shown = midi + cfg.transpose;
    return NoteLabel(
      key: key,
      name: noteName(midi, cfg),
      octave: withOctave ? (shown ~/ 12) - 1 : null,
      size: size,
      color: color,
      weight: weight,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasAcc = name.endsWith('♯') || name.endsWith('♭');
    final base = hasAcc ? name.substring(0, name.length - 1) : name;
    final acc = hasAcc ? name.substring(name.length - 1) : null;
    TextStyle st(double s, {FontWeight? w, Color? c}) => TextStyle(
        fontSize: s, fontWeight: w ?? weight, color: c ?? color, height: 1.0);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(base, style: st(size)),
        if (acc != null)
          Padding(
            padding: EdgeInsets.only(left: size * 0.03),
            child: Transform.translate(
              offset: Offset(0, -size * 0.30),
              child: Text(acc, style: st(size * 0.64)),
            ),
          ),
        if (octave != null)
          Padding(
            padding: EdgeInsets.only(left: size * 0.05),
            child: Transform.translate(
              offset: Offset(0, size * 0.10),
              child: Text('$octave', style: st(size * 0.46, w: FontWeight.w700, c: color.withValues(alpha: 0.8))),
            ),
          ),
      ],
    );
  }
}

/// Desvio em cents: símbolo ♯/♭ + número, alinhados. O número "rola" até o
/// novo valor em vez de saltar.
class CentsLabel extends StatelessWidget {
  final double? cents;
  final double size;
  final Color color;
  const CentsLabel({super.key, required this.cents, required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    final target = cents;
    final r = target?.round() ?? 0;
    final symbol = target == null ? '' : (r > 0 ? '♯' : (r < 0 ? '♭' : ''));
    return TweenAnimationBuilder<double>(
      tween: Tween(end: (target ?? 0).abs()),
      duration: const Duration(milliseconds: 170),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) {
        if (target == null) return SizedBox(height: size);
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            if (symbol.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(right: size * 0.06),
                child: Text(symbol,
                    style: TextStyle(
                        fontSize: size * 0.9,
                        fontWeight: FontWeight.w800,
                        color: color,
                        height: 1.0)),
              ),
            Text(v.round().toString(),
                style: TextStyle(
                    fontSize: size,
                    fontWeight: FontWeight.w800,
                    color: color,
                    height: 1.0,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        );
      },
    );
  }
}

/// Leitura da nota atual com troca FLUIDA.
///
/// Cada nota é uma camada: ao trocar, a antiga sobe (ou desce, conforme a nota
/// nova seja mais aguda ou mais grave) e esmaece, enquanto a nova entra do lado
/// oposto, com um pequeno atraso e uma curva suave. Se a nota trocar de novo no
/// meio da transição, as camadas se empilham sem salto (no máximo 3).
/// A cor segue o desvio quadro a quadro (sem reiniciar animações a cada leitura)
/// e a área ocupada nunca muda de tamanho.
class NoteReadout extends StatefulWidget {
  final TrackedNote? note;
  final TuningConfig cfg;
  final double zone;
  final double size;
  final bool withOctave;
  const NoteReadout({
    super.key,
    required this.note,
    required this.cfg,
    required this.zone,
    this.size = 40,
    this.withOctave = true,
  });

  @override
  State<NoteReadout> createState() => _NoteReadoutState();
}

/// Uma nota na tela (ou saindo dela).
class _ReadoutLayer {
  _ReadoutLayer(this.midi, this.dir, {this.enter = 0});

  /// Nota (null = traço, sem nota).
  final int? midi;

  /// +1: entra por baixo e a antiga sai por cima (nota mais aguda); -1: o contrário.
  final int dir;

  /// Progresso da entrada: valores negativos são o atraso inicial; 1 = parada.
  double enter;

  /// Progresso da saída (0 = ainda aqui, 1 = sumiu).
  double exit = 0;
  bool leaving = false;
  int leaveDir = 1;
}

class _NoteReadoutState extends State<NoteReadout> with SingleTickerProviderStateMixin {
  // Tempos (s)
  static const double _enterDur = 0.32;
  static const double _enterDelay = 0.07;
  static const double _exitDur = 0.20;
  static const double _tauColor = 0.09;
  static const int _maxLayers = 3;

  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<int> _repaint = ValueNotifier(0);
  final List<_ReadoutLayer> _layers = [];
  Duration _last = Duration.zero;
  late Color _color;
  late Color _target;

  Color _targetFor(TrackedNote? n) =>
      n == null ? AppColors.textDim : intonationColor(n.cents, widget.zone);

  @override
  void initState() {
    super.initState();
    _target = _targetFor(widget.note);
    _color = _target;
    _layers.add(_ReadoutLayer(widget.note?.midi, 1, enter: 1));
  }

  @override
  void didUpdateWidget(NoteReadout old) {
    super.didUpdateWidget(old);
    final midi = widget.note?.midi;
    final cur = _layers.last;
    if (midi != cur.midi) {
      // Sobe quando a nota nova é mais aguda, desce quando é mais grave.
      final dir = (midi != null && cur.midi != null && midi < cur.midi!) ? -1 : 1;
      cur
        ..leaving = true
        ..leaveDir = dir;
      _layers.add(_ReadoutLayer(midi, dir, enter: -_enterDelay / _enterDur));
      while (_layers.length > _maxLayers) {
        _layers.removeAt(0);
      }
      _wake();
    }
    _target = _targetFor(widget.note);
    if (!colorsClose(_color, _target)) _wake();
  }

  void _wake() {
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    var busy = false;
    for (final l in _layers) {
      if (l.enter < 1) {
        l.enter = math.min(1.0, l.enter + dt / _enterDur);
        busy = busy || l.enter < 1;
      }
      if (l.leaving && l.exit < 1) {
        l.exit = math.min(1.0, l.exit + dt / _exitDur);
        busy = busy || l.exit < 1;
      }
    }
    _layers.removeWhere((l) => l.leaving && l.exit >= 1);

    _color = Color.lerp(_color, _target, 1 - math.exp(-dt / _tauColor))!;
    if (colorsClose(_color, _target)) {
      _color = _target;
    } else {
      busy = true;
    }
    _repaint.value++;
    if (!busy) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  Widget _layer(_ReadoutLayer l) {
    final size = widget.size;
    final enter = l.enter.clamp(0.0, 1.0);
    final exit = l.exit.clamp(0.0, 1.0);
    final e = Curves.easeOutCubic.transform(enter); // posição/escala de quem entra
    final x = Curves.easeIn.transform(exit); // movimento de quem sai
    // A antiga some depressa e a nova aparece devagar, para as duas quase não
    // se sobreporem (nada de "um nome em cima do outro").
    final opacity =
        (Curves.easeInOut.transform(enter) * (1 - Curves.easeOutCubic.transform(exit))).clamp(0.0, 1.0);
    // Deslocamento vertical (px): entra vindo de `dir`, sai para o lado oposto.
    final dy = l.dir * (1 - e) * size * 0.34 - l.leaveDir * x * size * 0.34;
    final scale = (0.90 + 0.10 * e) * (1 - 0.06 * x);
    final Widget label = l.midi == null
        ? Text('–',
            style: TextStyle(
                fontSize: widget.size, fontWeight: FontWeight.w800, color: _color, height: 1.0))
        : NoteLabel.midi(l.midi!, widget.cfg,
            size: widget.size, color: _color, withOctave: widget.withOctave);
    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(0, dy),
        child: Transform.scale(scale: scale, alignment: Alignment.centerLeft, child: label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _repaint,
      builder: (context, _) => Stack(
        alignment: Alignment.centerLeft,
        clipBehavior: Clip.none,
        children: [for (final l in _layers) _layer(l)],
      ),
    );
  }
}
