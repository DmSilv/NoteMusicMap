import 'package:afina_core/tuning.dart';
import 'package:test/test.dart';

void main() {
  group('temperamento igual', () {
    test('Lá4 = refA e Dó4 = 261.626', () {
      expect(etFreq(69, 440), closeTo(440, 1e-9));
      expect(etFreq(60, 440), closeTo(261.6256, 1e-3));
      expect(etFreq(69, 442), closeTo(442, 1e-9));
    });
    test('cents: oitava = 1200, semitom = 100', () {
      expect(centsBetween(880, 440), closeTo(1200, 1e-9));
      expect(centsBetween(etFreq(70, 440), 440), closeTo(100, 1e-9));
    });
  });

  group('cordas soltas do violino (quintas puras ancoradas no Lá)', () {
    final v = instrumentById('violino');
    test('frequências exatas', () {
      expect(v.stringFreq(3, 440), closeTo(660.0, 1e-9)); // Mi5
      expect(v.stringFreq(2, 440), closeTo(440.0, 1e-9)); // Lá4
      expect(v.stringFreq(1, 440), closeTo(293.3333, 1e-3)); // Ré4
      expect(v.stringFreq(0, 440), closeTo(195.5556, 1e-3)); // Sol3
    });
    test('cada quinta é exatamente 3:2', () {
      for (var i = 0; i < 3; i++) {
        expect(v.stringFreq(i + 1, 440) / v.stringFreq(i, 440),
            closeTo(1.5, 1e-12));
      }
    });
    test('diferença para o temperado bate com a teoria', () {
      final et = TuningConfig(refA: 440);
      expect(centsBetween(v.stringFreq(3, 440), etFreq(76, 440)),
          closeTo(1.955, 0.001));
      expect(centsBetween(v.stringFreq(1, 440), etFreq(62, 440)),
          closeTo(-1.955, 0.001));
      expect(centsBetween(v.stringFreq(0, 440), etFreq(55, 440)),
          closeTo(-3.910, 0.001));
      expect(et.system, TuningSystem.equal);
    });
    test('A muda com a referência (442 Hz)', () {
      expect(v.stringFreq(2, 442), closeTo(442, 1e-9));
      expect(v.stringFreq(3, 442), closeTo(663, 1e-9));
    });
  });

  group('violoncelo e viola', () {
    test('cello: A3=220, D3, G2, C2 em quintas puras', () {
      final c = instrumentById('violoncelo');
      expect(c.stringFreq(3, 440), closeTo(220, 1e-9));
      expect(c.stringFreq(2, 440), closeTo(146.6667, 1e-3));
      expect(c.stringFreq(1, 440), closeTo(97.7778, 1e-3));
      expect(c.stringFreq(0, 440), closeTo(65.1852, 1e-3));
      // C2 fica ~5.87 cents abaixo do temperado.
      expect(centsBetween(c.stringFreq(0, 440), etFreq(36, 440)),
          closeTo(-5.865, 0.01));
    });
    test('viola: C3 = metade do C4 do cello? (65.185*2 = 130.370)', () {
      final va = instrumentById('viola');
      expect(va.stringFreq(0, 440), closeTo(130.3704, 1e-3));
      expect(va.stringFreq(3, 440), closeTo(440, 1e-9));
    });
  });

  group('instrumentos com trastes usam temperamento igual', () {
    test('violão E2 = 82.407 Hz', () {
      final g = instrumentById('violao');
      expect(g.stringFreq(0, 440), closeTo(82.4069, 1e-3));
      expect(g.stringFreq(5, 440), closeTo(329.6276, 1e-3));
    });
  });

  group('sistemas cromáticos (âncora no Lá)', () {
    test('Lá4 sempre vale refA, em qualquer tônica e sistema', () {
      for (final sys in [TuningSystem.pythagorean, TuningSystem.just]) {
        for (var tonic = 0; tonic < 12; tonic++) {
          final c = TuningConfig(
              refA: 440, system: sys, tonicPc: tonic, anchor: Anchor.a4);
          expect(targetFreq(69, c), closeTo(440, 1e-9),
              reason: '$sys tônica $tonic');
          // e em outras oitavas
          expect(targetFreq(57, c), closeTo(220, 1e-9));
          expect(targetFreq(81, c), closeTo(880, 1e-9));
        }
      }
    });
    test('justo, Sol maior: terça (Si) = -13.69 cents vs temperado', () {
      final c = TuningConfig(
          system: TuningSystem.just, tonicPc: 7, anchor: Anchor.tonic);
      // Si4 = midi 71. Com âncora na tônica, a tônica fica no temperado.
      expect(offsetFromEqual(71, c), closeTo(-13.686, 0.01));
      expect(offsetFromEqual(74, c), closeTo(1.955, 0.01)); // Ré = quinta
      expect(offsetFromEqual(67, c), closeTo(0, 1e-9)); // Sol = tônica
    });
    test('justo, âncora no Lá: Lá fixo e Sol tônica cai -3.91', () {
      final c = TuningConfig(
          system: TuningSystem.just, tonicPc: 7, anchor: Anchor.a4);
      expect(targetFreq(69, c), closeTo(440, 1e-9));
      // Sol é 9/8 abaixo do Lá: -203.91 cents contra os -200 do temperado.
      expect(offsetFromEqual(67, c), closeTo(-3.910, 0.01));
    });
    test('pitagórico, tônica Lá: terça maior (Dó♯) = +7.82 cents', () {
      final c = TuningConfig(system: TuningSystem.pythagorean, tonicPc: 9);
      expect(offsetFromEqual(73, c), closeTo(7.820, 0.01));
      expect(offsetFromEqual(76, c), closeTo(1.955, 0.01)); // Mi
      expect(offsetFromEqual(74, c), closeTo(-1.955, 0.01)); // Ré, quarta
    });
    test('oitavas mantêm a razão 2:1', () {
      final c = TuningConfig(system: TuningSystem.just, tonicPc: 2);
      for (var m = 40; m < 90; m++) {
        expect(targetFreq(m + 12, c) / targetFreq(m, c), closeTo(2, 1e-12));
      }
    });
  });

  group('nearestTarget', () {
    test('identifica Si de Sol maior justo mesmo -13.7¢ do temperado', () {
      final c = TuningConfig(
          system: TuningSystem.just, tonicPc: 7, anchor: Anchor.tonic);
      final f = targetFreq(71, c);
      final m = nearestTarget(f, c);
      expect(m.midi, 71);
      expect(m.cents, closeTo(0, 1e-9));
      // Contra o temperado, a mesma frequência estaria -13.7 cents.
      expect(centsBetween(f, etFreq(71, 440)), closeTo(-13.686, 0.01));
    });
    test('nota 30 cents acima é lida como +30, não como outra nota', () {
      final c = TuningConfig();
      final f = etFreq(69, 440) * 1.0174; // ~ +30 cents
      final m = nearestTarget(f, c);
      expect(m.midi, 69);
      expect(m.cents, closeTo(30, 0.5));
    });
    test('45 cents acima: continua na mesma nota; 55: troca', () {
      final c = TuningConfig();
      expect(nearestTarget(etFreq(69.45, 440), c).midi, 69);
      expect(nearestTarget(etFreq(69.55, 440), c).midi, 70);
    });
  });

  group('nomes', () {
    test('sustenido/bemol e transposição', () {
      const sharp = TuningConfig();
      const flat = TuningConfig(preferFlats: true);
      expect(noteName(70, sharp), 'Lá♯');
      expect(noteName(70, flat), 'Si♭');
      expect(noteName(69, sharp, withOctave: true), 'Lá4');
      // Clarinete em Si♭ lê +2: Dó soando = Ré escrito.
      expect(noteName(60, const TuningConfig(transpose: 2)), 'Ré');
    });
  });

  group('grafia automática de sustenidos e bemóis', () {
    const auto = TuningConfig(autoSpelling: true);

    test('sem tonalidade, alterna ♯ e ♭ (Dó♯, Mi♭, Fá♯, Lá♭, Si♭)', () {
      final nomes = [for (var pc = 0; pc < 12; pc++) noteName(60 + pc, auto)];
      expect(nomes, ['Dó', 'Dó♯', 'Ré', 'Mi♭', 'Mi', 'Fá', 'Fá♯', 'Sol', 'Lá♭', 'Lá', 'Si♭', 'Si']);
      // aparece os dois tipos de acidente
      expect(nomes.any((n) => n.contains('♯')), isTrue);
      expect(nomes.any((n) => n.contains('♭')), isTrue);
    });

    test('Sol e depois a tecla preta seguinte aparece como Lá♭, não Sol♯', () {
      expect(noteName(67, auto), 'Sol');
      expect(noteName(68, auto), 'Lá♭');
    });

    test('com tonalidade de bemóis (Fá maior), todas as pretas são bemóis', () {
      final fa = auto.copyWith(keyFlats: keyUsesFlats(5));
      expect(noteName(70, fa), 'Si♭');
      expect(noteName(66, fa), 'Sol♭'); // e não Fá♯
      expect(noteName(61, fa), 'Ré♭');
    });

    test('com tonalidade de sustenidos (Ré maior), as pretas são sustenidos', () {
      final re = auto.copyWith(keyFlats: keyUsesFlats(2));
      expect(noteName(66, re), 'Fá♯');
      expect(noteName(61, re), 'Dó♯');
      expect(noteName(68, re), 'Sol♯');
    });

    test('armaduras: maiores e menores', () {
      for (final t in [5, 10, 3, 8, 1]) {
        expect(keyUsesFlats(t), isTrue, reason: 'maior $t');
      }
      for (final t in [0, 7, 2, 9, 4, 11, 6]) {
        expect(keyUsesFlats(t), isFalse, reason: 'maior $t');
      }
      // menores: Sol menor (Si♭ maior), Dó menor, Fá menor, Mi♭ menor = bemóis
      for (final t in [7, 0, 5, 3, 2, 10]) {
        expect(keyUsesFlats(t, minor: true), isTrue, reason: 'menor $t');
      }
      // Lá menor, Mi menor, Si menor, Fá♯ menor, Dó♯ menor, Sol♯ menor = sustenidos
      for (final t in [9, 4, 11, 6, 1, 8]) {
        expect(keyUsesFlats(t, minor: true), isFalse, reason: 'menor $t');
      }
    });

    test('sem grafia automática vale só a preferência (compatível com antes)', () {
      expect(noteName(70, const TuningConfig()), 'Lá♯');
      expect(noteName(70, const TuningConfig(preferFlats: true)), 'Si♭');
      // e a preferência manual vence a tonalidade quando a automática está desligada
      final manual = const TuningConfig(preferFlats: true).copyWith(keyFlats: false);
      expect(noteName(70, manual), 'Si♭');
    });

    test('namesFor: null = automático', () {
      expect(namesFor(null)[8], 'Lá♭');
      expect(namesFor(false)[8], 'Sol♯');
      expect(namesFor(true)[8], 'Lá♭');
    });
  });
}
