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
///  - histerese: perto do limite entre duas notas, mantém a atual (±65¢).
class PitchTracker {
  int onsetFrames;
  final int medianSize;
  final int dropAfterMisses;

  final List<double> _midiRing = [];
  int _misses = 0;
  int _outlierRun = 0;
  int? _candidate;
  int _candidateCount = 0;
  int? _locked;

  PitchTracker(
      {this.onsetFrames = 3, this.medianSize = 5, this.dropAfterMisses = 4});

  void reset() {
    _midiRing.clear();
    _misses = 0;
    _outlierRun = 0;
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

    // Rejeição de outlier (ex.: erro de oitava de um quadro).
    if (_midiRing.length >= 3) {
      final med = _median(_midiRing);
      if ((m - med).abs() > 0.6) {
        _outlierRun++;
        if (_outlierRun < 3) return null;
        // 3 quadros seguidos em outro lugar: é uma nota nova.
        _midiRing.clear();
        _candidate = null;
        _candidateCount = 0;
        _locked = null;
      } else {
        _outlierRun = 0;
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
      if (c.abs() <= 65) match = NoteMatch(lk, t, c);
    }

    if (_candidate == match.midi) {
      _candidateCount++;
    } else {
      _candidate = match.midi;
      _candidateCount = 1;
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

/// Faixa considerada "afinada" (±cents).
enum ZoneLevel {
  beginner(10),
  intermediate(5),
  advanced(3);

  final double cents;
  const ZoneLevel(this.cents);
}

class CellView {
  final double avgCents;

  /// 0..1: quanto já se tocou nessa nota (cor mais firme).
  final double confidence;

  /// 0..1: visibilidade (cai a 0 depois do tempo de retenção).
  final double alpha;
  final double seconds;
  const CellView(this.avgCents, this.confidence, this.alpha, this.seconds);
}

class _Cell {
  double sum = 0;
  double w = 0;
  double seconds = 0;
  double lastSeen = double.negativeInfinity;
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
    final tau = history.seconds;
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
    return CellView(
        c.sum / c.w, 1 - math.exp(-c.w / 0.5), alpha.clamp(0.0, 1.0), c.seconds);
  }

  Iterable<int> get playedMidis => _cells.keys;
}

// ---------------------------------------------------------------------------
// Escalas e relatório
// ---------------------------------------------------------------------------

enum ScaleType {
  major('Maior', [0, 2, 4, 5, 7, 9, 11]),
  naturalMinor('Menor natural', [0, 2, 3, 5, 7, 8, 10]),
  harmonicMinor('Menor harmônica', [0, 2, 3, 5, 7, 8, 11]),

  /// Sobe com 6ª e 7ª maiores e desce como menor natural (como se estuda).
  melodicMinor('Menor melódica', [0, 2, 3, 5, 7, 9, 11], [0, 2, 3, 5, 7, 8, 10]),
  majorPentatonic('Pentatônica maior', [0, 2, 4, 7, 9]),
  chromatic('Cromática', [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);

  final String label;

  /// Graus ao SUBIR (semitons acima da tônica).
  final List<int> steps;

  /// Graus ao DESCER (igual aos de subida, exceto na menor melódica).
  final List<int> downSteps;
  const ScaleType(this.label, this.steps, [List<int>? down])
      : downSteps = down ?? steps;
}

/// Notas da escala subindo [octaves] oitavas, terminando na tônica.
List<int> scaleMidis(int tonicMidi, ScaleType t, {int octaves = 1}) {
  final out = <int>[];
  for (var o = 0; o < octaves; o++) {
    for (final s in t.steps) {
      out.add(tonicMidi + 12 * o + s);
    }
  }
  out.add(tonicMidi + 12 * octaves);
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
    ZoneLevel zone, double now) {
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
    final st = v.avgCents.abs() <= zone.cents
        ? NoteStatus.inTune
        : (v.avgCents < 0 ? NoteStatus.flat : NoteStatus.sharp);
    reports.add(NoteReport(m, name, st, v.avgCents, v.seconds));
  }
  return ScaleReport(reports);
}
