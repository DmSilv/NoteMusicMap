import 'dart:math' as math;
import 'dart:typed_data';

import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  group('frequência exata', () {
    // Do contrabaixo ao violino agudo, e referências de orquestra.
    for (final f in [41.2034, 65.4064, 82.4069, 195.5556, 293.3333, 440.0, 442.0, 523.25, 660.0, 880.0, 1318.51, 2000.0]) {
      test('${f.toStringAsFixed(2)} Hz: erro de laço < 0,05 cent e duração <= 2 s', () {
        final t = buildToneLoop(f);
        expect(t.centsError(f).abs(), lessThan(0.05));
        expect(t.samples.length / t.sampleRate, lessThanOrEqualTo(2.0));
        expect(t.samples.length, greaterThan(8));
      });
    }
  });

  test('o laço fecha sem salto: a amostra seguinte à última é a primeira', () {
    for (final f in [440.0, 293.3333, 195.5556, 659.2551]) {
      for (final tb in ToneTimbre.values) {
        final t = buildToneLoop(f, timbre: tb);
        final n = t.samples.length;
        // Continuação natural: a amostra "n" (= a 0) deve seguir a n-1 sem degrau
        // maior que o passo típico do sinal.
        final a = t.samples[n - 1], b = t.samples[0], c = t.samples[1];
        final stepInside = (c - b).abs();
        final stepAcrossLoop = (b - a).abs();
        expect(stepAcrossLoop, lessThanOrEqualTo(stepInside * 1.6 + 1e-3),
            reason: '$f Hz $tb: degrau na emenda $stepAcrossLoop vs $stepInside');
        expect(b.abs(), lessThan(1e-9)); // começa em fase zero
      }
    }
  });

  test('o pico fica em 0,9 e nunca passa de 1', () {
    for (final tb in ToneTimbre.values) {
      final t = buildToneLoop(440, timbre: tb);
      var peak = 0.0;
      for (final s in t.samples) {
        if (s.abs() > peak) peak = s.abs();
      }
      expect(peak, closeTo(0.9, 0.01));
    }
  });

  test('o diapasão é senoide pura: sem harmônicos', () {
    final t = buildToneLoop(440, timbre: ToneTimbre.fork);
    // Projeta no 1º e 2º harmônico (DFT em um ciclo inteiro de laço).
    double amp(int h) {
      var re = 0.0, im = 0.0;
      final n = t.samples.length;
      for (var i = 0; i < n; i++) {
        final ph = 2 * math.pi * t.cycles * h * i / n;
        re += t.samples[i] * math.cos(ph);
        im += t.samples[i] * math.sin(ph);
      }
      return 2 * math.sqrt(re * re + im * im) / n;
    }

    expect(amp(1), closeTo(0.9, 0.01));
    expect(amp(2), lessThan(0.005));
    expect(amp(3), lessThan(0.005));
  });

  test('o timbre suave tem harmônicos, mas bem menores que a fundamental', () {
    final t = buildToneLoop(440, timbre: ToneTimbre.soft);
    double amp(int h) {
      var re = 0.0, im = 0.0;
      final n = t.samples.length;
      for (var i = 0; i < n; i++) {
        final ph = 2 * math.pi * t.cycles * h * i / n;
        re += t.samples[i] * math.cos(ph);
        im += t.samples[i] * math.sin(ph);
      }
      return 2 * math.sqrt(re * re + im * im) / n;
    }

    expect(amp(2) / amp(1), closeTo(0.22, 0.02));
    expect(amp(2), lessThan(amp(1) * 0.3));
  });

  test('WAV: cabeçalho e tamanho corretos', () {
    final t = buildToneLoop(440);
    final wav = pcm16Wav(t.samples, t.sampleRate);
    final bd = ByteData.sublistView(wav);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(bd.getUint32(24, Endian.little), t.sampleRate);
    expect(bd.getUint16(22, Endian.little), 1); // mono
    expect(bd.getUint16(34, Endian.little), 16);
    expect(wav.length, 44 + t.samples.length * 2);
    expect(bd.getUint32(40, Endian.little), t.samples.length * 2);
    // uma amostra de pico vira quase o máximo de 16 bits
    var maxV = 0;
    for (var i = 0; i < t.samples.length; i++) {
      final v = bd.getInt16(44 + i * 2, Endian.little).abs();
      if (v > maxV) maxV = v;
    }
    expect(maxV, closeTo(0.9 * 32767, 400));
  });

  test('desempenho: gerar o tom mais pesado em menos de 100 ms', () {
    final sw = Stopwatch()..start();
    for (final f in [41.2034, 440.0, 1318.51]) {
      buildToneLoop(f, timbre: ToneTimbre.soft);
    }
    expect(sw.elapsedMilliseconds / 3, lessThan(100));
  });
}
