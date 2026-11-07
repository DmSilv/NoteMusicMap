/// Exercício de escalas guiado (estilo "sistema de escalas" de Carl Flesch):
/// o músico toca a escala subindo e descendo, em 1, 2 ou 3 oitavas, e o app
/// acompanha nota por nota, medindo a afinação de cada uma.
///
/// Lógica pura: quem usa alimenta o exercício com as notas detectadas.
library;


import 'pitch_grid.dart';

/// Sequência completa: sobe até a tônica mais alta e desce até a tônica
/// (sem repetir a nota do topo). Na menor melódica, desce como menor natural.
List<int> scaleSequence(int tonicMidi, ScaleType t,
    {int octaves = 1, bool descend = true}) {
  final up = scaleMidis(tonicMidi, t, octaves: octaves);
  if (!descend) return up;
  final down = <int>[];
  for (var o = octaves - 1; o >= 0; o--) {
    for (final s in t.downSteps.reversed) {
      down.add(tonicMidi + 12 * o + s);
    }
  }
  return [...up, ...down];
}

class StepResult {
  final int midi;
  final bool ascending;

  /// Oitava dentro do exercício (0 = a mais grave).
  final int octaveIndex;

  /// Desvio médio em cents (null se a nota foi pulada).
  final double? cents;
  final double seconds;
  final bool skipped;
  const StepResult(this.midi, this.ascending, this.octaveIndex, this.cents,
      this.seconds, this.skipped);
}

class ExerciseScore {
  /// Fração (0..1) das notas dentro da faixa "afinado".
  final double accuracy;

  /// Desvio médio absoluto (cents) das notas tocadas.
  final double meanAbsCents;
  final int inTune;
  final int played;
  final int total;
  const ExerciseScore(
      this.accuracy, this.meanAbsCents, this.inTune, this.played, this.total);
}

class ScaleExercise {
  final List<int> sequence;
  final int upCount;
  final int tonicMidi;
  final double zone;

  /// Tempo (s) sobre a nota certa para dá-la como tocada.
  final double holdSeconds;

  /// Tempo inicial ignorado na média (a altura ainda está assentando).
  final double settleSeconds;

  int index = 0;
  final List<StepResult> results = [];

  double _sum = 0, _w = 0, _time = 0;

  ScaleExercise({
    required this.tonicMidi,
    required ScaleType type,
    required int octaves,
    required this.zone,
    this.holdSeconds = 0.5,
    this.settleSeconds = 0.12,
  })  : sequence = scaleSequence(tonicMidi, type, octaves: octaves),
        upCount = scaleMidis(tonicMidi, type, octaves: octaves).length;

  bool get finished => index >= sequence.length;
  int? get expected => finished ? null : sequence[index];
  bool get ascendingNow => index < upCount;
  double get progress => sequence.isEmpty ? 0 : index / sequence.length;

  /// 0..1 de quanto da nota atual já foi segurado.
  double get holdProgress => (_time / holdSeconds).clamp(0.0, 1.0);

  int _octaveOf(int midi) => ((midi - tonicMidi) / 12).floor().clamp(0, 99);

  /// Alimente com a nota estável detectada (ou null). Devolve o resultado
  /// quando a nota esperada é concluída.
  StepResult? feed({
    required int? midi,
    required double cents,
    required double clarity,
    required double dt,
  }) {
    if (finished) return null;
    if (midi != expected) return null; // outras notas são ignoradas
    _time += dt;
    if (_time > settleSeconds) {
      final w = clarity.clamp(0.0, 1.0) * dt;
      _sum += cents.clamp(-100.0, 100.0) * w;
      _w += w;
    }
    if (_time < holdSeconds) return null;
    final avg = _w > 0 ? _sum / _w : cents;
    return _complete(StepResult(sequence[index], ascendingNow,
        _octaveOf(sequence[index]), avg, _time, false));
  }

  /// Pula a nota atual (conta como não afinada).
  StepResult? skip() {
    if (finished) return null;
    return _complete(StepResult(
        sequence[index], ascendingNow, _octaveOf(sequence[index]), null, 0, true));
  }

  StepResult _complete(StepResult r) {
    results.add(r);
    index++;
    _sum = _w = _time = 0;
    return r;
  }

  ExerciseScore get score {
    var inTune = 0, played = 0;
    var sumAbs = 0.0;
    for (final r in results) {
      if (r.skipped || r.cents == null) continue;
      played++;
      sumAbs += r.cents!.abs();
      if (r.cents!.abs() <= zone) inTune++;
    }
    final total = sequence.length;
    // Notas puladas ou ainda não tocadas contam contra a taxa de acerto.
    final acc = total == 0 ? 0.0 : inTune / total;
    return ExerciseScore(acc, played == 0 ? 0 : sumAbs / played, inTune, played, total);
  }
}

