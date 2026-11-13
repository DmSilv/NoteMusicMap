import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

// Cordas soltas do violino: Sol3, Ré4, Lá4, Mi5.
const _open = {55, 62, 69, 76};

void main() {
  test('a tabela confere com a sequência: índices existentes e dedos de 0 a 4', () {
    for (final e in violinFingeringEntries()) {
      final tonic = 55 + ((e.tonicPc - 55) % 12 + 12) % 12; // oitava perto da corda Sol, como o app
      final seq = scaleSequence(tonic, e.type, octaves: e.octaves);
      for (final m in e.marks.entries) {
        expect(m.key, inInclusiveRange(0, seq.length - 1), reason: 'índice ${m.key}');
        expect(int.parse(m.value), inInclusiveRange(0, 4));
      }
    }
  });

  test('todo "0" cai numa corda solta do violino (pega número lido na nota errada)', () {
    for (final e in violinFingeringEntries()) {
      final tonic = 55 + ((e.tonicPc - 55) % 12 + 12) % 12;
      final seq = scaleSequence(tonic, e.type, octaves: e.octaves);
      for (final m in e.marks.entries.where((m) => m.value == '0')) {
        expect(_open.contains(seq[m.key]), isTrue, reason: 'índice ${m.key} = nota ${seq[m.key]}');
      }
    }
  });

  test('o 4º dedo no lugar da corda solta: Si♭ maior sobe com 4º dedo no Ré4 e no Lá4 e desce com as cordas soltas', () {
    final seq = scaleSequence(58, ScaleType.major, octaves: 3);
    final f = violinFingering(tonicMidi: 58, type: ScaleType.major, octaves: 3, direction: ScaleDirection.both)!;
    expect(f.length, seq.length);
    expect(seq[2], 62); // Ré4
    expect(f[2], '4');
    expect(seq[6], 69); // Lá4
    expect(f[6], '4');
    expect(seq[36], 69);
    expect(f[36], '0');
    expect(seq[40], 62);
    expect(f[40], '0');
  });

  test('só subindo e só descendo recortam a mesma tabela', () {
    final both = violinFingering(tonicMidi: 58, type: ScaleType.major, octaves: 3, direction: ScaleDirection.both)!;
    final up = violinFingering(tonicMidi: 58, type: ScaleType.major, octaves: 3, direction: ScaleDirection.up)!;
    final down = violinFingering(tonicMidi: 58, type: ScaleType.major, octaves: 3, direction: ScaleDirection.down)!;
    expect(up, both.sublist(0, up.length));
    expect(down, both.sublist(up.length - 1));
    expect(down.first, both[up.length - 1]);
  });

  test('sem tabela, null (nada é inventado)', () {
    expect(violinFingering(tonicMidi: 60, type: ScaleType.major, octaves: 1, direction: ScaleDirection.both), isNull);
    expect(hasViolinFingering(58, ScaleType.major, 3), isTrue);
    expect(hasViolinFingering(58, ScaleType.major, 2), isFalse);
  });
}
