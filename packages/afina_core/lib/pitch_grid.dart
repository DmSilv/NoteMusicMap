/// Estabilizador de notas + grade de entonação + relatório de escala.
///
/// A grade guarda, para cada nota (número MIDI), a MÉDIA PONDERADA do desvio em
/// cents em relação ao alvo do sistema escolhido. Ponderação por clareza e por
/// tempo tocado, para vibrato não "piscar" e notas curtas não pesarem demais.
library;

import 'dart:math' as math;

import 'pitch_detector.dart';
import 'tuning.dart';

// ---------------------------------------------------------------------------
// Estabilizador
// ---------------------------------------------------------------------------

class TrackedNote {
  final int midi;
  final double freq;
  final double target;

  /// Desvio suavizado em relação ao alvo (cents; + = agudo).
  final double cents;
  final double clarity;
  const TrackedNote(this.midi, this.freq, this.target, this.cents, this.clarity);
}

/// Transforma leituras instáveis em notas estáveis:
///  - mediana evita saltos de oitava de um quadro só;
///  - filtro de ataque: só emite depois de [onsetFrames] quadros na mesma nota;
///  - histerese: perto do limite entre duas notas, mantém a atual (±75¢);
///  - vibrato: trocar para a nota vizinha na beirada dela exige persistência.
class PitchTracker {
  int onsetFrames;
  final int medianSize;
  final int dropAfterMisses;

  /// Tolerância (cents) em volta da nota travada: o som pode variar até aqui
  /// (vibrato, mão esquerda não temperada) sem virar a nota vizinha.
  final double hysteresisCents;

  /// Trocar para uma nota VIZINHA (a 1 semitom) quando o som está na beirada dela
  /// (a mais de [edgeCents] do centro) exige essa quantidade de leituras seguidas.
  /// É o que separa o vibrato (passa pela beirada e volta) de uma troca de nota
  /// (pousa perto do centro e troca na hora).
  final int neighborFrames;
  final double edgeCents;

  final List<double> _midiRing = [];
  int _misses = 0;
  final List<double> _outliers = []; // leituras fora do lugar em sequência
  int? _candidate;
  int _candidateCount = 0;
  int? _locked;

  PitchTracker(
      {this.onsetFrames = 3,
      this.medianSize = 5,
      this.dropAfterMisses = 5,
      this.hysteresisCents = 75,
      this.neighborFrames = 8,
      this.edgeCents = 25});

  void reset() {
    _midiRing.clear();
    _misses = 0;
    _outliers.clear();
    _candidate = null;
    _candidateCount = 0;
    _locked = null;
  }

  TrackedNote? update(PitchResult? r, TuningConfig cfg) {
    if (r == null) {
      _misses++;
      if (_misses >= dropAfterMisses) reset();
      return null;
    }
    _misses = 0;
    final m = freqToMidi(r.frequency, cfg.refA);

    // Leitura fora do lugar (ex.: erro de oitava de um quadro ou NOTA NOVA).
    // Duas leituras seguidas que concordam entre si já são uma nota nova: assim
    // notas rápidas aparecem logo (antes eram precisos 3 quadros mais o filtro
    // de ataque). Três que não concordam também trocam, como antes.
    // Mas leitura DENTRO da região da nota travada (vibrato, mão não temperada) não
    // é nota nova: o vibrato balança mais rápido que a mediana acompanha.
    final lk0 = _locked;
    final inRegion = lk0 != null &&
        centsBetween(r.frequency, targetFreq(lk0, cfg)).abs() <= hysteresisCents;
    if (_midiRing.length >= 3 && !inRegion) {
      final med = _median(_midiRing);
      if ((m - med).abs() > 0.6) {
        _outliers.add(m);
        final k = _outliers.length;
        final agree = k >= 2 && (_outliers[k - 1] - _outliers[k - 2]).abs() < 0.5;
        if (!agree && k < 3) return null;
        final seed = agree ? _outliers[k - 2] : null;
        _midiRing.clear();
        _locked = null;
        _candidate = null;
        _candidateCount = 0;
        if (seed != null) {
          _midiRing.add(seed);
          _candidate = nearestTarget(etFreq(seed, cfg.refA), cfg).midi;
          _candidateCount = 1;
        }
        _outliers.clear();
      } else {
        _outliers.clear();
      }
    }
    _midiRing.add(m);
    if (_midiRing.length > medianSize) _midiRing.removeAt(0);

    final smoothMidi = _median(_midiRing);
    final smoothFreq = etFreq(smoothMidi, cfg.refA);
    var match = nearestTarget(smoothFreq, cfg);

    // Histerese
    final lk = _locked;
    if (lk != null && lk != match.midi) {
      final t = targetFreq(lk, cfg);
      final c = centsBetween(smoothFreq, t);
      if (c.abs() <= hysteresisCents) match = NoteMatch(lk, t, c);
    }

    if (_candidate == match.midi) {
      _candidateCount++;
    } else {
      _candidate = match.midi;
      _candidateCount = 1;
    }
    // Vizinha na beirada (provável vibrato): só troca se persistir. Enquanto isso
    // continua mostrando a nota travada, com o desvio real (que pode ser grande).
    final lk2 = _locked;
    if (lk2 != null &&
        match.midi != lk2 &&
        (match.midi - lk2).abs() == 1 &&
        match.cents.abs() > edgeCents &&
        _candidateCount < neighborFrames) {
      final t = targetFreq(lk2, cfg);
      return TrackedNote(lk2, smoothFreq, t, centsBetween(smoothFreq, t), r.clarity);
    }
    if (_candidateCount < onsetFrames) return null;
    _locked = match.midi;
    return TrackedNote(
        match.midi, smoothFreq, match.target, match.cents, r.clarity);
  }

  static double _median(List<double> v) {
    final s = List<double>.of(v)..sort();
    final n = s.length;
    return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
  }
}

// ---------------------------------------------------------------------------
// Grade
// ---------------------------------------------------------------------------

enum HistoryMode {
  short(1),
  medium(3),
  long(30),
  unlimited(double.infinity);

  final double seconds;
  const HistoryMode(this.seconds);
}

/// Faixa considerada "afinada" (±cents): um padrão só, igual para todo mundo. O
/// app é a referência do músico; não há níveis (iniciante/avançado) que afrouxem
/// ou apertem a régua.
const double kInTuneCents = 10;

class CellView {
  final double avgCents;

  /// 0..1: quanto já se tocou nessa nota (cor mais firme).
  final double confidence;

  /// 0..1: visibilidade (cai a 0 depois do tempo de retenção).
  final double alpha;
  final double seconds;

  /// Segundos desde a última vez que a nota soou (0 = soando agora).
  final double age;

  /// Quantas vezes a nota foi tocada (uma nova vez depois de uma pausa na nota).
  final int plays;
  const CellView(this.avgCents, this.confidence, this.alpha, this.seconds,
      [this.age = 0, this.plays = 1]);
}

/// Resumo da sessão: quantas notas foram tocadas e quantas ficaram afinadas.
class GridSummary {
  /// Total de vezes que alguma nota foi tocada.
  final int notes;

  /// Notas diferentes tocadas (quadrados coloridos).
  final int distinct;

  /// Dessas, quantas estão com a média dentro da faixa afinada.
  final int inTune;
  const GridSummary(this.notes, this.distinct, this.inTune);

  /// 0..1 (0 se nada foi tocado).
  double get accuracy => distinct == 0 ? 0 : inTune / distinct;
}

class _Cell {
  double sum = 0;
  double w = 0;
  double seconds = 0;
  double lastSeen = double.negativeInfinity;
  int plays = 0;
}

class PitchGrid {
  HistoryMode history;

  /// Quanto tempo a cor fica visível depois que a nota para (s). null = sempre.
  double? holdSeconds;
  final double fadeSeconds;
  final Map<int, _Cell> _cells = {};

  PitchGrid(
      {this.history = HistoryMode.medium,
      this.holdSeconds = 30,
      this.fadeSeconds = 3});

  void clear() => _cells.clear();

  /// Registra [dt] segundos tocando [midi] com desvio [cents].
  void add(int midi, double cents, double clarity, double dt, double now) {
    final c = _cells.putIfAbsent(midi, _Cell.new);
    // Nova "tocada": primeira vez, ou voltou à nota depois de uma pausa.
    // (Se o aparelho engasgou e os quadros vieram espaçados, o intervalo cresce
    // junto com [dt] e não conta como nota nova.)
    final newPlay = !c.lastSeen.isFinite || now - c.lastSeen > math.max(replayGap, dt * 2.5);
    if (newPlay) c.plays++;
    final tau = history.seconds;
    // Memória curta/média: tocar a nota de novo depois de uma pausa recomeça a média.
    // Sem isso, os segundos de afinação (cravelha ainda baixa) pesavam mais que a
    // tocada nova e o Sol já afinado seguia aparecendo "baixo". Nas memórias longa e
    // sem limite o histórico continua valendo de propósito.
    if (newPlay && c.lastSeen.isFinite && tau <= 3) {
      c.sum *= 0.05;
      c.w *= 0.05;
    }
    if (c.lastSeen.isFinite && tau.isFinite) {
      final f = math.exp(-(now - c.lastSeen) / tau);
      c.sum *= f;
      c.w *= f;
    }
    final weight = clarity * dt;
    c.sum += cents.clamp(-100.0, 100.0) * weight;
    c.w += weight;
    c.seconds += dt;
    c.lastSeen = now;
  }

  CellView? view(int midi, double now) {
    final c = _cells[midi];
    if (c == null || c.w <= 0) return null;
    var alpha = 1.0;
    final hold = holdSeconds;
    if (hold != null) {
      final since = now - c.lastSeen;
      if (since > hold) {
        alpha = 1 - (since - hold) / fadeSeconds;
        if (alpha <= 0) return null;
      }
    }
    return CellView(c.sum / c.w, 1 - math.exp(-c.w / 0.5), alpha.clamp(0.0, 1.0), c.seconds,
        math.max(0.0, now - c.lastSeen), math.max(1, c.plays));
  }

  Iterable<int> get playedMidis => _cells.keys;

  /// Pausa (s) a partir da qual voltar à mesma nota conta como outra tocada.
  static const double replayGap = 0.45;

  /// Total de notas tocadas e quantas estão afinadas, olhando a sessão inteira
  /// (ignora o tempo de retenção da cor).
  GridSummary summary(double zoneCents) {
    var notes = 0, distinct = 0, ok = 0;
    for (final c in _cells.values) {
      if (c.w <= 0) continue;
      distinct++;
      notes += math.max(1, c.plays);
      if ((c.sum / c.w).abs() <= zoneCents) ok++;
    }
    return GridSummary(notes, distinct, ok);
  }
}

// ---------------------------------------------------------------------------
// Escalas e relatório
// ---------------------------------------------------------------------------

enum ScaleType {
  major('Maior', [0, 2, 4, 5, 7, 9, 11]),
  naturalMinor('Menor natural', [0, 2, 3, 5, 7, 8, 10]),
  harmonicMinor('Menor harmônica', [0, 2, 3, 5, 7, 8, 11]),

  /// Sobe com 6ª e 7ª maiores e desce como menor natural (como se estuda).
  melodicMinor('Menor melódica', [0, 2, 3, 5, 7, 9, 11], down: [0, 2, 3, 5, 7, 8, 10]),
  majorPentatonic('Pentatônica maior', [0, 2, 4, 7, 9]),
  chromatic('Cromática', [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]),

  // ---- Arpejos (família do "sistema de escalas" de Carl Flesch) ----
  // Tríades em posição fundamental e nas duas inversões, 7ª da dominante e 7ª
  // diminuta, em 1, 2 e 3 oitavas. A "tônica" escolhida é a RAIZ do acorde; nas
  // inversões o exercício começa na 3ª ou na 5ª (campo [start]).
  majorTriad('Arpejo maior', [0, 4, 7],
      arpeggio: true,
      hint: 'Tríade maior: 1ª, 3ª e 5ª notas. Comece em 1 oitava e aumente para 2 e 3.'),
  minorTriad('Arpejo menor', [0, 3, 7],
      arpeggio: true,
      hint: 'Tríade menor: a 3ª é mais baixa que no arpejo maior (meio tom).'),
  majorTriad1('Arpejo maior (1ª inversão)', [0, 3, 8],
      start: 4,
      arpeggio: true,
      hint: 'Começa na 3ª do acorde (ex.: Mi–Sol–Dó em Dó maior).'),
  minorTriad1('Arpejo menor (1ª inversão)', [0, 4, 9],
      start: 3,
      arpeggio: true,
      hint: 'Começa na 3ª do acorde (ex.: Mi♭–Sol–Dó em Dó menor).'),
  majorTriad2('Arpejo maior (2ª inversão)', [0, 5, 9],
      start: 7,
      arpeggio: true,
      hint: 'Começa na 5ª do acorde (ex.: Sol–Dó–Mi em Dó maior).'),
  minorTriad2('Arpejo menor (2ª inversão)', [0, 5, 8],
      start: 7,
      arpeggio: true,
      hint: 'Começa na 5ª do acorde (ex.: Sol–Dó–Mi♭ em Dó menor).'),
  dominantSeventh('Arpejo de 7ª da dominante', [0, 4, 7, 10],
      arpeggio: true,
      hint: 'Tríade maior com 7ª menor: 4 notas por oitava; cuidado com a 7ª, que tende a ficar alta.'),
  diminishedSeventh('Arpejo de 7ª diminuta', [0, 3, 6, 9],
      arpeggio: true,
      hint: 'Quatro notas igualmente espaçadas (terças menores): afine cada intervalo de ouvido.');

  final String label;

  /// Graus ao SUBIR (semitons acima da nota inicial do exercício).
  final List<int> steps;

  /// Graus ao DESCER (igual aos de subida, exceto na menor melódica).
  final List<int> downSteps;

  /// Semitons entre a tônica (raiz) e a primeira nota do exercício (inversões).
  final int start;

  /// true = arpejo (acorde quebrado), false = escala.
  final bool arpeggio;

  /// Dica de estudo mostrada ao escolher o tipo.
  final String hint;

  const ScaleType(this.label, this.steps,
      {List<int>? down, this.start = 0, this.arpeggio = false, this.hint = ''})
      : downSteps = down ?? steps;

  /// Só as escalas / só os arpejos (para os seletores).
  static List<ScaleType> get scales => [for (final t in values) if (!t.arpeggio) t];
  static List<ScaleType> get arpeggios => [for (final t in values) if (t.arpeggio) t];

  /// Nome para mostrar: "Sol menor natural" (escala) ou "Arpejo maior de Sol".
  String display(String note) => arpeggio ? '$label de $note' : '$note ${label.toLowerCase()}';
}

/// Notas do exercício subindo [octaves] oitavas, terminando na nota de chegada
/// (uma oitava acima da inicial, no fim da última oitava).
List<int> scaleMidis(int tonicMidi, ScaleType t, {int octaves = 1}) {
  final base = tonicMidi + t.start;
  final out = <int>[];
  for (var o = 0; o < octaves; o++) {
    for (final s in t.steps) {
      out.add(base + 12 * o + s);
    }
  }
  out.add(base + 12 * octaves);
  return out;
}

enum NoteStatus { notPlayed, inTune, flat, sharp }

class NoteReport {
  final int midi;
  final String name;
  final NoteStatus status;
  final double? avgCents;
  final double seconds;
  const NoteReport(this.midi, this.name, this.status, this.avgCents, this.seconds);
}

class ScaleReport {
  final List<NoteReport> notes;
  const ScaleReport(this.notes);

  int get played => notes.where((n) => n.status != NoteStatus.notPlayed).length;
  int get inTune => notes.where((n) => n.status == NoteStatus.inTune).length;

  /// Porcentagem de notas afinadas entre as tocadas (0 se nada foi tocado).
  double get accuracy => played == 0 ? 0 : inTune / played;
}

ScaleReport buildScaleReport(PitchGrid grid, List<int> midis, TuningConfig cfg,
    double zoneCents, double now) {
  final reports = <NoteReport>[];
  for (final m in midis) {
    // O relatório ignora a retenção: usa o que foi acumulado.
    final saved = grid.holdSeconds;
    grid.holdSeconds = null;
    final v = grid.view(m, now);
    grid.holdSeconds = saved;
    final name = noteName(m, cfg, withOctave: true);
    if (v == null || v.seconds < 0.15) {
      reports.add(NoteReport(m, name, NoteStatus.notPlayed, null, 0));
      continue;
    }
    final st = v.avgCents.abs() <= zoneCents
        ? NoteStatus.inTune
        : (v.avgCents < 0 ? NoteStatus.flat : NoteStatus.sharp);
    reports.add(NoteReport(m, name, st, v.avgCents, v.seconds));
  }
  return ScaleReport(reports);
}
