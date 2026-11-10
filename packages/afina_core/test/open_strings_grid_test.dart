import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  // O afinador de cordas afina em quintas puras (Sol3 = 195,56 Hz). Em temperamento
  // igual o Sol3 seria 196,00 Hz (3,9 cents acima). A grade precisa concordar.
  final violin = instrumentById('violino');
  const base = TuningConfig(refA: 440.0, system: TuningSystem.equal);

  test('afinador de cordas: Sol3 solto = 195,56 Hz', () {
    expect(violin.stringFreq(0, 440), closeTo(195.556, 0.01));
  });

  test('sem ajuste, o Sol afinado pelo afinador aparece 3,9 cents baixo', () {
    final m = nearestTarget(violin.stringFreq(0, 440), base);
    expect(m.midi, 55);
    expect(m.cents, closeTo(-3.9, 0.1));
  });

  test('com os alvos das cordas soltas, o Sol afinado fica em 0 cents', () {
    final cfg = base.copyWith(targetOverrides: violin.openTargets(440));
    final m = nearestTarget(violin.stringFreq(0, 440), cfg);
    expect(m.midi, 55);
    expect(m.cents.abs(), lessThan(0.01));
  });

  test('as quatro cordas soltas do violino ficam em 0 cents na grade', () {
    final cfg = base.copyWith(targetOverrides: violin.openTargets(440));
    for (var i = 0; i < 4; i++) {
      final m = nearestTarget(violin.stringFreq(i, 440), cfg);
      expect(m.midi, violin.strings[i].midi);
      expect(m.cents.abs(), lessThan(0.01), reason: 'corda $i');
    }
  });

  test('as outras notas continuam em temperamento igual', () {
    final cfg = base.copyWith(targetOverrides: violin.openTargets(440));
    expect(targetFreq(57, cfg), closeTo(etFreq(57, 440), 1e-9)); // Lá3
    expect(targetFreq(60, cfg), closeTo(etFreq(60, 440), 1e-9)); // Dó4
  });

  test('instrumento com trastes não tem alvos especiais', () {
    expect(instrumentById('violao').openTargets(440), isEmpty);
  });

  test('o Lá continua em refA com outras referências', () {
    final cfg = base.copyWith(refA: 442, targetOverrides: violin.openTargets(442));
    expect(targetFreq(69, cfg), closeTo(442, 1e-9));
  });
}
