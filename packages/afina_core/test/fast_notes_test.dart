import 'dart:math' as math;

import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

const sr = 44100;
const cfg = TuningConfig();

/// Sinal de violino sintético: escala de Sol maior (Sol3 a Sol4) com notas de
/// [noteMs] cada, ligadas (sem pausa), com vibrato e um pouco de ruído.
({List<double> signal, List<int> notes}) fastScale(double noteMs, {int seed = 3}) {
  const midis = [55, 57, 59, 60, 62, 64, 66, 67, 66, 64, 62, 60, 59, 57, 55];
  final rnd = math.Random(seed);
  final per = (sr * noteMs / 1000).round();
  final out = List<double>.filled(per * midis.length + sr ~/ 4, 0);
  var phase = 0.0;
  const amps = [1.0, 0.7, 0.5, 0.35, 0.2, 0.12];
  for (var i = 0; i < out.length; i++) {
    final k = math.min(midis.length - 1, i ~/ per);
    final f = etFreq(midis[k].toDouble(), 440);
    final t = i / sr;
    final fi = f * math.pow(2, 6 * math.sin(2 * math.pi * 5.5 * t) / 1200);
    phase += 2 * math.pi * fi / sr;
    var s = 0.0;
    for (var h = 0; h < amps.length; h++) {
      s += amps[h] * math.sin((h + 1) * phase);
    }
    final fade = i >= per * midis.length ? 0.0 : 1.0;
    out[i] = fade * 0.12 * s + 0.002 * (rnd.nextDouble() * 2 - 1);
  }
  return (signal: out, notes: midis);
}

/// Passa o sinal pela cadeia real (detector em janelas deslizantes + estabilizador)
/// e devolve a fração de notas reconhecidas e a latência média (ms).
({double recall, double latencyMs, int falseNotes}) run(
    List<double> signal, List<int> notes, double noteMs,
    {required int window,
    required int hop,
    required double minFreq,
    int onset = 2,
    bool adaptive = false}) {
  final det = McLeodPitchDetector(
      sampleRate: sr, windowSize: window, minFreq: minFreq, maxFreq: 3200, minClarity: 0.8, minRms: 0.003);
  final adet = AdaptiveWindowDetector.forProfile(DetectorProfile(window, hop, minFreq, 3200))
    ..minClarity = 0.8
    ..minRms = 0.003;
  final tracker = PitchTracker(onsetFrames: onset);
  final per = sr * noteMs / 1000;
  final firstSeen = <int, double>{}; // índice da nota -> instante (ms) da 1ª emissão
  var falseNotes = 0;
  for (var end = window; end <= signal.length; end += hop) {
    final buf = signal.sublist(end - window, end);
    final n = tracker.update(adaptive ? adet.detect(buf) : det.detect(buf), cfg);
    if (n == null) continue;
    final tMs = end * 1000 / sr;
    final idx = (end - window / 2) ~/ per; // nota que domina o centro da janela
    // procura o índice de nota correspondente ao midi emitido, perto de agora
    var matched = -1;
    for (var k = math.max(0, (tMs * sr / 1000 / per).floor() - 1);
        k <= math.min(notes.length - 1, (tMs * sr / 1000 / per).floor());
        k++) {
      if (notes[k] == n.midi) matched = k;
    }
    if (matched >= 0) {
      firstSeen.putIfAbsent(matched, () => tMs);
    } else if (idx < notes.length) {
      falseNotes++;
    }
  }
  var rec = 0, lat = 0.0;
  firstSeen.forEach((k, t) {
    rec++;
    lat += t - k * noteMs;
  });
  return (recall: rec / notes.length, latencyMs: rec == 0 ? 0 : lat / rec, falseNotes: falseNotes);
}

void main() {
  final violin = DetectorProfile.forLowest(etFreq(55, 440)); // Sol3
  test('perfil do violino: janela curta, passo curto e faixa estreita', () {
    expect(violin.window, 2048);
    expect(violin.hop, lessThanOrEqualTo(512));
    expect(violin.minFreq, closeTo(157, 1));
  });

  test('perfil de instrumentos graves usa janela maior; nunca passa de 4096', () {
    expect(DetectorProfile.forLowest(etFreq(36, 440)).window, 4096); // Dó2 (violoncelo)
    expect(DetectorProfile.forLowest(etFreq(28, 440)).window, 4096); // Mi1 (contrabaixo)
    expect(DetectorProfile.forLowest(etFreq(48, 440)).window, 2048); // Dó3 (viola)
  });

  for (final ms in [180.0, 125.0, 100.0]) {
    test('janela adaptativa, notas de ${ms.round()} ms: mais rápida e igual de confiável', () {
      final s = fastScale(ms);
      final fixed = run(s.signal, s.notes, ms,
          window: violin.window, hop: violin.hop, minFreq: violin.minFreq);
      final ad = run(s.signal, s.notes, ms,
          window: violin.window, hop: violin.hop, minFreq: violin.minFreq, adaptive: true);
      // ignore: avoid_print
      print('${ms.round()} ms: janela fixa ${(fixed.recall * 100).round()}% / ${fixed.latencyMs.round()} ms'
          ' -> adaptativa ${(ad.recall * 100).round()}% / ${ad.latencyMs.round()} ms (falsas ${ad.falseNotes})');
      expect(ad.recall, greaterThanOrEqualTo(fixed.recall));
      expect(ad.falseNotes, 0);
      expect(ad.latencyMs, lessThan(fixed.latencyMs - 5));
    });
  }

  for (final ms in [250.0, 180.0, 125.0, 100.0]) {
    test('notas de ${ms.round()} ms: antes (janela 4096) × agora (perfil do violino)', () {
      final s = fastScale(ms);
      final old = run(s.signal, s.notes, ms, window: 4096, hop: 1536, minFreq: 40);
      final now = run(s.signal, s.notes, ms,
          window: violin.window, hop: violin.hop, minFreq: violin.minFreq);
      // ignore: avoid_print
      print('${ms.round()} ms: antes (janela 4096, com o estabilizador novo) ${(old.recall * 100).round()}% / ${old.latencyMs.round()} ms'
          ' -> agora ${(now.recall * 100).round()}% / ${now.latencyMs.round()} ms (falsas ${now.falseNotes})');
      expect(now.recall, greaterThanOrEqualTo(old.recall));
      expect(now.latencyMs, lessThanOrEqualTo(old.latencyMs));
      expect(now.falseNotes, 0);
      if (ms >= 125) expect(now.recall, greaterThanOrEqualTo(0.9));
    });
  }
}
