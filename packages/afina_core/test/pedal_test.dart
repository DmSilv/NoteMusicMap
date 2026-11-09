import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  group('escolher as notas', () {
    test('liga, desliga e mantém do grave ao agudo, sem repetir', () {
      var n = <int>[];
      n = togglePedalNote(n, 64).notes; // Mi4
      n = togglePedalNote(n, 57).notes; // Lá3
      expect(n, [57, 64]);
      expect(togglePedalNote(n, 57).result, PedalToggle.removed);
      expect(togglePedalNote(n, 57).notes, [64]);
      expect(n, [57, 64], reason: 'a lista de entrada não é alterada');
    });

    test('limite de notas ao mesmo tempo: a quinta nota é recusada, mas dá para tirar', () {
      var n = <int>[];
      for (final m in [48, 52, 55, 60]) {
        n = togglePedalNote(n, m).notes;
      }
      expect(n.length, kMaxPedalVoices);
      final r = togglePedalNote(n, 64);
      expect(r.result, PedalToggle.full);
      expect(r.notes, n);
      expect(togglePedalNote(n, 52).result, PedalToggle.removed);
    });

    test('fora do teclado (graves e agudos demais) é recusado', () {
      expect(togglePedalNote([], kPedalLowestMidi - 1).result, PedalToggle.outOfRange);
      expect(togglePedalNote([], kPedalHighestMidi + 1).result, PedalToggle.outOfRange);
      expect(togglePedalNote([], kPedalLowestMidi).result, PedalToggle.added);
    });
  });

  group('atalhos', () {
    test('quinta, oitava, tônica+5ª e acordes a partir de uma raiz', () {
      expect(pedalPreset(PedalPreset.fifth, 57), [57, 64]);
      expect(pedalPreset(PedalPreset.octave, 57), [57, 69]);
      expect(pedalPreset(PedalPreset.rootFifth, 48), [48, 55, 60]);
      expect(pedalPreset(PedalPreset.major, 60), [60, 64, 67]);
      expect(pedalPreset(PedalPreset.minor, 60), [60, 63, 67]);
    });

    test('nunca passa do limite de notas e descarta o que sai do teclado', () {
      for (final p in PedalPreset.values) {
        expect(pedalPreset(p, 60).length, lessThanOrEqualTo(kMaxPedalVoices));
      }
      expect(pedalPreset(PedalPreset.octave, kPedalHighestMidi - 5), [kPedalHighestMidi - 5]);
    });
  });

  group('frequências no sistema escolhido', () {
    test('Igual: Lá4 = 440 e Lá4 = 442 muda tudo na mesma proporção', () {
      final a = pedalFrequencies([57, 69], const TuningConfig());
      expect(a[1], closeTo(440, 1e-9));
      expect(a[0], closeTo(220, 1e-9));
      final b = pedalFrequencies([57, 69], const TuningConfig(refA: 442));
      expect(b[1], closeTo(442, 1e-9));
      expect(b[1] / a[1], closeTo(442 / 440, 1e-12));
    });

    test('a transposição do instrumento não muda o som do pedal', () {
      final a = pedalFrequencies([69], const TuningConfig());
      final b = pedalFrequencies([69], const TuningConfig(transpose: 2));
      expect(b.first, closeTo(a.first, 1e-9));
    });

    test('Justo com tônica: a quinta fica exatamente 3:2', () {
      const just = TuningConfig(system: TuningSystem.just, tonicPc: 0, anchor: Anchor.tonic);
      final f = pedalFrequencies([60, 67], just);
      expect(f[1] / f[0], closeTo(3 / 2, 1e-12));
      const equal = TuningConfig();
      final e = pedalFrequencies([60, 67], equal);
      expect(e[1] / e[0], isNot(closeTo(3 / 2, 1e-6)), reason: 'na afinação igual a quinta é um pouco menor');
    });
  });

  group('intervalo e batimento', () {
    test('quinta justa na afinação igual treme ~0,7 Hz; no Justo, zero', () {
      const equal = TuningConfig();
      final fe = pedalFrequencies([57, 64], equal); // Lá3 + Mi4
      final ie = pedalInterval(57, 64, fe[0], fe[1]);
      expect(ie.name, '5ª justa');
      expect(ie.ratio, '3:2');
      expect(ie.simple, isTrue);
      expect(ie.beatHz, closeTo(0.74, 0.02), reason: 'Lá3 220 Hz + Mi4: 2·329,63 − 3·220 = −0,74');
      expect(ie.isSmooth, isFalse);

      const just = TuningConfig(system: TuningSystem.just, tonicPc: 9);
      final fj = pedalFrequencies([57, 64], just);
      final ij = pedalInterval(57, 64, fj[0], fj[1]);
      expect(ij.beatHz, lessThan(1e-9));
      expect(ij.isSmooth, isTrue);
    });

    test('o batimento dobra quando as duas notas sobem uma oitava', () {
      const equal = TuningConfig();
      final lo = pedalFrequencies([57, 64], equal);
      final hi = pedalFrequencies([69, 76], equal);
      final a = pedalInterval(57, 64, lo[0], lo[1]).beatHz;
      final b = pedalInterval(69, 76, hi[0], hi[1]).beatHz;
      expect(b / a, closeTo(2, 1e-9));
    });

    test('oitava e uníssono', () {
      final f = pedalFrequencies([57, 69], const TuningConfig());
      final o = pedalInterval(57, 69, f[0], f[1]);
      expect(o.name, 'oitava');
      expect(o.ratio, '2:1');
      expect(o.cents, closeTo(1200, 1e-6));
      expect(o.beatHz, lessThan(1e-9));
      final u = pedalInterval(60, 60, 261.6256, 261.6256);
      expect(u.name, 'uníssono');
      expect(u.beatHz, 0);
    });

    test('nomes e razões das terças, quartas e sextas; acima de uma oitava vira composto', () {
      String name(int a, int b) {
        final f = pedalFrequencies([a, b], const TuningConfig());
        return pedalInterval(a, b, f[0], f[1]).name;
      }

      expect(name(60, 64), '3ª maior');
      expect(name(60, 63), '3ª menor');
      expect(name(60, 65), '4ª justa');
      expect(name(60, 69), '6ª maior');
      expect(name(60, 76), '3ª maior + oitava');
      expect(name(60, 84), '2 oitavas');
      final f = pedalFrequencies([60, 64], const TuningConfig());
      expect(pedalInterval(60, 64, f[0], f[1]).ratio, '5:4');
    });

    test('a ordem das notas não importa e a terça maior igual treme bem mais que a justa', () {
      const equal = TuningConfig();
      final f = pedalFrequencies([60, 64], equal);
      final a = pedalInterval(60, 64, f[0], f[1]);
      final b = pedalInterval(64, 60, f[1], f[0]);
      expect(b.name, a.name);
      expect(b.beatHz, closeTo(a.beatHz, 1e-9));
      expect(a.beatHz, greaterThan(3), reason: 'harmônicos 4 e 5: 4·329,63 − 5·261,63 ≈ 10,9 Hz');
    });

    test('intervalos de razão complexa (trítono, sétimas) não mostram batimento', () {
      final f = pedalFrequencies([60, 66], const TuningConfig());
      expect(pedalInterval(60, 66, f[0], f[1]).simple, isFalse);
      final g = pedalFrequencies([60, 71], const TuningConfig());
      expect(pedalInterval(60, 71, g[0], g[1]).simple, isFalse);
    });
  });

  test('volume de cada nota diminui com mais notas, sem passar de 1', () {
    expect(pedalVoiceGain(0), 1);
    expect(pedalVoiceGain(1), 1);
    for (var n = 2; n <= kMaxPedalVoices; n++) {
      expect(pedalVoiceGain(n), lessThan(pedalVoiceGain(n - 1)));
    }
    // a soma das amplitudes no pior caso fica contida (< 1,6)
    expect(pedalVoiceGain(kMaxPedalVoices) * kMaxPedalVoices, lessThan(1.6));
  });
}
