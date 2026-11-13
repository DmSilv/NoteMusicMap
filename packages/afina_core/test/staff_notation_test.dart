import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

SpelledNote _n(int letter, int acc, int oct) => SpelledNote(letter, acc, oct);

/// Leitor independente: lê a partitura como um músico (armadura + acidentes valem até a barra de compasso)
/// e devolve a nota MIDI que cada evento representa. Se bater com a sequência do exercício, a escrita está certa.
List<int> _readBack(StaffScore s) {
  final out = <int>[];
  for (final bar in s.bars) {
    final state = <int, int>{};
    for (final e in bar) {
      final d = e.pos + 30;
      final letter = d % 7;
      final oct = d ~/ 7;
      final pk = oct * 7 + letter;
      if (e.accidental != null) state[pk] = e.accidental!;
      final acc = state[pk] ?? s.key.accidentalOf(letter);
      out.add(midiOfSpelled(SpelledNote(letter, acc, oct)));
    }
  }
  return out;
}

int _upCount(int tonic, ScaleType t, int octaves, ScaleDirection d) => switch (d) {
      ScaleDirection.down => 0,
      ScaleDirection.up => scaleMidis(tonic, t, octaves: octaves).length,
      ScaleDirection.both => scaleMidis(tonic, t, octaves: octaves).length,
    };

StaffScore _score(int tonic, ScaleType t, {int octaves = 1, ScaleDirection d = ScaleDirection.both, StaffRhythm r = StaffRhythm.quarter}) {
  final seq = scaleSequence(tonic, t, octaves: octaves, direction: d);
  return buildStaffScore(tonicMidi: tonic, type: t, sequence: seq, upCount: _upCount(tonic, t, octaves, d), rhythm: r);
}

void main() {
  group('posição na pauta (clave de Sol)', () {
    test('notas de referência', () {
      expect(staffPos(_n(2, 0, 4)), 0); // Mi4 = 1ª linha
      expect(staffPos(_n(4, 0, 4)), 2); // Sol4 = 2ª linha
      expect(staffPos(_n(6, 0, 4)), 4); // Si4 = 3ª linha
      expect(staffPos(_n(1, 0, 5)), 6); // Ré5 = 4ª linha
      expect(staffPos(_n(3, 0, 5)), 8); // Fá5 = 5ª linha
      expect(staffPos(_n(0, 0, 4)), -2); // Dó4 = linha suplementar abaixo
      expect(staffPos(_n(4, 0, 5)), 9); // Sol5 = espaço logo acima da pauta
      expect(staffPos(_n(5, 0, 5)), 10); // Lá5 = 1ª linha suplementar acima
      expect(staffPos(_n(0, 0, 6)), 12); // Dó6 = 2ª linha suplementar acima
      expect(staffPos(_n(2, 0, 6)), 14); // Mi6 = 3ª linha suplementar acima
      expect(staffPos(_n(6, 0, 3)), -3); // Si3
    });

    test('o acidente não muda a posição (Dó♯4 fica onde o Dó4 fica)', () {
      expect(staffPos(_n(0, 1, 4)), staffPos(_n(0, 0, 4)));
      expect(staffPos(_n(6, -1, 4)), staffPos(_n(6, 0, 4)));
    });

    test('linhas suplementares', () {
      expect(ledgerLines(0), isEmpty);
      expect(ledgerLines(8), isEmpty);
      expect(ledgerLines(9), isEmpty); // espaço acima da pauta
      expect(ledgerLines(-1), isEmpty); // espaço abaixo da pauta
      expect(ledgerLines(-2), [-2]);
      expect(ledgerLines(-3), [-2]);
      expect(ledgerLines(-4), [-2, -4]);
      expect(ledgerLines(10), [10]); // Lá5
      expect(ledgerLines(11), [10]); // Si5
      expect(ledgerLines(12), [10, 12]); // Dó6
      expect(ledgerLines(13), [10, 12]);
      expect(ledgerLines(14), [10, 12, 14]); // Mi6
      expect(ledgerLines(16), [10, 12, 14, 16]);
    });

    test('ida e volta: posição + acidente voltam à mesma nota', () {
      for (var m = 40; m <= 100; m++) {
        for (final tonic in [m]) {
          final sp = ScaleSpeller(tonic, ScaleType.chromatic);
          for (final asc in [true, false]) {
            final s = sp.spell(m, ascending: asc);
            expect(midiOfSpelled(noteAtStaffPos(staffPos(s), s.accidental)), m, reason: 'midi $m');
          }
        }
      }
    });
  });

  group('armadura de clave', () {
    test('tonalidades maiores (de Dó a Si)', () {
      const major = [0, -5, 2, -3, 4, -1, 6, 1, -4, 3, -2, 5];
      for (var pc = 0; pc < 12; pc++) {
        expect(keySignatureFor(60 + pc, ScaleType.major).fifths, major[pc], reason: 'maior pc $pc');
      }
    });

    test('tonalidades menores', () {
      const minor = [-3, 4, -1, -6, 1, -4, 3, -2, 5, 0, -5, 2];
      for (var pc = 0; pc < 12; pc++) {
        expect(keySignatureFor(60 + pc, ScaleType.naturalMinor).fifths, minor[pc], reason: 'menor pc $pc');
        expect(keySignatureFor(60 + pc, ScaleType.melodicMinor).fifths, minor[pc]);
        expect(keySignatureFor(60 + pc, ScaleType.minorTriad).fifths, minor[pc]);
      }
    });

    test('sinais nas posições certas (3 bemóis: Si Mi Lá; 2 sustenidos: Fá Dó)', () {
      final cm = keySignatureFor(60, ScaleType.melodicMinor).symbols;
      expect([for (final s in cm) s.pos], [4, 7, 3]);
      expect([for (final s in cm) s.letter], [6, 2, 5]);
      expect(cm.every((s) => s.accidental == -1), isTrue);
      final d = keySignatureFor(62, ScaleType.major).symbols;
      expect([for (final s in d) s.pos], [8, 5]);
      expect(d.every((s) => s.accidental == 1), isTrue);
    });

    test('7 bemóis e 7 sustenidos cabem na pauta (posições entre -1 e 10)', () {
      for (final f in [-7, 7]) {
        for (final s in KeySignature(f).symbols) {
          expect(s.pos, inInclusiveRange(1, 9));
        }
      }
    });

    test('7ª da dominante usa a tonalidade para onde resolve; cromática, a maior da tônica', () {
      expect(keySignatureFor(60, ScaleType.dominantSeventh).fifths, -1); // Dó7 -> Fá maior
      expect(keySignatureFor(67, ScaleType.dominantSeventh).fifths, 0); // Sol7 -> Dó maior
      expect(keySignatureFor(62, ScaleType.chromatic).fifths, 2);
    });
  });

  group('acidentes (Dó menor melódica, armadura com 3 bemóis)', () {
    test('subindo: Lá♮ e Si♮ ganham bequadro, Mi♭ não precisa (já está na armadura)', () {
      final s = _score(60, ScaleType.melodicMinor, r: StaffRhythm.eighth);
      final first = s.bars.first;
      expect([for (final e in first) e.note.name()], ['Dó', 'Ré', 'Mi♭', 'Fá', 'Sol', 'Lá', 'Si', 'Dó']);
      expect([for (final e in first) e.accidental], [null, null, null, null, null, 0, 0, null]);
    });

    test('descendo: Si♭ e Lá♭ já estão na armadura; no compasso seguinte voltam com acidente de precaução', () {
      final s = _score(60, ScaleType.melodicMinor, r: StaffRhythm.eighth);
      final second = s.bars[1];
      expect(second.first.note.name(), 'Si♭'); // o Dó5 do topo fecha o 1º compasso
      final bb = second.firstWhere((e) => e.note.name() == 'Si♭');
      final ab = second.firstWhere((e) => e.note.name() == 'Lá♭');
      expect(bb.accidental, -1);
      expect(bb.courtesy, isTrue);
      expect(ab.accidental, -1);
      expect(ab.courtesy, isTrue);
    });

    test('sem precaução, a armadura basta', () {
      final seq = scaleSequence(60, ScaleType.melodicMinor);
      final s = buildStaffScore(
          tonicMidi: 60, type: ScaleType.melodicMinor, sequence: seq, upCount: 8, rhythm: StaffRhythm.eighth, courtesy: false);
      expect(s.events.where((e) => e.courtesy), isEmpty);
      expect(s.events.firstWhere((e) => e.note.name() == 'Si♭').accidental, isNull);
    });

    test('Ré menor melódica: Si♮ e Dó♯ subindo; Si♭ (armadura) descendo', () {
      final s = _score(62, ScaleType.melodicMinor, r: StaffRhythm.eighth);
      expect(s.key.fifths, -1);
      final ev = s.events;
      final up = ev.where((e) => e.ascending);
      expect(up.firstWhere((e) => e.note.name() == 'Si').accidental, 0);
      expect(up.firstWhere((e) => e.note.name() == 'Dó♯').accidental, 1);
      final down = ev.where((e) => !e.ascending);
      expect(down.firstWhere((e) => e.note.name() == 'Si♭').courtesy, isTrue); // primeira vez do compasso
    });

    test('acidente vale até a barra de compasso (a mesma altura não repete o sinal)', () {
      // Sol♯ duas vezes no mesmo compasso: só a primeira leva o ♯
      final s = buildStaffScore(
          tonicMidi: 57, type: ScaleType.harmonicMinor, sequence: [64, 65, 68, 68, 69, 68, 65, 64], upCount: 8, rhythm: StaffRhythm.eighth);
      final firstBar = s.bars.first;
      final g = firstBar.where((e) => e.note.letter == 4 && e.note.accidental == 1).toList();
      expect(g, hasLength(3));
      expect(g.first.accidental, 1);
      expect(g.skip(1).map((e) => e.accidental), [null, null]);
    });
  });

  group('o que se lê é o que o exercício pede (todas as tonalidades e tipos)', () {
    for (final t in ScaleType.values) {
      for (final r in StaffRhythm.values) {
        test('${t.name} / ${r.name}: ida e volta', () {
          for (var tonic = 48; tonic <= 71; tonic++) {
            for (var oct = 1; oct <= 3; oct++) {
              for (final d in ScaleDirection.values) {
                final seq = scaleSequence(tonic, t, octaves: oct, direction: d);
                final s = _score(tonic, t, octaves: oct, d: d, r: r);
                expect(s.noteCount, seq.length);
                expect(_readBack(s), seq, reason: 'tônica $tonic, $oct oit., ${d.name}');
              }
            }
          }
        });
      }
    }
  });

  test('no máximo acidente duplo (♯♯ em Sol♯ menor harmônica); a tela desenha 𝄪 e 𝄫', () {
    for (final t in ScaleType.values) {
      for (var tonic = 48; tonic <= 71; tonic++) {
        final s = _score(tonic, t, octaves: 2);
        for (final e in s.events) {
          expect(e.note.accidental.abs(), lessThanOrEqualTo(2), reason: '${t.name} tônica $tonic nota ${e.index}');
          if (e.accidental != null) expect(e.accidental!.abs(), lessThanOrEqualTo(2));
        }
      }
    }
  });

  group('ritmo e compassos 4/4', () {
    test('todo compasso fecha 48 ticks, a nota final é longa, nada cruza a barra', () {
      for (final r in StaffRhythm.values) {
        for (var n = 1; n <= 80; n++) {
          final t = rhythmTicks(n, r);
          expect(t, hasLength(n));
          expect(t.fold(0, (a, b) => a + b) % kBarTicks, 0, reason: '${r.name} n=$n');
          expect(t.last, greaterThanOrEqualTo(12));
          var pos = 0;
          for (final k in t) {
            expect(pos % kBarTicks + k <= kBarTicks, isTrue, reason: '${r.name} n=$n atravessa o compasso');
            pos += k;
          }
        }
      }
    });

    test('a nota final cai sempre no início de um tempo', () {
      for (final r in StaffRhythm.values) {
        for (var n = 2; n <= 80; n++) {
          final t = rhythmTicks(n, r);
          final before = t.sublist(0, n - 1).fold(0, (a, b) => a + b);
          expect(before % 12, 0, reason: '${r.name} n=$n');
        }
      }
    });

    test('semínimas: 4 por compasso; tercinas: 12 por compasso em grupos de 3 (com o "3")', () {
      final q = _score(60, ScaleType.major, octaves: 2);
      expect(q.bars.first.map((e) => e.ticks), [12, 12, 12, 12]);
      final tr3 = _score(60, ScaleType.major, octaves: 2, r: StaffRhythm.triplet);
      expect(tr3.bars.first, hasLength(12));
      final groups = <int, int>{};
      for (final e in tr3.events) {
        if (e.tripletGroup != null) groups[e.tripletGroup!] = (groups[e.tripletGroup!] ?? 0) + 1;
      }
      expect(groups.values.every((c) => c == 3), isTrue);
    });

    test('colcheias ligadas de quatro em quatro; nenhuma barra com uma nota só', () {
      for (final r in [StaffRhythm.eighth, StaffRhythm.triplet]) {
        for (var n = 2; n <= 50; n++) {
          final s = buildStaffScore(tonicMidi: 60, type: ScaleType.major, sequence: List.generate(n, (i) => 60 + i), upCount: n, rhythm: r);
          final g = <int, List<StaffEvent>>{};
          for (final e in s.events) {
            if (e.beamGroup != null) g.putIfAbsent(e.beamGroup!, () => []).add(e);
          }
          for (final grp in g.values) {
            expect(grp.length, greaterThanOrEqualTo(2), reason: '${r.name} n=$n');
            expect(grp.map((e) => e.bar).toSet(), hasLength(1), reason: 'barra atravessa o compasso');
          }
          expect(s.events.last.beamGroup, isNull);
        }
      }
    });

    test('mínima pontuada e semibreve só aparecem como nota final', () {
      for (final r in StaffRhythm.values) {
        for (var n = 2; n <= 60; n++) {
          final t = rhythmTicks(n, r);
          expect(t.sublist(0, n - 1).where((k) => k > 24), isEmpty);
        }
      }
    });
  });

  test('uma única nota: vira semibreve', () {
    final s = buildStaffScore(tonicMidi: 60, type: ScaleType.major, sequence: [60], upCount: 1);
    expect(s.events.single.ticks, 48);
    expect(s.bars, hasLength(1));
  });
}
