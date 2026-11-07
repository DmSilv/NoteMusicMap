import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

const dol = 60; // Dó4

void main() {
  group('arpejos (família do sistema de Carl Flesch)', () {
    test('tríade maior, 1 oitava: sobe e desce pelas notas do acorde', () {
      expect(scaleSequence(dol, ScaleType.majorTriad), [60, 64, 67, 72, 67, 64, 60]);
    });

    test('tríade menor tem a 3ª meio tom abaixo', () {
      expect(scaleSequence(dol, ScaleType.minorTriad), [60, 63, 67, 72, 67, 63, 60]);
    });

    test('1ª inversão começa na 3ª e termina uma oitava acima dela', () {
      expect(scaleSequence(dol, ScaleType.majorTriad1), [64, 67, 72, 76, 72, 67, 64]);
      expect(scaleSequence(dol, ScaleType.minorTriad1), [63, 67, 72, 75, 72, 67, 63]);
    });

    test('2ª inversão começa na 5ª', () {
      expect(scaleSequence(dol, ScaleType.majorTriad2), [67, 72, 76, 79, 76, 72, 67]);
      expect(scaleSequence(dol, ScaleType.minorTriad2), [67, 72, 75, 79, 75, 72, 67]);
    });

    test('7ª da dominante (1-3-5-b7) e 7ª diminuta (terças menores)', () {
      expect(scaleSequence(dol, ScaleType.dominantSeventh), [60, 64, 67, 70, 72, 70, 67, 64, 60]);
      expect(scaleSequence(dol, ScaleType.diminishedSeventh), [60, 63, 66, 69, 72, 69, 66, 63, 60]);
    });

    test('2 e 3 oitavas repetem o desenho e o último ponto fica na oitava certa', () {
      for (final t in ScaleType.arpeggios) {
        for (final o in [1, 2, 3]) {
          final up = scaleMidis(dol, t, octaves: o);
          expect(up.length, t.steps.length * o + 1, reason: '${t.label} $o');
          expect(up.last - up.first, 12 * o, reason: '${t.label} $o');
          final seq = scaleSequence(dol, t, octaves: o);
          expect(seq.first, seq.last);
          expect(seq.length, up.length * 2 - 1);
        }
      }
    });

    test('cada arpejo soa as notas do acorde (classes de altura certas)', () {
      Set<int> pcs(ScaleType t) => {for (final m in scaleSequence(dol, t)) m % 12};
      expect(pcs(ScaleType.majorTriad), {0, 4, 7});
      expect(pcs(ScaleType.majorTriad1), {0, 4, 7});
      expect(pcs(ScaleType.majorTriad2), {0, 4, 7});
      expect(pcs(ScaleType.minorTriad), {0, 3, 7});
      expect(pcs(ScaleType.minorTriad1), {0, 3, 7});
      expect(pcs(ScaleType.minorTriad2), {0, 3, 7});
      expect(pcs(ScaleType.dominantSeventh), {0, 4, 7, 10});
      expect(pcs(ScaleType.diminishedSeventh), {0, 3, 6, 9});
    });

    test('listas de escalas e arpejos não se misturam e escalas seguem iguais', () {
      expect(ScaleType.arpeggios.every((t) => t.arpeggio), isTrue);
      expect(ScaleType.scales.every((t) => !t.arpeggio), isTrue);
      expect(ScaleType.scales.length + ScaleType.arpeggios.length, ScaleType.values.length);
      expect(scaleSequence(dol, ScaleType.major).length, 15);
      expect(scaleMidis(dol, ScaleType.major), [60, 62, 64, 65, 67, 69, 71, 72]);
    });

    test('nome para mostrar', () {
      expect(ScaleType.majorTriad.display('Sol'), 'Arpejo maior de Sol');
      expect(ScaleType.naturalMinor.display('Lá'), 'Lá menor natural');
    });

    test('o exercício guiado funciona com arpejos (modo seguir o ritmo)', () {
      final e = ScaleExercise(
          tonicMidi: 55, type: ScaleType.majorTriad1, octaves: 1, zone: 5, flow: true);
      expect(e.sequence.first, 59); // Si3 = 3ª de Sol
      for (final m in e.sequence) {
        for (var i = 0; i < 8; i++) {
          e.feed(midi: m, cents: 1, clarity: 0.9, dt: 0.03);
        }
      }
      for (var i = 0; i < 10; i++) {
        e.feed(midi: null, cents: 0, clarity: 0, dt: 0.03);
      }
      expect(e.finished, isTrue);
      expect(e.score.accuracy, 1.0);
    });
  });
}
