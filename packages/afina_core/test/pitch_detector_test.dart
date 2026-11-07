import 'dart:math' as math;

import 'package:afina_core/pitch_detector.dart';
import 'package:afina_core/tuning.dart';
import 'package:test/test.dart';

/// Gera um tom com harmônicos [amps] (índice 0 = fundamental).
List<double> tone(double f, int sr, int n,
    {List<double> amps = const [1.0],
    double noise = 0,
    double vibCents = 0,
    double vibHz = 5.5,
    int seed = 1}) {
  final rnd = math.Random(seed);
  final out = List<double>.filled(n, 0);
  var phase = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i / sr;
    final fi = f * math.pow(2, vibCents * math.sin(2 * math.pi * vibHz * t) / 1200);
    phase += 2 * math.pi * fi / sr;
    var s = 0.0;
    for (var h = 0; h < amps.length; h++) {
      s += amps[h] * math.sin((h + 1) * phase);
    }
    out[i] = 0.3 * s / amps.reduce((a, b) => a + b);
    if (noise > 0) out[i] += noise * (rnd.nextDouble() * 2 - 1);
  }
  return out;
}

double errCents(double got, double want) => centsBetween(got, want);

void main() {
  const violinTimbre = [1.0, 0.8, 0.6, 0.45, 0.3, 0.2, 0.12];

  for (final sr in [44100, 48000]) {
    group('sr=$sr tons limpos', () {
      final det = McLeodPitchDetector(sampleRate: sr);
      // contrabaixo E1 .. violino E6
      final freqs = <String, double>{
        'E1 contrabaixo': 41.2034,
        'C2 cello': 65.4064,
        'E2 violão': 82.4069,
        'G3 violino': 195.5556,
        'A4': 440.0,
        'E5 violino': 660.0,
        'A5': 880.0,
        'E6': 1318.51,
      };
      freqs.forEach((name, f) {
        test('$name (${f.toStringAsFixed(2)} Hz) senoide', () {
          final r = det.detect(tone(f, sr, 4096));
          expect(r, isNotNull);
          expect(errCents(r!.frequency, f).abs(), lessThan(0.5));
        });
        test('$name timbre de violino (harmônicos fortes)', () {
          final r = det.detect(tone(f, sr, 4096, amps: violinTimbre));
          expect(r, isNotNull);
          expect(errCents(r!.frequency, f).abs(), lessThan(0.5));
        });
      });
    });
  }

  group('casos difíceis', () {
    final det = McLeodPitchDetector(sampleRate: 44100);

    test('fundamental fraca (2º harmônico dominante) não vira oitava acima', () {
      final r = det.detect(tone(220, 44100, 4096,
          amps: const [0.25, 1.0, 0.7, 0.4, 0.2]));
      expect(r, isNotNull);
      expect(errCents(r!.frequency, 220).abs(), lessThan(1));
    });

    test('3º harmônico mais forte que a fundamental', () {
      final r = det.detect(tone(196, 44100, 4096,
          amps: const [0.4, 0.6, 1.0, 0.5, 0.3]));
      expect(r, isNotNull);
      expect(errCents(r!.frequency, 196).abs(), lessThan(1));
    });

    test('ruído branco moderado (SNR ~ 20 dB)', () {
      for (final f in [196.0, 440.0, 659.26]) {
        final r = det.detect(
            tone(f, 44100, 4096, amps: violinTimbre, noise: 0.03, seed: 7));
        expect(r, isNotNull, reason: '$f');
        expect(errCents(r!.frequency, f).abs(), lessThan(2), reason: '$f');
      }
    });

    test('vibrato de ±20 cents: cada janela fica dentro da amplitude e a '
        'média no tempo cai no centro (< 3 cents)', () {
      // Uma janela de 93 ms cobre só meio ciclo de vibrato (5,5 Hz), então
      // uma leitura isolada acompanha o vibrato. A média no tempo é que
      // representa a nota (é o que a grade de entonação faz).
      final sig = tone(440, 44100, 44100 * 2,
          amps: violinTimbre, vibCents: 20);
      final errs = <double>[];
      for (var start = 0; start + 4096 <= sig.length; start += 1024) {
        final r = det.detect(sig.sublist(start, start + 4096));
        expect(r, isNotNull);
        errs.add(errCents(r!.frequency, 440));
      }
      for (final e in errs) {
        expect(e.abs(), lessThan(24));
      }
      final mean = errs.reduce((a, b) => a + b) / errs.length;
      expect(mean.abs(), lessThan(3));
    });

    test('silêncio e ruído puro não geram nota', () {
      expect(det.detect(List.filled(4096, 0.0)), isNull);
      final rnd = math.Random(3);
      final noise = List.generate(4096, (_) => (rnd.nextDouble() * 2 - 1) * 0.2);
      expect(det.detect(noise), isNull);
    });

    test('varredura de 50 desafinações finas: erro máximo < 0.5 cents', () {
      var maxErr = 0.0;
      for (var i = 0; i < 50; i++) {
        final cents = -49.0 + i * 2;
        final f = 440 * math.pow(2, cents / 1200).toDouble();
        final r = det.detect(tone(f, 44100, 4096, amps: violinTimbre));
        expect(r, isNotNull);
        maxErr = math.max(maxErr, errCents(r!.frequency, f).abs());
      }
      expect(maxErr, lessThan(0.5));
    });
  });

  test('modo livre: pega nota fraca e ruidosa que o rigoroso descarta', () {
    final strict = McLeodPitchDetector(
        sampleRate: 44100, minClarity: 0.88, minRms: 0.006);
    final free = McLeodPitchDetector(
        sampleRate: 44100, minClarity: 0.55, minRms: 0.0008);
    // nota fraca (amplitude ~0.01) e com bastante ruído
    final sig = tone(330, 44100, 4096, amps: const [1.0, 0.6, 0.3], noise: 0.04, seed: 5)
        .map((v) => v * 0.012)
        .toList();
    expect(strict.detect(sig), isNull);
    final r = free.detect(sig);
    expect(r, isNotNull);
    expect(errCents(r!.frequency, 330).abs(), lessThan(15));
  });

  test('desempenho: janela de 4096 em menos de 25 ms (média)', () {
    final det = McLeodPitchDetector(sampleRate: 44100);
    final buf = tone(110, 44100, 4096, amps: violinTimbre);
    det.detect(buf); // aquecimento
    final sw = Stopwatch()..start();
    for (var i = 0; i < 20; i++) {
      det.detect(buf);
    }
    final ms = sw.elapsedMicroseconds / 20 / 1000;
    // ignore: avoid_print
    print('tempo médio por detecção: ${ms.toStringAsFixed(2)} ms');
    expect(ms, lessThan(25));
  });
}
