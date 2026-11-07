/// Exercício de escalas guiado (estilo "sistema de escalas" de Carl Flesch):
/// o músico toca a escala subindo e descendo, em 1, 2 ou 3 oitavas, e o app
/// acompanha nota por nota, medindo a afinação de cada uma.
///
/// Dois jeitos de acompanhar:
///  - **Esperar cada nota** (clássico): a nota precisa ser segurada por um
///    tempo antes de o app dá-la como tocada;
///  - **Seguir meu ritmo** (`flow`): o músico toca a escala sem parar e o app
///    acompanha. Cada nota vale quando ele passa para a próxima (ou cala), e o
///    desvio é a MEDIANA do que foi ouvido, então a transição entre notas não
///    estraga a medida. Notas fora do lugar são ignoradas e geram só um aviso
///    leve ("ainda não é Lá: suba um pouco").
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

/// Aviso leve quando a nota ouvida ainda NÃO é a esperada.
class NoteCue {
  /// Nota que o microfone ouviu.
  final int heardMidi;

  /// Nota que o exercício espera.
  final int expectedMidi;

  /// Onde a nota ouvida está em relação à esperada, em cents
  /// (negativo = abaixo/grave, positivo = acima/aguda).
  final double offCents;

  /// A nota ouvida pertence à escala?
  final bool inScale;
  const NoteCue(this.heardMidi, this.expectedMidi, this.offCents, this.inScale);

  /// O músico precisa SUBIR a afinação para chegar na nota esperada.
  bool get goUp => offCents < 0;

  /// Perto o bastante para dizer "suba/desça um pouco" (até ~1,5 semitom).
  bool get near => offCents.abs() <= 160;

  /// 0 = um pouco, 1 = médio, 2 = bastante.
  int get amount {
    final a = offCents.abs();
    if (a <= 70) return 0;
    if (a <= 130) return 1;
    return 2;
  }
}

class _Sample {
  final double t; // tempo desde que a nota começou (s)
  final double cents;
  final double w; // peso (clareza × duração)
  const _Sample(this.t, this.cents, this.w);
}

class ScaleExercise {
  final List<int> sequence;
  final int upCount;
  final int tonicMidi;
  final double zone;

  /// true = "seguir meu ritmo" (sem exigir segurar a nota). Pode ser trocado
  /// durante o exercício; a nota em andamento recomeça.
  bool _flow;
  bool get flow => _flow;
  set flow(bool v) {
    if (v == _flow) return;
    _flow = v;
    _resetCurrent();
  }

  /// Tempo (s) sobre a nota certa para dá-la como tocada (modo "esperar").
  final double holdSeconds;

  /// Tempo inicial ignorado na média (a altura ainda está assentando).
  final double settleSeconds;

  /// Modo "seguir meu ritmo": tempo mínimo (s) ouvindo a nota esperada para
  /// ela valer. Notas mais curtas que isso não contam (provável ruído).
  final double flowMinSeconds;

  /// Modo "seguir meu ritmo": silêncio (s) que encerra a nota em andamento.
  final double flowReleaseSeconds;

  /// Modo "seguir meu ritmo": a ÚLTIMA nota não tem "próxima" para encerrá-la;
  /// conclui depois de ouvida por este tempo (s).
  final double flowLastSeconds;

  int index = 0;
  final List<StepResult> results = [];

  // modo "esperar"
  double _sum = 0, _w = 0, _time = 0;

  // modo "seguir meu ritmo"
  double _heard = 0; // s ouvindo a nota esperada
  double _silence = 0; // s de silêncio seguidos
  final List<_Sample> _samples = [];
  late final Set<int> _scalePcs;

  ScaleExercise({
    required this.tonicMidi,
    required ScaleType type,
    required int octaves,
    required this.zone,
    this.holdSeconds = 0.5,
    this.settleSeconds = 0.12,
    bool flow = false,
    this.flowMinSeconds = 0.10,
    this.flowReleaseSeconds = 0.22,
    this.flowLastSeconds = 0.45,
  })  : _flow = flow,
        sequence = scaleSequence(tonicMidi, type, octaves: octaves),
        upCount = scaleMidis(tonicMidi, type, octaves: octaves).length {
    _scalePcs = {for (final m in sequence) m % 12};
  }

  bool get finished => index >= sequence.length;
  int? get expected => finished ? null : sequence[index];
  bool get ascendingNow => index < upCount;
  double get progress => sequence.isEmpty ? 0 : index / sequence.length;

  /// 0..1 de quanto da nota atual já foi segurado (modo "esperar").
  double get holdProgress => (_time / holdSeconds).clamp(0.0, 1.0);

  /// true quando o microfone está ouvindo a nota esperada agora (modo "seguir
  /// meu ritmo"), depois do tempo mínimo.
  bool get hearing => _flow && _heard >= flowMinSeconds && _silence == 0;

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
    return _flow ? _feedFlow(midi, cents, clarity, dt) : _feedHold(midi, cents, clarity, dt);
  }

  /// Aviso leve para a nota [heardMidi] (com desvio [heardCents] em relação a
  /// ela mesma): devolve null se não há o que avisar (silêncio, nota certa ou
  /// exercício terminado).
  NoteCue? cue(int? heardMidi, double heardCents) {
    final exp = expected;
    if (exp == null || heardMidi == null || heardMidi == exp) return null;
    final off = (heardMidi - exp) * 100.0 + heardCents;
    return NoteCue(heardMidi, exp, off, _scalePcs.contains(heardMidi % 12));
  }

  // ---------------- modo "esperar cada nota" ----------------
  StepResult? _feedHold(int? midi, double cents, double clarity, double dt) {
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

  // ---------------- modo "seguir meu ritmo" ----------------
  StepResult? _feedFlow(int? midi, double cents, double clarity, double dt) {
    final exp = sequence[index];
    if (midi == exp) {
      _silence = 0;
      _heard += dt;
      if (_samples.length < 600) {
        _samples.add(_Sample(_heard, cents.clamp(-100.0, 100.0),
            (clarity.clamp(0.05, 1.0)) * dt));
      }
      // A última nota não tem "próxima" para encerrá-la.
      if (index == sequence.length - 1 && _heard >= flowLastSeconds) {
        return _completeFlow();
      }
      return null;
    }
    if (midi == null) {
      _silence += dt;
      // O som parou depois de a nota ter sido ouvida: dá por concluída.
      if (_heard >= flowMinSeconds && _silence >= flowReleaseSeconds) {
        return _completeFlow();
      }
      return null;
    }
    // Ouviu OUTRA nota.
    _silence = 0;
    final next = index + 1 < sequence.length ? sequence[index + 1] : null;
    if (_heard >= flowMinSeconds && midi == next) {
      // Passou para a próxima da escala: fecha esta e já conta este quadro
      // para a nova nota.
      final r = _completeFlow();
      if (!finished) _feedFlow(midi, cents, clarity, dt);
      return r;
    }
    return null; // nota errada ou de passagem: só ignora (a tela dá um aviso)
  }

  StepResult _completeFlow() {
    // Mediana ponderada dos desvios, sem o começo (a altura ainda assenta).
    var use = _samples.where((s) => s.t > settleSeconds).toList();
    if (use.length < 3) use = List.of(_samples); // nota curta: usa tudo
    final cents = use.isEmpty ? 0.0 : _weightedMedian(use);
    return _complete(StepResult(sequence[index], ascendingNow,
        _octaveOf(sequence[index]), cents, _heard, false));
  }

  static double _weightedMedian(List<_Sample> v) {
    final s = [...v]..sort((a, b) => a.cents.compareTo(b.cents));
    final total = s.fold<double>(0, (a, b) => a + b.w);
    if (total <= 0) return s[s.length ~/ 2].cents;
    var acc = 0.0;
    for (final x in s) {
      acc += x.w;
      if (acc >= total / 2) return x.cents;
    }
    return s.last.cents;
  }

  /// Pula a nota atual (conta como não afinada).
  StepResult? skip() {
    if (finished) return null;
    return _complete(StepResult(
        sequence[index], ascendingNow, _octaveOf(sequence[index]), null, 0, true));
  }

  void _resetCurrent() {
    _sum = _w = _time = 0;
    _heard = _silence = 0;
    _samples.clear();
  }

  StepResult _complete(StepResult r) {
    results.add(r);
    index++;
    _resetCurrent();
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
