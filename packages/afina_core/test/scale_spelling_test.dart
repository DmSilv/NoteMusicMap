import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

String _seq(int tonic, ScaleType t, {required bool up}) {
  final sp = ScaleSpeller(tonic, t);
  final base = tonic + t.start;
  final midis = up ? [for (final x in t.steps) base + x, base + 12] : [base + 12, for (final x in t.downSteps.reversed) base + x];
  return midis.map((m) => sp.name(m, ascending: up)).join(' ');
}

void main() {
  test('trocar só o tipo mantém o nome da tônica (Lá♭ maior -> Lá♭ menor, Sol♯ menor -> Sol♯ maior não existe)', () {
    // Lá♭ (pc 8): maior só tem esta grafia; menor tem Sol♯ (comum) e Lá♭ (outra)
    expect(altKeepingSpelling(56, ScaleType.major, false, ScaleType.melodicMinor), isTrue);
    expect(altKeepingSpelling(56, ScaleType.melodicMinor, true, ScaleType.major), isFalse);
    // Ré♭ maior -> menor: Ré♭ menor não existe (8 bemóis): fica como está
    expect(altKeepingSpelling(61, ScaleType.major, false, ScaleType.melodicMinor), isNull);
    // Dó♯ menor -> Dó♯ maior (7 sustenidos, outra grafia do Ré♭)
    expect(altKeepingSpelling(61, ScaleType.melodicMinor, false, ScaleType.major), isTrue);
    // Mi♭ maior -> Mi♭ menor melódica: grafia comum nos dois
    expect(altKeepingSpelling(63, ScaleType.major, false, ScaleType.melodicMinor), isFalse);
    // cromática e arpejos não mexem
    expect(altKeepingSpelling(56, ScaleType.major, false, ScaleType.chromatic), isNull);
    expect(altKeepingSpelling(56, ScaleType.major, false, ScaleType.majorTriad), isNull);
  });

  tearDown(() => Lang.current = AppLang.pt);

  group('Dó menor melódica (Flesch): sobe com Lá e Si naturais, desce com Si♭ e Lá♭', () {
    test('subindo', () => expect(_seq(60, ScaleType.melodicMinor, up: true), 'Dó Ré Mi♭ Fá Sol Lá Si Dó'));
    test('descendo', () => expect(_seq(60, ScaleType.melodicMinor, up: false), 'Dó Si♭ Lá♭ Sol Fá Mi♭ Ré Dó'));
  });

  group('Ré menor (armadura com Si♭): sobe com Si natural e Dó♯, desce na armadura', () {
    test('subindo', () => expect(_seq(62, ScaleType.melodicMinor, up: true), 'Ré Mi Fá Sol Lá Si Dó♯ Ré'));
    test('descendo', () => expect(_seq(62, ScaleType.melodicMinor, up: false), 'Ré Dó Si♭ Lá Sol Fá Mi Ré'));
  });

  test('menor natural e harmônica seguem a armadura / o sensível', () {
    expect(_seq(62, ScaleType.naturalMinor, up: true), 'Ré Mi Fá Sol Lá Si♭ Dó Ré');
    expect(_seq(62, ScaleType.harmonicMinor, up: true), 'Ré Mi Fá Sol Lá Si♭ Dó♯ Ré');
  });

  test('maiores com a grafia certa (nada de Sol♯ no lugar de Lá♭)', () {
    expect(_seq(55, ScaleType.major, up: true), 'Sol Lá Si Dó Ré Mi Fá♯ Sol');
    expect(_seq(68, ScaleType.major, up: true), 'Lá♭ Si♭ Dó Ré♭ Mi♭ Fá Sol Lá♭');
    expect(_seq(61, ScaleType.major, up: true), 'Ré♭ Mi♭ Fá Sol♭ Lá♭ Si♭ Dó Ré♭');
    expect(_seq(66, ScaleType.major, up: true), 'Fá♯ Sol♯ Lá♯ Si Dó♯ Ré♯ Mi♯ Fá♯');
  });

  group('tônica por letra + acidente (o seletor de tônica do app)', () {
    test('as tonalidades que existem, nas duas grafias', () {
      // maiores: Fá♯ (padrão) e Sol♭ (outra grafia) são a mesma tecla
      expect(tonicForSpelling(3, 1, ScaleType.major), (pc: 6, alt: false));
      expect(tonicForSpelling(4, -1, ScaleType.major), (pc: 6, alt: true));
      expect(tonicForSpelling(0, 1, ScaleType.major), (pc: 1, alt: true)); // Dó♯ maior (7 sustenidos)
      expect(tonicForSpelling(1, -1, ScaleType.major), (pc: 1, alt: false)); // Ré♭
      expect(tonicForSpelling(0, -1, ScaleType.major), (pc: 11, alt: true)); // Dó♭
      expect(tonicForSpelling(6, 0, ScaleType.major), (pc: 11, alt: false));
      // menores
      expect(tonicForSpelling(1, 1, ScaleType.naturalMinor), (pc: 3, alt: true)); // Ré♯ menor
      expect(tonicForSpelling(2, -1, ScaleType.naturalMinor), (pc: 3, alt: false)); // Mi♭ menor
      expect(tonicForSpelling(5, -1, ScaleType.melodicMinor), (pc: 8, alt: true)); // Lá♭ menor
      expect(tonicForSpelling(4, 1, ScaleType.melodicMinor), (pc: 8, alt: false)); // Sol♯ menor
    });

    test('o que não existe devolve null (Mi♯ maior, Fá♭, Si♯, Dó♭ menor...)', () {
      expect(tonicForSpelling(2, 1, ScaleType.major), isNull);
      expect(tonicForSpelling(3, -1, ScaleType.major), isNull);
      expect(tonicForSpelling(6, 1, ScaleType.major), isNull);
      expect(tonicForSpelling(0, -1, ScaleType.naturalMinor), isNull);
      expect(tonicForSpelling(1, 1, ScaleType.major), isNull); // Ré♯ maior (9 sustenidos)
    });

    test('ida e volta: a grafia de cada tônica devolve a mesma tônica, em todos os tipos', () {
      for (final t in ScaleType.values) {
        for (var midi = 55; midi < 67; midi++) {
          for (final alt in [false, true]) {
            final sp = ScaleSpeller(midi, t, alt: alt);
            final (l, a) = sp.tonicSpelling;
            final back = tonicForSpelling(l, a, t);
            expect(back, isNotNull, reason: '${t.name} $midi alt=$alt');
            expect(back!.pc, midi % 12);
            // o seletor reproduz exatamente a escolha (a "outra grafia" só vale onde existe)
            final really = alt && ScaleSpeller.hasAlt(midi, minor: t.isMinor) && !t.arpeggio && t != ScaleType.chromatic;
            expect(back.alt, really, reason: '${t.name} $midi alt=$alt');
          }
        }
      }
    });
  });

  test('cromática: sobe com sustenidos e desce com bemóis', () {
    final s = ScaleSpeller(60, ScaleType.chromatic);
    expect([for (final m in [61, 63, 66, 68, 70]) s.name(m, ascending: true)], ['Dó♯', 'Ré♯', 'Fá♯', 'Sol♯', 'Lá♯']);
    expect([for (final m in [70, 68, 66, 63, 61]) s.name(m, ascending: false)], ['Si♭', 'Lá♭', 'Sol♭', 'Mi♭', 'Ré♭']);
  });

  test('arpejos: tríades e sétimas na letra certa', () {
    final maj = ScaleSpeller(55, ScaleType.majorTriad);
    expect([for (final m in [55, 59, 62, 67]) maj.name(m, ascending: true)], ['Sol', 'Si', 'Ré', 'Sol']);
    final min = ScaleSpeller(62, ScaleType.minorTriad);
    expect([for (final m in [62, 65, 69]) min.name(m, ascending: true)], ['Ré', 'Fá', 'Lá']);
    final dom = ScaleSpeller(67, ScaleType.dominantSeventh);
    expect([for (final m in [67, 71, 74, 77]) dom.name(m, ascending: true)], ['Sol', 'Si', 'Ré', 'Fá']);
    final dim = ScaleSpeller(60, ScaleType.diminishedSeventh);
    expect([for (final m in [60, 63, 66, 69]) dim.name(m, ascending: true)], ['Dó', 'Mi♭', 'Sol♭', 'Lá']);
  });

  test('a oitava acompanha a letra (Dó4 = dó central) e o nome sai em inglês', () {
    final s = ScaleSpeller(55, ScaleType.major);
    expect(s.name(55, ascending: true, withOctave: true), 'Sol3');
    expect(s.name(66, ascending: true, withOctave: true), 'Fá♯4');
    Lang.current = AppLang.en;
    expect(s.name(66, ascending: true, withOctave: true), 'F♯4');
    expect(ScaleSpeller(60, ScaleType.melodicMinor).name(70, ascending: false), 'B♭');
  });

  group('direção do exercício', () {
    test('subindo e descendo (padrão): 15 notas numa oitava de escala maior', () {
      final e = ScaleExercise(tonicMidi: 55, type: ScaleType.major, octaves: 1, zone: 10);
      expect(e.sequence.length, 15);
      expect(e.upCount, 8);
      expect(e.ascendingAt(7), isTrue);
      expect(e.ascendingAt(8), isFalse);
    });

    test('só subindo', () {
      final e = ScaleExercise(tonicMidi: 55, type: ScaleType.major, octaves: 2, zone: 10, direction: ScaleDirection.up);
      expect(e.sequence.first, 55);
      expect(e.sequence.last, 79);
      expect(e.sequence.length, 15);
      expect(e.sequence.every((m) => e.ascendingAt(e.sequence.indexOf(m))), isTrue);
    });

    test('só descendo: começa na tônica mais alta e termina na mais grave', () {
      final e = ScaleExercise(tonicMidi: 55, type: ScaleType.major, octaves: 2, zone: 10, direction: ScaleDirection.down);
      expect(e.sequence.first, 79);
      expect(e.sequence.last, 55);
      expect(e.sequence.length, 15);
      expect(e.upCount, 0);
      expect(e.ascendingNow, isFalse);
      for (var i = 1; i < e.sequence.length; i++) {
        expect(e.sequence[i], lessThan(e.sequence[i - 1]));
      }
    });

    test('menor melódica descendo usa as notas naturais (Si♭ e Lá♭ em Dó menor)', () {
      final e = ScaleExercise(tonicMidi: 60, type: ScaleType.melodicMinor, octaves: 1, zone: 10, direction: ScaleDirection.down);
      expect(e.sequence, [72, 70, 68, 67, 65, 63, 62, 60]);
      final up = ScaleExercise(tonicMidi: 60, type: ScaleType.melodicMinor, octaves: 1, zone: 10, direction: ScaleDirection.up);
      expect(up.sequence, [60, 62, 63, 65, 67, 69, 71, 72]);
    });
  });
}
