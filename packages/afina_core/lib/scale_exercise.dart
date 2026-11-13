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

/// Para onde vai o exercício: só subindo, só descendo, ou subindo e descendo.
enum ScaleDirection { up, down, both }

/// Sequência completa: sobe até a tônica mais alta e desce até a tônica
/// (sem repetir a nota do topo). Na menor melódica, desce como menor natural.
/// [direction]: só subindo, só descendo (começa na tônica mais alta) ou os dois.
List<int> scaleSequence(int tonicMidi, ScaleType t,
    {int octaves = 1, bool descend = true, ScaleDirection direction = ScaleDirection.both}) {
  final up = scaleMidis(tonicMidi, t, octaves: octaves);
  if (!descend || direction == ScaleDirection.up) return up;
  final base = tonicMidi + t.start;
  final down = <int>[];
  for (var o = octaves - 1; o >= 0; o--) {
    for (final s in t.downSteps.reversed) {
      down.add(base + 12 * o + s);
    }
  }
  if (direction == ScaleDirection.down) return [up.last, ...down];
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

/// Resultado de uma nota no modo livre (a última vez que foi tocada).
class FreeNote {
  final int midi;

  /// Desvio (cents) pela mediana do que foi ouvido na última vez.
  final double cents;

  /// Quantas vezes a nota foi tocada.
  final int attempts;
  final double seconds;
  const FreeNote(this.midi, this.cents, this.attempts, this.seconds);
}

class ScaleExercise {
  final List<int> sequence;
  final int upCount;
  final ScaleDirection direction;
  final int tonicMidi;
  final double zone;

  /// true = EXECUÇÃO LIVRE: toque qualquer nota da escala, em qualquer ordem,
  /// e o app valida a afinação de cada uma. false = GUIADO: uma nota por vez,
  /// e a próxima só vem quando a atual ficar afinada. Pode ser trocado durante
  /// o exercício; a nota em andamento recomeça.
  bool _flow;
  bool get flow => _flow;
  set flow(bool v) {
    if (v == _flow) return;
    _flow = v;
    _resetCurrent();
  }

  /// Modo guiado: tempo (s) SEGUIDO dentro da faixa "afinado" para a nota valer.
  final double holdSeconds;

  /// Tempo inicial ignorado na medida (a altura ainda está assentando).
  final double settleSeconds;

  /// Modo guiado: janela (s) depois do assentar usada como "primeira tentativa".
  final double landingSeconds;

  /// Modo livre: tempo mínimo (s) ouvindo uma nota para ela contar.
  final double flowMinSeconds;

  /// Modo livre: silêncio (s) que encerra a nota em andamento (tocar de novo
  /// a mesma nota depois disso conta como outra tentativa).
  final double flowReleaseSeconds;

  int index = 0;
  final List<StepResult> results = [];

  // ---- modo guiado ----
  double _time = 0; // s ouvindo a nota esperada
  double _run = 0; // s seguidos afinada
  bool _tunedNow = false;
  final List<_Sample> _landing = [];

  // ---- modo livre ----
  late final List<int> freeNotes; // notas distintas da escala, do grave ao agudo
  final Map<int, FreeNote> board = {};
  int? _curMidi;
  double _heard = 0; // s ouvindo a nota atual
  double _silence = 0; // s de silêncio seguidos
  bool _counted = false;
  final List<_Sample> _samples = [];
  bool _done = false;

  late final Set<int> _scalePcs;

  ScaleExercise({
    required this.tonicMidi,
    required ScaleType type,
    required int octaves,
    required this.zone,
    this.holdSeconds = 0.5,
    this.settleSeconds = 0.08,
    this.landingSeconds = 0.45,
    bool flow = false,
    this.flowMinSeconds = 0.05,
    this.flowReleaseSeconds = 0.22,
    this.direction = ScaleDirection.both,
  })  : _flow = flow,
        sequence = scaleSequence(tonicMidi, type, octaves: octaves, direction: direction),
        upCount = direction == ScaleDirection.down ? 0 : scaleMidis(tonicMidi, type, octaves: octaves).length {
    _scalePcs = {for (final m in sequence) m % 12};
    freeNotes = ({...sequence}.toList()..sort());
  }

  bool get finished => _flow ? _done : index >= sequence.length;

  /// Modo livre: encerra o exercício (botão "Concluir").
  void finish() => _done = true;

  /// Nota pedida agora. No modo guiado é a da vez; no livre é só uma sugestão
  /// (a mais grave ainda não tocada), sem obrigar nenhuma ordem.
  int? get expected {
    if (finished) return null;
    if (!_flow) return sequence[index];
    for (final m in freeNotes) {
      if (!board.containsKey(m)) return m;
    }
    return null;
  }

  bool get ascendingNow => _flow ? direction != ScaleDirection.down : index < upCount;

  /// O passo [i] da sequência é de subida?
  bool ascendingAt(int i) => i < upCount;
  double get progress {
    if (_flow) return freeNotes.isEmpty ? 0 : board.length / freeNotes.length;
    return sequence.isEmpty ? 0 : index / sequence.length;
  }

  /// Modo livre: todas as notas da escala já foram tocadas ao menos uma vez.
  bool get allPlayed => _flow && board.length == freeNotes.length;

  /// Modo livre: nota que está soando agora (da escala), ou null.
  int? get currentFreeMidi => _curMidi;

  /// 0..1 de quanto já foi segurado AFINADO (modo guiado).
  double get holdProgress => _flow ? 0 : (_run / holdSeconds).clamp(0.0, 1.0);

  /// Modo guiado: o último quadro estava na nota certa E dentro da faixa afinada.
  bool get tunedNow => !_flow && _tunedNow;

  /// true quando o microfone está ouvindo uma nota da escala (modo livre).
  bool get hearing => _flow && _curMidi != null && _heard >= flowMinSeconds && _silence == 0;

  int _octaveOf(int midi) => ((midi - tonicMidi) / 12).floor().clamp(0, 99);

  /// Resultados para guardar no histórico: a sequência (guiado) ou a última
  /// medida de cada nota (livre).
  List<StepResult> get finalResults {
    if (!_flow) return results;
    return [
      for (final m in freeNotes)
        if (board[m] != null)
          StepResult(m, true, _octaveOf(m), board[m]!.cents, board[m]!.seconds, false)
    ];
  }

  /// Alimente com a nota estável detectada (ou null). Devolve um resultado
  /// quando uma nota é concluída (guiado) ou medida pela primeira vez (livre).
  StepResult? feed({
    required int? midi,
    required double cents,
    required double clarity,
    required double dt,
  }) {
    if (finished) return null;
    return _flow ? _feedFree(midi, cents, clarity, dt) : _feedHold(midi, cents, clarity, dt);
  }

  int _nearestScaleNote(int m) {
    var best = freeNotes.first;
    for (final n in freeNotes) {
      if ((n - m).abs() < (best - m).abs()) best = n;
    }
    return best;
  }

  /// Aviso leve para a nota [heardMidi] (com desvio [heardCents] em relação a
  /// ela mesma): devolve null se não há o que avisar. No modo guiado, avisa
  /// quando a nota ouvida não é a da vez; no livre, só quando não é da escala.
  NoteCue? cue(int? heardMidi, double heardCents) {
    if (finished || heardMidi == null) return null;
    if (_flow) {
      if (freeNotes.contains(heardMidi)) return null;
      final near = _nearestScaleNote(heardMidi);
      return NoteCue(heardMidi, near, (heardMidi - near) * 100.0 + heardCents,
          _scalePcs.contains(heardMidi % 12));
    }
    final exp = expected;
    if (exp == null || heardMidi == exp) return null;
    final off = (heardMidi - exp) * 100.0 + heardCents;
    return NoteCue(heardMidi, exp, off, _scalePcs.contains(heardMidi % 12));
  }

  // ---------------- modo guiado: só avança afinada ----------------
  StepResult? _feedHold(int? midi, double cents, double clarity, double dt) {
    _tunedNow = false;
    if (midi != expected) {
      // Saiu da nota: perde um pouco do que tinha segurado.
      _run = (_run - dt).clamp(0.0, double.infinity);
      return null;
    }
    _time += dt;
    // "Primeira tentativa": o que se ouviu logo depois de a altura assentar.
    if (_time > settleSeconds && _time <= settleSeconds + landingSeconds) {
      _landing.add(_Sample(_time, cents.clamp(-100.0, 100.0), clarity.clamp(0.05, 1.0) * dt));
    }
    final inZone = cents.abs() <= zone;
    _tunedNow = inZone;
    if (inZone) {
      _run += dt;
    } else {
      _run = (_run - dt * 1.5).clamp(0.0, double.infinity);
    }
    if (_run < holdSeconds) return null;
    final land = _landing.isNotEmpty ? _weightedMedian(_landing) : cents;
    return _complete(StepResult(
        sequence[index], ascendingNow, _octaveOf(sequence[index]), land, _time, false));
  }

  // ---------------- modo livre: qualquer nota da escala ----------------
  StepResult? _feedFree(int? midi, double cents, double clarity, double dt) {
    if (midi == null) {
      _silence += dt;
      if (_silence >= flowReleaseSeconds) _endRun();
      return null;
    }
    _silence = 0;
    if (!freeNotes.contains(midi)) {
      _endRun(); // nota fora da escala: não conta (a tela avisa)
      return null;
    }
    if (midi != _curMidi) {
      _endRun();
      _curMidi = midi;
    }
    _heard += dt;
    if (_samples.length < 400) {
      _samples.add(_Sample(_heard, cents.clamp(-100.0, 100.0), clarity.clamp(0.05, 1.0) * dt));
    }
    if (_heard < flowMinSeconds) return null;
    // Mediana até agora, sem o começo instável quando há dados suficientes.
    var use = _samples.where((s) => s.t > settleSeconds).toList();
    if (use.length < 3) use = List.of(_samples);
    final med = _weightedMedian(use);
    final prev = board[midi];
    final first = !_counted;
    _counted = true;
    board[midi] = FreeNote(midi, med, (prev?.attempts ?? 0) + (first ? 1 : 0),
        _heard);
    if (!first) return null;
    final r = StepResult(midi, true, _octaveOf(midi), med, _heard, false);
    results.add(r);
    return r;
  }

  void _endRun() {
    _curMidi = null;
    _heard = 0;
    _counted = false;
    _samples.clear();
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

  /// Pula a nota atual (modo guiado; conta como não afinada).
  StepResult? skip() {
    if (finished || _flow) return null;
    return _complete(StepResult(
        sequence[index], ascendingNow, _octaveOf(sequence[index]), null, 0, true));
  }

  void _resetCurrent() {
    _time = _run = 0;
    _tunedNow = false;
    _landing.clear();
    _endRun();
    _silence = 0;
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
    if (_flow) {
      for (final n in board.values) {
        played++;
        sumAbs += n.cents.abs();
        if (n.cents.abs() <= zone) inTune++;
      }
      final total = freeNotes.length;
      final acc = total == 0 ? 0.0 : inTune / total;
      return ExerciseScore(acc, played == 0 ? 0 : sumAbs / played, inTune, played, total);
    }
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
