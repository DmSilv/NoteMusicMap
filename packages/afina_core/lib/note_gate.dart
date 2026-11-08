/// Porta de registro da sessão: só vira nota da grade (cor, ×N, placar) o que se
/// mantém por um tempo mínimo.
///
/// Corta o que o músico não tocou de verdade: a passagem entre duas notas (de Lá
/// para Si o dedo cruza o Lá♯), ruído do arco e cordas soltas que ressoam por
/// simpatia. Uma nota nova só é "confirmada" depois de [minSeconds]; quando é, o
/// que ficou guardado nesse tempo entra de uma vez na grade (nada se perde).
library;

import 'dart:math' as math;

import 'pitch_grid.dart';

/// Uma nota ouvida: quanto durou e se entrou na sessão.
class NoteRun {
  final int midi;
  final double seconds;
  final double clarity;

  /// false = durou pouco demais e foi descartada (provável passagem ou ruído).
  final bool kept;
  const NoteRun(this.midi, this.seconds, this.clarity, this.kept);
}

/// Nota já encerrada, guardada um instante para reconhecer trinados.
class _Closed {
  final int midi;
  final double start;
  final double last;
  bool kept;
  final List<(double cents, double clarity, double dt, double at)> frames;
  NoteRun run;
  _Closed(this.midi, this.start, this.last, this.kept, this.frames, this.run);
}

class NoteGate {
  /// Tempo (s) que uma nota precisa durar para entrar na sessão.
  double minSeconds;

  /// Quanto tempo (s) sem som (falha curta) ainda conta como a mesma nota.
  final double dropout;

  /// Durante um trinado (A, B, A, B rápidos) bastam notas desta duração (s).
  final double trillMinSeconds;

  /// Janela (s) em que 4 notas alternadas formam um trinado, e quanto o modo
  /// trinado continua valendo depois da última (s).
  final double trillSpan;
  final double trillHold;

  /// Últimas notas ouvidas (mais recente primeiro).
  final List<NoteRun> runs = [];
  final int keepRuns;

  int? _midi;
  double _start = 0;
  double _last = 0;
  bool _open = false;
  double _claritySum = 0;
  int _frames = 0;
  final List<(double cents, double clarity, double dt, double at)> _pending = [];

  NoteGate({
    this.minSeconds = 0.06,
    this.dropout = 0.15,
    this.keepRuns = 10,
    this.trillMinSeconds = 0.03,
    this.trillSpan = 1.0,
    this.trillHold = 0.6,
  });

  PitchGrid? _grid;
  final List<_Closed> _closed = [];
  double _trillUntil = double.negativeInfinity;

  /// true enquanto um trinado está sendo tocado.
  bool trilling(double now) => now < _trillUntil;

  /// Nota que está sendo avaliada agora (ou null).
  int? get midi => _midi;

  /// Alimenta com a nota do quadro ([n] null = sem nota), o tempo do quadro
  /// [dt] e o instante [now] (s). As notas confirmadas entram em [grid].
  void update(PitchGrid grid, TrackedNote? n, double dt, double now) {
    _grid = grid;
    final g = _midi;
    if (g != null) {
      if (n == null) {
        if (now - _last > dropout) close();
        return;
      }
      if (n.midi != g) close();
    }
    if (n == null) return;
    if (_midi == null) {
      _midi = n.midi;
      _start = now;
      _open = false;
      _claritySum = 0;
      _frames = 0;
      _pending.clear();
    }
    _last = now;
    _claritySum += n.clarity;
    _frames++;
    if (_open) {
      grid.add(n.midi, n.cents, n.clarity, dt, now);
      return;
    }
    _pending.add((n.cents, n.clarity, dt, now));
    final need = now < _trillUntil ? math.min(minSeconds, trillMinSeconds) : minSeconds;
    if (now - _start >= need) {
      _open = true;
      for (final p in _pending) {
        grid.add(n.midi, p.$1, p.$2, p.$3, p.$4);
      }
      _pending.clear();
    }
  }

  /// Encerra a nota em andamento e a registra no histórico.
  void close() {
    final g = _midi;
    if (g != null && _frames > 0) {
      final run = NoteRun(g, _last - _start, _claritySum / _frames, _open);
      runs.insert(0, run);
      if (runs.length > keepRuns) runs.removeLast();
      _closed.add(_Closed(g, _start, _last, _open, _open ? const [] : List.of(_pending), run));
      if (_closed.length > 6) _closed.removeAt(0);
    }
    _midi = null;
    _open = false;
    _pending.clear();
    _checkTrill();
  }

  /// Quatro notas alternadas (A, B, A, B) em pouco tempo = trinado. Entra no modo
  /// trinado (notas curtas valem) e credita as que tinham sido descartadas por
  /// serem curtas: o trinado não perde as primeiras notas.
  void _checkTrill() {
    if (_closed.length < 4) return;
    final e = _closed.sublist(_closed.length - 4);
    if (e.last.last - e.first.start > trillSpan) return;
    if (e[0].midi != e[2].midi || e[1].midi != e[3].midi || e[0].midi == e[1].midi) return;
    // Um quadro solto não é nota de trinado.
    if (e.any((x) => x.last - x.start < 0.02)) return;
    // Notas longas não formam trinado (é uma nota sustentada com ruído entre elas).
    if (e.any((x) => x.last - x.start > 0.25)) return;
    _trillUntil = e.last.last + trillHold;
    final grid = _grid;
    if (grid == null) return;
    for (final x in e) {
      if (x.kept || x.frames.isEmpty) continue;
      for (final f in x.frames) {
        grid.add(x.midi, f.$1, f.$2, f.$3, f.$4);
      }
      x.kept = true;
      final i = runs.indexOf(x.run);
      final r = NoteRun(x.run.midi, x.run.seconds, x.run.clarity, true);
      if (i >= 0) runs[i] = r;
      x.run = r;
    }
  }

  /// Esquece tudo (ao zerar a sessão).
  void reset() {
    _midi = null;
    _open = false;
    _pending.clear();
    runs.clear();
    _closed.clear();
    _trillUntil = double.negativeInfinity;
  }
}
