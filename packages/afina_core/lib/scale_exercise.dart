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

/// Quão exigente é o exercício guiado. A zona é o desvio (cents) que ainda vale como "afinado"; a oscilação aceita na chegada
/// e a janela em que a chegada é medida também crescem nos níveis mais folgados (vibrato e transição do arco não reprovam).
enum ScaleTolerance {
  strict(10, 1.2, 0.2, 'Rigoroso'),
  standard(20, 2.0, 0.3, 'Padrão'),
  easy(30, 2.0, 0.3, 'Iniciante');

  /// Desvio máximo (cents) para valer como afinado.
  final double cents;

  /// Quanto a altura pode oscilar na chegada, em múltiplos da zona (máximo menos mínimo).
  final double spread;

  /// Janela (s) em que a chegada é medida.
  final double arrivalSeconds;
  final String label;
  const ScaleTolerance(this.cents, this.spread, this.arrivalSeconds, this.label);

  static ScaleTolerance byName(String? n) => ScaleTolerance.values.firstWhere((x) => x.name == n, orElse: () => ScaleTolerance.standard);
}

/// Por que o exercício travou e mandou voltar à nota anterior.
enum LockReason { wrongNote, sharp, flat, unstable }

/// Como foi a última chegada numa nota (para a tela explicar, por uns instantes, o que o app ouviu).
class ArrivalInfo {
  /// Desvio (mediana) na chegada, em cents; positivo = alto.
  final double cents;

  /// Oscilação (máximo menos mínimo) na janela de chegada.
  final double spread;
  final bool ok;
  const ArrivalInfo(this.cents, this.spread, this.ok);
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
  double zone;

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

  /// Modo guiado "sem escorregar": a nota precisa CHEGAR afinada. Se chegou fora da faixa (ou veio deslizando até
  /// achar a altura), o exercício trava e o aluno tem de voltar a tocar a nota ANTERIOR e depois a da vez de novo, para
  /// não ficar procurando a nota com o dedo (o ouvido e a mão esquerda só evoluem acertando na primeira).
  bool noSlide;

  /// Janela (s) logo depois de a altura assentar que decide se a nota chegou afinada.
  double arrivalSeconds;

  /// Oscilação aceita na janela de chegada, em múltiplos da zona.
  double arrivalSpread;

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
  double _waiting = 0; // s desde que a nota atual passou a ser a esperada (tocando ou não)
  double _run = 0; // s seguidos afinada
  bool _tunedNow = false;
  final List<_Sample> _landing = [];

  // ---- guiado sem escorregar ----
  bool _locked = false; // chegou fora da afinação: precisa voltar à nota anterior
  bool _checked = false; // a chegada desta tentativa já foi avaliada (e passou)
  bool _wasOn = false; // o quadro anterior estava na nota da vez
  double _offT = 99; // s seguidos fora da nota da vez (99 = ainda não começou)
  double _backHeld = 0; // s tocando a nota anterior afinada, para destravar
  double _gapT = 0; // s soltos (primeira nota: basta soltar e tocar de novo)
  final List<_Sample> _arrival = [];

  /// Quantas vezes a nota chegou desafinada (ou escorregando) neste exercício.
  int slips = 0;

  /// Quantas vezes o aluno saiu da nota anterior direto para uma nota errada (sem passar pela da vez).
  int wrongStarts = 0;

  /// Tempo (s) seguidos numa nota errada, logo depois de largar a anterior, para valer como "errou o começo".
  final double wrongSeconds;
  double _wrongT = 0;

  /// A nota errada que travou o exercício (null: travou por chegar desafinada ou escorregando).
  int? lockWrongMidi;

  /// Por que travou (null: não está travado) e como foi a chegada que travou (mediana e oscilação, em cents).
  LockReason? lockReason;
  double lockCents = 0;
  double lockSpread = 0;

  /// Contadores do exercício: voltas por nota alta, baixa, instável, e quantas vezes a volta foi dispensada.
  int slipsSharp = 0, slipsFlat = 0, slipsUnstable = 0, skippedReplays = 0;

  /// Quantas vezes travou nesta mesma nota (zera ao avançar). Com 2 ou mais, a volta pode ser dispensada.
  int _locksHere = 0;

  /// Relógio do exercício (s), para os avisos que duram só um instante.
  double _clock = 0;
  ArrivalInfo? _lastArrival;
  double _arrivalAt = -99;
  double _shortAt = -99;
  bool _onPrev = false;
  double _offShort = 0;

  /// A chegada mais recente (mostrada por ~2,5 s), ou null.
  ArrivalInfo? get recentArrival => _clock - _arrivalAt <= 2.5 ? _lastArrival : null;

  /// O aluno largou a nota antes de a barra encher (mostrado por ~2,5 s).
  bool get recentShort => _clock - _shortAt <= 2.5;

  /// Travado pela segunda vez (ou mais) na mesma nota: pode tentar de novo sem voltar à anterior.
  bool get canSkipReplay => replayNeeded && _locksHere >= 2;

  /// Dispensa a volta à nota anterior: destrava e deixa tentar a nota da vez de novo.
  void skipReplay() {
    if (!replayNeeded) return;
    skippedReplays++;
    _unlock();
  }

  void _unlock() {
    _locked = false;
    lockWrongMidi = null;
    lockReason = null;
    _backHeld = 0;
    _gapT = 0;
    _offT = 99;
    _wasOn = false;
  }

  void _lock(LockReason reason, {double cents = 0, double spread = 0}) {
    _resetCurrent();
    _locked = true;
    _locksHere++;
    lockReason = reason;
    lockCents = cents;
    lockSpread = spread;
    _backHeld = 0;
    _gapT = 0;
    switch (reason) {
      case LockReason.sharp:
        slipsSharp++;
      case LockReason.flat:
        slipsFlat++;
      case LockReason.unstable:
        slipsUnstable++;
      case LockReason.wrongNote:
        break;
    }
  }

  /// Aplica um nível de tolerância (vale já no exercício em andamento).
  void applyTolerance(ScaleTolerance tol) {
    zone = tol.cents;
    arrivalSpread = tol.spread;
    arrivalSeconds = tol.arrivalSeconds;
  }

  /// O exercício está travado esperando o aluno voltar à nota anterior (ou soltar, na primeira nota).
  bool get replayNeeded => !_flow && noSlide && _locked;

  /// A nota anterior, que o aluno precisa tocar de novo para destravar (null na primeira nota: basta soltar e tocar).
  int? get replayMidi => replayNeeded && index > 0 ? sequence[index - 1] : null;

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
    this.noSlide = false,
    this.arrivalSeconds = 0.2,
    this.arrivalSpread = 1.2,
    this.wrongSeconds = 0.15,
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

  /// Modo guiado: há quanto tempo (s) a nota atual espera ser tocada. Serve para a dica de uma nota difícil de achar.
  double get waitingSeconds => _flow ? 0 : _waiting;

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
    if (exp == null) return null;
    return cueTo(exp, heardMidi, heardCents);
  }

  /// Aviso para a nota ouvida em relação a uma nota-alvo qualquer (por exemplo, a anterior, quando o exercício
  /// está travado esperando o aluno voltar a ela).
  NoteCue? cueTo(int target, int? heardMidi, double heardCents) {
    if (heardMidi == null || heardMidi == target) return null;
    final off = (heardMidi - target) * 100.0 + heardCents;
    return NoteCue(heardMidi, target, off, _scalePcs.contains(heardMidi % 12));
  }

  // ---------------- modo guiado: só avança afinada ----------------
  StepResult? _feedHold(int? midi, double cents, double clarity, double dt) {
    _tunedNow = false;
    _waiting += dt;
    _clock += dt;
    if (noSlide && _locked) return _feedLocked(midi, cents, dt);
    if (midi != expected) {
      // Largou a nota antes de a barra encher (por mais que um instante): avisa que é para segurar mais.
      if (_onPrev) {
        _offShort += dt;
        if (_offShort >= 0.15) {
          _onPrev = false;
          if (_time >= 0.2 && _run < holdSeconds) _shortAt = _clock;
        }
      }
      // Saiu da nota: perde um pouco do que tinha segurado.
      _run = (_run - dt).clamp(0.0, double.infinity);
      if (noSlide) {
        _wasOn = false;
        _offT += dt;
        // Saiu da nota anterior e caiu numa nota ERRADA antes de tocar a da vez: tem de voltar à anterior.
        // (A nota anterior em si não conta: o aluno ainda pode estar segurando ela. Na primeira nota não há para onde voltar.)
        if (midi != null && index > 0 && _time == 0 && midi != sequence[index - 1]) {
          _wrongT += dt;
          if (_wrongT >= wrongSeconds) {
            slips++;
            wrongStarts++;
            final heard = midi;
            _lock(LockReason.wrongNote);
            lockWrongMidi = heard;
          }
        } else {
          _wrongT = 0;
        }
      }
      return null;
    }
    _wrongT = 0;
    _onPrev = true;
    _offShort = 0;
    if (noSlide) {
      // Nota nova (vinda de outra ou de silêncio por um instante): é uma CHEGADA, que começa do zero.
      if (!_wasOn && _offT >= 0.12) {
        _time = 0;
        _run = 0;
        _landing.clear();
        _arrival.clear();
        _checked = false;
      }
      _wasOn = true;
      _offT = 0;
    }
    _time += dt;
    if (noSlide && !_checked) {
      if (_time > settleSeconds && _time <= settleSeconds + arrivalSeconds) {
        _arrival.add(_Sample(_time, cents.clamp(-100.0, 100.0), clarity.clamp(0.05, 1.0) * dt));
      }
      if (_time > settleSeconds + arrivalSeconds) {
        // Chegou afinada e firme, ou escorregou? Mediana fora da faixa, ou a altura andou demais na janela, é escorregar.
        if (_arrival.length >= 2) {
          final med = _weightedMedian(_arrival);
          var lo = 1e9, hi = -1e9;
          for (final s in _arrival) {
            if (s.cents < lo) lo = s.cents;
            if (s.cents > hi) hi = s.cents;
          }
          final spread = hi - lo;
          final off = med.abs() > zone;
          final shaky = spread > zone * arrivalSpread;
          _lastArrival = ArrivalInfo(med, spread, !off && !shaky);
          _arrivalAt = _clock;
          if (off || shaky) {
            slips++;
            _lock(off ? (med > 0 ? LockReason.sharp : LockReason.flat) : LockReason.unstable, cents: med, spread: spread);
            lockWrongMidi = null;
            return null;
          }
        }
        _checked = true;
      }
    }
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

  /// Travado: a nota da vez chegou desafinada. Destrava tocando a nota ANTERIOR afinada por um instante
  /// (na primeira nota, que não tem anterior, basta soltar por um instante e tocar de novo).
  StepResult? _feedLocked(int? midi, double cents, double dt) {
    final prev = index > 0 ? sequence[index - 1] : null;
    if (prev != null) {
      if (midi == prev && cents.abs() <= zone * 1.5) {
        _backHeld += dt;
        if (_backHeld >= 0.25) _unlock();
      } else {
        _backHeld = (_backHeld - dt).clamp(0.0, double.infinity);
      }
      return null;
    }
    if (midi != expected) {
      _gapT += dt;
      if (_gapT >= 0.3) _unlock();
    } else {
      _gapT = 0;
    }
    return null;
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
    _locked = false; // pular a nota também solta o travamento do "sem escorregar"
    lockWrongMidi = null;
    lockReason = null;
    return _complete(StepResult(
        sequence[index], ascendingNow, _octaveOf(sequence[index]), null, 0, true));
  }

  void _resetCurrent() {
    _arrival.clear();
    _checked = false;
    _wasOn = false;
    _offT = 99;
    _time = _run = 0;
    _waiting = 0;
    _tunedNow = false;
    _landing.clear();
    _endRun();
    _silence = 0;
    _wrongT = 0;
  }

  StepResult _complete(StepResult r) {
    results.add(r);
    index++;
    _locksHere = 0;
    _onPrev = false;
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
