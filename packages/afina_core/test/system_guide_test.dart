import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  const justC = TuningConfig(system: TuningSystem.just, tonicPc: 0, anchor: Anchor.tonic);
  const justG = TuningConfig(system: TuningSystem.just, tonicPc: 7);

  group('tabela do sistema de afinação', () {
    test('12 linhas, a partir da tônica, com os papéis certos', () {
      final r = systemRows(justG);
      expect(r.length, 12);
      expect(r.first.role, 'Tônica');
      expect(r.first.name, 'Sol');
      expect(r[4].role, '3ª maior');
      expect(r[4].name, 'Si');
      expect(r[7].role, '5ª justa');
      expect(r[7].name, 'Ré');
      expect(r.map((x) => x.step), [for (var i = 0; i < 12; i++) i]);
    });

    test('Igual: alvo = igual em todas as notas (diferença zero)', () {
      for (var pc = 0; pc < 12; pc++) {
        final r = systemRows(TuningConfig(system: TuningSystem.equal, tonicPc: pc));
        expect(r.every((x) => x.diffHz.abs() < 1e-9), isTrue, reason: 'tônica $pc');
        expect(r.any((x) => x.differs), isFalse);
      }
    });

    test('Justo com a tônica no temperado: a terça maior desce ~13,7 cents e a quinta sobe ~2', () {
      final r = systemRows(justC);
      expect(r[0].diffHz.abs(), lessThan(1e-9)); // tônica = igual
      expect(r[4].diffCents, closeTo(-13.686, 0.01)); // Mi 5:4
      expect(r[7].diffCents, closeTo(1.955, 0.01)); // Sol 3:2
      expect(r[4].diffHz, lessThan(0));
      expect(r[7].diffHz, greaterThan(0));
      // em Hz, na oitava 4: Mi justo (5/4 de 261,626) = 327,03 Hz contra 329,63 do igual
      expect(r[4].target, closeTo(261.6256 * 5 / 4, 0.001));
      expect(r[4].equal, closeTo(329.6276, 0.001));
      expect(r[4].diffHz, closeTo(-2.60, 0.01));
    });

    test('Justo: as razões entre a tônica e cada nota são exatamente as puras', () {
      final r = systemRows(justC);
      final t = r[0].target;
      expect(r[4].target / t, closeTo(5 / 4, 1e-12));
      expect(r[7].target / t, closeTo(3 / 2, 1e-12));
      expect(r[5].target / t, closeTo(4 / 3, 1e-12));
      expect(r[9].target / t, closeTo(5 / 3, 1e-12));
      expect(r[11].target / t, closeTo(15 / 8, 1e-12));
      expect(r[2].target / t, closeTo(9 / 8, 1e-12));
    });

    test('Pitagórico: quinta pura 3:2 e terça maior alta (81:64, +7,8 cents)', () {
      const pit = TuningConfig(system: TuningSystem.pythagorean, tonicPc: 0, anchor: Anchor.tonic);
      final r = systemRows(pit);
      final t = r[0].target;
      expect(r[7].target / t, closeTo(3 / 2, 1e-12));
      expect(r[4].target / t, closeTo(81 / 64, 1e-12));
      expect(r[4].diffCents, closeTo(7.82, 0.01));
      expect(r[4].diffHz, greaterThan(0)); // sobe
    });

    test('com o Lá fixo, o Lá4 vale exatamente a referência em qualquer sistema e tônica', () {
      for (final sys in TuningSystem.values) {
        for (var pc = 0; pc < 12; pc++) {
          final cfg = TuningConfig(system: sys, tonicPc: pc, refA: 442);
          expect(targetFreq(69, cfg), closeTo(442, 1e-9), reason: '$sys $pc');
          expect(a4ShiftHz(cfg).abs(), lessThan(1e-9));
        }
      }
    });

    test('com a tônica no temperado (Lá não fixo), a tônica é igual e o Lá pode mudar', () {
      final r = systemRows(justG.copyWith(anchor: Anchor.tonic));
      expect(r[0].diffHz.abs(), lessThan(1e-9));
      expect(a4ShiftHz(justG.copyWith(anchor: Anchor.tonic)).abs(), greaterThan(0.01));
    });

    test('a tabela segue a referência (Lá 442 muda todos os alvos de forma proporcional)', () {
      final a = systemRows(justG);
      final b = systemRows(justG.copyWith(refA: 442));
      for (var i = 0; i < 12; i++) {
        expect(b[i].target / a[i].target, closeTo(442 / 440, 1e-9));
      }
    });

    test('o alvo de cada linha é reconhecido como aquela nota, com 0 de desvio', () {
      for (final sys in TuningSystem.values) {
        for (final tonic in [0, 2, 7, 9]) {
          final cfg = TuningConfig(system: sys, tonicPc: tonic);
          for (final row in systemRows(cfg)) {
            final m = nearestTarget(row.target, cfg);
            expect(m.midi, row.midi, reason: '$sys $tonic ${row.name}');
            expect(m.cents.abs(), lessThan(1e-6));
          }
        }
      }
    });

    test('o nome das notas segue a grafia escolhida', () {
      final sharp = systemRows(const TuningConfig(tonicPc: 1));
      expect(sharp[0].name, 'Dó♯');
      final flat = systemRows(const TuningConfig(tonicPc: 1, preferFlats: true));
      expect(flat[0].name, 'Ré♭');
    });
  });
}
