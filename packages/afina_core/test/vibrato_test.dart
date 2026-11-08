import 'dart:math' as math;

import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

const sr = 44100;
const cfg = TuningConfig();

/// Violino sintético: segue [midis] (cada um por [noteMs]) com [centerCents] de
/// desvio médio e vibrato de ±[depth] cents a [rate] Hz.
List<double> violin(List<int> midis, double noteMs,
    {double centerCents = 0, double depth = 0, double rate = 5.5, int seed = 5}) {
  final rnd = math.Random(seed);
  final per = (sr * noteMs / 1000).round();
  final out = List<double>.filled(per * midis.length, 0);
  var phase = 0.0;
  const amps = [1.0, 0.7, 0.5, 0.35, 0.2, 0.12];
  for (var i = 0; i < out.length; i++) {
    final k = i ~/ per;
    final t = i / sr;
    // O vibrato começa suave (0,4 s), como no violino de verdade.
    final ramp = math.min(1.0, (i % per) / sr / 0.4);
    final c = centerCents + ramp * depth * math.sin(2 * math.pi * rate * t);
    final f = etFreq(midis[k].toDouble(), 440) * math.pow(2, c / 1200);
    phase += 2 * math.pi * f / sr;
    var s = 0.0;
    for (var h = 0; h < amps.length; h++) {
      s += amps[h] * math.sin((h + 1) * phase);
    }
    out[i] = 0.12 * s + 0.002 * (rnd.nextDouble() * 2 - 1);
  }
  return out;
}

/// Passa o sinal pela cadeia real e devolve as notas emitidas (midi) por quadro.
List<int> emitted(List<double> sig, PitchTracker tracker) {
  final p = DetectorProfile.forLowest(etFreq(55, 440)); // violino
  final det = AdaptiveWindowDetector.forProfile(p)
    ..minClarity = 0.72
    ..minRms = 0.0018;
  final out = <int>[];
  for (var end = p.window; end <= sig.length; end += p.hop) {
    final n = tracker.update(det.detect(sig.sublist(end - p.window, end)), cfg);
    if (n != null) out.add(n.midi);
  }
  return out;
}

void main() {
  group('vibrato e mão esquerda não temperada', () {
    test('vibrato largo com centro um pouco alto não vira a nota vizinha', () {
      // Lá4 com centro +10¢ e vibrato de ±60¢: o som chega a +70¢ e a -50¢.
      final sig = violin([69], 1500, centerCents: 10, depth: 60);
      final novo = emitted(sig, PitchTracker(onsetFrames: 2));
      final velho = emitted(
          sig,
          PitchTracker(
              onsetFrames: 2, hysteresisCents: 65, neighborFrames: 0)); // regra antiga
      final foraNovo = novo.where((m) => m != 69).length;
      final foraVelho = velho.where((m) => m != 69).length;
      // ignore: avoid_print
      print('vibrato ±60¢: notas erradas antes $foraVelho, agora $foraNovo '
          '(de ${novo.length} quadros)');
      expect(foraNovo, 0);
      expect(novo.length, greaterThan(40));
      expect(foraVelho, greaterThanOrEqualTo(foraNovo));
    });

    test('vibrato comum (±30¢) em várias notas fica na nota', () {
      for (final midi in [55, 62, 69, 76]) {
        final sig = violin([midi], 1200, centerCents: -5, depth: 30);
        final got = emitted(sig, PitchTracker(onsetFrames: 2));
        expect(got.where((m) => m != midi).length, 0, reason: 'nota $midi');
        expect(got.length, greaterThan(30));
      }
    });

    test('trinado de semitom (dedo 1 e 2) continua trocando rápido', () {
      // Lá4 <-> Lá♯4, 125 ms cada, com a afinação centrada em cada nota.
      const seq = [69, 70, 69, 70, 69, 70, 69, 70];
      final sig = violin(seq, 125);
      final got = emitted(sig, PitchTracker(onsetFrames: 2));
      final changes = [for (var i = 1; i < got.length; i++) if (got[i] != got[i - 1]) 1].length;
      expect(got.toSet(), {69, 70});
      expect(changes, greaterThanOrEqualTo(6)); // viu (quase) todas as 7 trocas
    });

    test('semitom desafinado 20¢ baixo troca de nota; 40¢ baixo fica na nota de baixo (60¢ alta)', () {
      // Si♭ 20¢ baixo = Lá +80¢: já é mais Si♭ que Lá, então troca.
      final a = emitted([
        ...violin([69], 500),
        ...violin([70], 500, centerCents: -20),
      ], PitchTracker(onsetFrames: 2));
      expect(a.last, 70);
      // Si♭ 40¢ baixo = Lá +60¢: ambíguo, dentro da tolerância do Lá (mostra Lá, agudo).
      final b = emitted([
        ...violin([69], 500),
        ...violin([70], 500, centerCents: -40),
      ], PitchTracker(onsetFrames: 2));
      expect(b.last, 69);
    });
  });
}
