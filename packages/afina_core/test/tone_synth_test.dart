import 'dart:math' as math;
import 'dart:typed_data';

import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  chimeTests();
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
        if (lowNoteStrength(f) == 0 || tb == ToneTimbre.violin) {
          expect(b.abs(), lessThan(1e-9)); // senoide pura começa em fase zero
        }
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
      expect(peak, closeTo(kTonePeak, 0.01));
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

    expect(amp(1), closeTo(kTonePeak, 0.01));
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
    expect(maxV, closeTo(kTonePeak * 32767, 400));
  });

  test('desempenho: gerar o tom mais pesado em menos de 100 ms', () {
    final sw = Stopwatch()..start();
    for (final f in [41.2034, 440.0, 1318.51]) {
      buildToneLoop(f, timbre: ToneTimbre.soft);
    }
    expect(sw.elapsedMilliseconds / 3, lessThan(100));
  });
}

void chimeTests() {
  group('alarme (sino)', () {
    test('tem som de verdade: pico 0,9 e duração de 2,2 s', () {
      for (final eof in [true, false]) {
        final c = buildChime(endOfFocus: eof);
        var peak = 0.0;
        for (final v in c) {
          if (v.abs() > peak) peak = v.abs();
        }
        expect(peak, closeTo(0.9, 0.01), reason: 'endOfFocus=$eof');
        expect(c.length / 44100, closeTo(2.2, 0.01));
      }
    });

    test('termina em silêncio, sem clique', () {
      final c = buildChime(endOfFocus: true);
      expect(c.last.abs(), lessThan(1e-3));
      expect(c[c.length - 2].abs(), lessThan(1e-2));
    });

    test('fim de foco desce (agudo → grave); fim de pausa sobe', () {
      // Estima a frequência por cruzamentos de zero em janelas curtas dentro de
      // cada nota (0,03–0,25 s e 0,36–0,56 s).
      double hz(Float32List s, double from, double to) {
        final a = (from * 44100).round(), b = (to * 44100).round();
        var z = 0;
        for (var i = a + 1; i < b; i++) {
          if ((s[i - 1] < 0) != (s[i] < 0)) z++;
        }
        return z / 2 / (to - from);
      }

      final down = buildChime(endOfFocus: true);
      final up = buildChime(endOfFocus: false);
      expect(hz(down, 0.03, 0.25), greaterThan(hz(down, 0.40, 0.60)));
      expect(hz(up, 0.03, 0.25), lessThan(hz(up, 0.40, 0.60)));
    });
  });

  group('notas graves audíveis (Sol3 no celular)', () {
    const strings = {'Sol3': 195.9954, 'Ré4': 293.6648, 'Lá4': 440.0, 'Mi5': 659.2551};

    test('o reforço só age abaixo de ~420 Hz', () {
      expect(lowNoteStrength(195.9954), 1.0);
      expect(lowNoteStrength(293.6648), inInclusiveRange(0.2, 0.6));
      expect(lowNoteStrength(440), 0.0);
      expect(lowNoteStrength(659.2551), 0.0);
    });

    test('Sol3 fica pelo menos 4 dB mais forte (percebido) do que a senoide pura', () {
      final puro = toneLoudnessDb(buildToneLoop(195.9954, boostLow: false));
      final novo = toneLoudnessDb(buildToneLoop(195.9954));
      expect(novo - puro, greaterThan(4.0));
    });

    test('a diferença de volume entre as cordas cai (de ~9 dB para menos de 6 dB)', () {
      double spread(bool boost) {
        final v = [
          for (final f in strings.values) toneLoudnessDb(buildToneLoop(f, boostLow: boost))
        ];
        return v.reduce(math.max) - v.reduce(math.min);
      }

      expect(spread(false), greaterThan(8));
      expect(spread(true), lessThan(6));
    });

    test('qualidade: nunca estoura e a fundamental continua presente', () {
      for (final tb in [ToneTimbre.fork, ToneTimbre.soft]) {
        for (final f in strings.values) {
          final t = buildToneLoop(f, timbre: tb);
          var peak = 0.0;
          for (final x in t.samples) {
            peak = math.max(peak, x.abs());
          }
          expect(peak, lessThanOrEqualTo(0.95));
          // fundamental com pelo menos 20% do pico
          var re = 0.0, im = 0.0;
          final n = t.samples.length;
          for (var i = 0; i < n; i++) {
            final ph = 2 * math.pi * t.cycles * i / n;
            re += t.samples[i] * math.cos(ph);
            im += t.samples[i] * math.sin(ph);
          }
          expect(2 * math.sqrt(re * re + im * im) / n, greaterThan(0.2 * peak), reason: '$f $tb');
          // e a altura continua exata
          expect(t.centsError(f).abs(), lessThan(0.5));
        }
      }
    });

    test('o laço continua sem emenda com o reforço', () {
      final t = buildToneLoop(195.9954);
      final n = t.samples.length;
      final a = t.samples[n - 1], b = t.samples[0], c = t.samples[1];
      expect((b - a).abs(), lessThanOrEqualTo((c - b).abs() * 1.6 + 1e-3));
    });

    test('a ponderação A é a esperada (referência: 1 kHz = 0 dB)', () {
      expect(aWeightDb(1000), closeTo(0, 0.2));
      expect(aWeightDb(100), closeTo(-19.1, 0.3));
      expect(aWeightDb(200), closeTo(-10.9, 0.3));
    });
  });
}
