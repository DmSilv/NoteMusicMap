import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

StaffScore _score(int tonic, ScaleType t, {int octaves = 1, StaffRhythm r = StaffRhythm.quarter, ScaleDirection d = ScaleDirection.both}) {
  final seq = scaleSequence(tonic, t, octaves: octaves, direction: d);
  final up = d == ScaleDirection.down ? 0 : scaleMidis(tonic, t, octaves: octaves).length;
  return buildStaffScore(tonicMidi: tonic, type: t, sequence: seq, upCount: up, rhythm: r);
}

void main() {
  _fingerTests();
  group('layout na largura do celular', () {
    test('toda linha cabe na largura e o espaço de pauta fica legível (>= 6 px)', () {
      for (final w in [300.0, 340.0, 360.0, 390.0]) {
        for (final r in StaffRhythm.values) {
          for (final t in [ScaleType.melodicMinor, ScaleType.major, ScaleType.chromatic, ScaleType.dominantSeventh]) {
            for (var oct = 1; oct <= 3; oct++) {
              final lay = layoutStaff(_score(60, t, octaves: oct, r: r), widthPx: w);
              expect(lay.sp, greaterThanOrEqualTo(6.0));
              for (final s in lay.systems) {
                expect(s.width, lessThanOrEqualTo(lay.widthSp + 1e-6), reason: 'w=$w ${r.name} ${t.name} $oct');
                for (final e in s.events) {
                  expect(e.slotX1, lessThanOrEqualTo(lay.widthSp + 1e-6));
                  expect(e.x, greaterThanOrEqualTo(s.headerEnd));
                }
              }
            }
          }
        }
      }
    });

    test('toda nota aparece uma vez, na ordem, e as linhas cobrem o exercício todo', () {
      final sc = _score(62, ScaleType.melodicMinor, octaves: 2, r: StaffRhythm.triplet);
      final lay = layoutStaff(sc, widthPx: 360);
      final idx = [for (final s in lay.systems) for (final e in s.events) e.e.index];
      expect(idx, [for (var i = 0; i < sc.noteCount; i++) i]);
      expect(lay.systems.first.firstIndex, 0);
      expect(lay.systems.last.lastIndex, sc.noteCount - 1);
      for (var i = 0; i < sc.noteCount; i++) {
        expect(lay.systemOf(i), greaterThanOrEqualTo(0));
      }
    });

    test('notas avançam para a direita e não se sobrepõem', () {
      final lay = layoutStaff(_score(60, ScaleType.melodicMinor, octaves: 2, r: StaffRhythm.eighth), widthPx: 340);
      for (final s in lay.systems) {
        for (var i = 1; i < s.events.length; i++) {
          expect(s.events[i].slotX0, greaterThanOrEqualTo(s.events[i - 1].slotX1 - 1e-9));
          expect(s.events[i].x, greaterThan(s.events[i - 1].x));
        }
      }
    });

    test('só a primeira linha tem o compasso 4/4; a barra final fecha a última', () {
      final lay = layoutStaff(_score(60, ScaleType.major, octaves: 3), widthPx: 340);
      expect(lay.systems.length, greaterThan(1));
      expect(lay.systems.first.showTime, isTrue);
      expect(lay.systems.skip(1).any((s) => s.showTime), isFalse);
      expect(lay.systems.last.finalBarline, isTrue);
      expect(lay.systems.take(lay.systems.length - 1).any((s) => s.finalBarline), isFalse);
    });
  });

  group('hastes e barras', () {
    test('notas ligadas ficam todas com a haste para o mesmo lado e uma só barra por grupo', () {
      final lay = layoutStaff(_score(60, ScaleType.major, octaves: 2, r: StaffRhythm.eighth), widthPx: 360);
      for (final s in lay.systems) {
        final byGroup = <int, List<LaidEvent>>{};
        for (final e in s.events) {
          if (e.e.beamGroup != null) byGroup.putIfAbsent(e.e.beamGroup! * 1000 + e.e.bar, () => []).add(e);
        }
        expect(s.beams.length, byGroup.length);
        for (final g in byGroup.values) {
          expect(g.map((e) => e.stemUp).toSet(), hasLength(1));
        }
      }
    });

    test('toda haste tem comprimento mínimo e notas longe da pauta chegam à linha do meio', () {
      for (final r in StaffRhythm.values) {
        final lay = layoutStaff(_score(65, ScaleType.major, octaves: 3, r: r), widthPx: 360);
        for (final s in lay.systems) {
          for (final e in s.events) {
            if (!e.e.hasStem) continue;
            final len = e.stemUp ? e.stemTipY - e.y : e.y - e.stemTipY;
            expect(len, greaterThanOrEqualTo(2.0), reason: '${r.name} nota ${e.e.index}');
            if (e.stemUp) {
              expect(e.stemTipY, greaterThanOrEqualTo(2.0));
            } else {
              expect(e.stemTipY, lessThanOrEqualTo(2.0));
            }
          }
        }
      }
    });

    test('tercinas: um "3" por grupo de três', () {
      final sc = _score(60, ScaleType.major, octaves: 2, r: StaffRhythm.triplet);
      final lay = layoutStaff(sc, widthPx: 360);
      final groups = <int>{for (final e in sc.events) if (e.tripletGroup != null) e.tripletGroup!};
      expect(lay.systems.fold(0, (a, s) => a + s.tuplets.length), groups.length);
    });
  });

  group('extensão vertical e notas agudas', () {
    test('a linha sobe o bastante para as linhas suplementares e a clave', () {
      final lay = layoutStaff(_score(79, ScaleType.major, octaves: 2), widthPx: 360); // Sol5 até Sol7
      for (final s in lay.systems) {
        expect(s.top, greaterThanOrEqualTo(5.6));
        for (final e in s.events) {
          expect(s.top, greaterThan(e.y));
          expect(s.bottom, lessThan(e.y));
        }
      }
    });

    test('reservar a faixa de nomes aumenta a altura', () {
      final sc = _score(60, ScaleType.major);
      final a = layoutStaff(sc, widthPx: 360);
      final b = layoutStaff(sc, widthPx: 360, names: true);
      expect(b.systems.first.height, greaterThan(a.systems.first.height));
    });
  });
}

void _fingerTests() {
  group('dedilhado em cima das notas', () {
    StaffScore withFingers(StaffRhythm r, {int octaves = 1}) {
      final seq = scaleSequence(62, ScaleType.melodicMinor, octaves: octaves);
      return buildStaffScore(
          tonicMidi: 62,
          type: ScaleType.melodicMinor,
          sequence: seq,
          upCount: scaleMidis(62, ScaleType.melodicMinor, octaves: octaves).length,
          rhythm: r,
          fingers: [for (var i = 0; i < seq.length; i++) '${i % 5}']);
    }

    test('o número fica acima da pauta e acima da nota, da haste e do "3"', () {
      for (final r in StaffRhythm.values) {
        final lay = layoutStaff(withFingers(r, octaves: 2), widthPx: 358);
        for (final s in lay.systems) {
          for (final e in s.events) {
            expect(e.fingerY, isNotNull);
            expect(e.fingerY!, greaterThanOrEqualTo(4.9));
            expect(e.fingerY!, greaterThan(e.y + 0.5));
            if (e.e.hasStem && e.stemUp) expect(e.fingerY!, greaterThan(e.stemTipY));
            expect(s.top, greaterThan(e.fingerY! + 1.0));
          }
          for (final t in s.tuplets) {
            for (final e in s.events.where((e) => e.e.tripletGroup != null && e.stemUp)) {
              expect(e.fingerY!, greaterThan(t.baselineY));
            }
          }
        }
      }
    });

    test('sem dedilhado nada muda; com dedilhado a linha fica mais alta', () {
      final seq = scaleSequence(62, ScaleType.melodicMinor);
      final plain = buildStaffScore(tonicMidi: 62, type: ScaleType.melodicMinor, sequence: seq, upCount: 8);
      final lay0 = layoutStaff(plain, widthPx: 358);
      expect(lay0.systems.every((s) => s.events.every((e) => e.fingerY == null)), isTrue);
      final lay1 = layoutStaff(withFingers(StaffRhythm.quarter), widthPx: 358);
      expect(lay1.systems.first.top, greaterThan(lay0.systems.first.top));
    });

    test('a nota com número nunca fica mais apertada que o necessário e tudo cabe na largura', () {
      for (final w in [300.0, 358.0, 420.0]) {
        final lay = layoutStaff(withFingers(StaffRhythm.triplet, octaves: 3), widthPx: w);
        for (final s in lay.systems) {
          expect(s.width, lessThanOrEqualTo(lay.widthSp + 1e-6));
        }
      }
    });
  });
}
