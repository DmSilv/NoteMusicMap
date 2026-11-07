import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Medidor de fluidez, SÓ para builds de desenvolvimento (kDevDemo).
///
/// Enquanto a simulação roda, mede a cada quadro:
///  - o INTERVALO entre quadros (quanto tempo a tela leva para ser atualizada);
///  - o CUSTO do quadro: do começo do quadro (animações) até o fim do desenho,
///    que na web inclui montar a árvore, medir, pintar e rasterizar.
/// E escreve um resumo a cada [every] segundos no console:
///   [frames] 5.0s: 298 quadros (59.6 fps) | intervalo médio 16.8 ms, p95 17.9, máx 24.3 | custo médio 3.1 ms, p95 5.2, máx 9.8 | >25 ms: 0
/// Bom resultado: custo bem abaixo do intervalo do quadro (16,7 ms a 60 Hz) e
/// nenhum quadro lento. O intervalo depende da tela; o custo, do app.
class FrameMeter {
  FrameMeter._();
  static final FrameMeter instance = FrameMeter._();

  bool _on = false;
  bool _hooked = false;
  Duration? _last;
  final Stopwatch _sw = Stopwatch()..start();
  int _t0 = -1;
  final List<double> _dts = [];
  final List<double> _costs = [];
  double _since = 0;
  static const double every = 5.0;

  /// Última medição (para testes e para ler no console do navegador).
  String? lastSummary;

  void start() {
    if (_on) return;
    _on = true;
    _last = null;
    _t0 = -1;
    _dts.clear();
    _costs.clear();
    _since = 0;
    if (!_hooked) {
      _hooked = true;
      // Roda depois de montar, medir e pintar o quadro.
      SchedulerBinding.instance.addPersistentFrameCallback(_after);
    }
    SchedulerBinding.instance.scheduleFrameCallback(_tick);
    debugPrint('[frames] medindo fluidez…');
  }

  void stop() {
    if (!_on) return;
    _on = false;
    _report();
  }

  void _tick(Duration ts) {
    if (!_on) return;
    _t0 = _sw.elapsedMicroseconds;
    final last = _last;
    if (last != null) {
      final ms = (ts - last).inMicroseconds / 1000.0;
      _dts.add(ms);
      _since += ms / 1000.0;
      if (_since >= every) _report();
    }
    _last = ts;
    SchedulerBinding.instance.scheduleFrameCallback(_tick);
  }

  void _after(Duration ts) {
    if (!_on || _t0 < 0) return;
    _costs.add((_sw.elapsedMicroseconds - _t0) / 1000.0);
    _t0 = -1;
  }

  static String _stats(List<double> v) {
    final s = [...v]..sort();
    final n = s.length;
    final avg = s.fold<double>(0, (a, b) => a + b) / n;
    final p95 = s[math.min(n - 1, (n * 0.95).floor())];
    return 'médio ${avg.toStringAsFixed(1)} ms, p95 ${p95.toStringAsFixed(1)}, máx ${s.last.toStringAsFixed(1)}';
  }

  void _report() {
    if (_dts.isEmpty) return;
    final n = _dts.length;
    final total = _dts.fold<double>(0, (a, b) => a + b);
    final slow = _dts.where((d) => d > 25).length;
    final fps = n / (total / 1000);
    final cost = _costs.isEmpty ? '' : ' | custo ${_stats(_costs)}';
    lastSummary = '[frames] ${(total / 1000).toStringAsFixed(1)}s: $n quadros '
        '(${fps.toStringAsFixed(1)} fps) | intervalo ${_stats(_dts)}$cost | >25 ms: $slow';
    debugPrint(lastSummary);
    _dts.clear();
    _costs.clear();
    _since = 0;
  }
}
