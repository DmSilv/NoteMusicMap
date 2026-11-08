import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

TrackedNote note(int midi, [double cents = 0, double clarity = 0.9]) =>
    TrackedNote(midi, 440, 440, cents, clarity);

/// Alimenta a porta com [n] por [seconds], um quadro a cada 17 ms, desde [t0].
/// Devolve o instante final.
double feed(NoteGate g, PitchGrid grid, TrackedNote? n, double t0, double seconds) {
  var t = t0;
  while (t < t0 + seconds - 1e-9) {
    g.update(grid, n, 0.017, t);
    t += 0.017;
  }
  return t;
}

void main() {
  group('NoteGate', () {
    test('nota que se mantém entra na grade, com todo o tempo tocado', () {
      final grid = PitchGrid(holdSeconds: null);
      final g = NoteGate();
      feed(g, grid, note(55, 3), 0, 0.4);
      final v = grid.view(55, 0.4)!;
      expect(v.plays, 1);
      // o tempo dos primeiros quadros (antes de confirmar) não se perde
      expect(v.seconds, greaterThan(0.35));
    });

    test('toque curto demais (passagem, ruído) NÃO entra na grade nem no ×N', () {
      final grid = PitchGrid(holdSeconds: null);
      final g = NoteGate();
      var t = feed(g, grid, note(57), 0, 0.4); // Lá
      t = feed(g, grid, note(58), t, 0.034); // Lá♯ de passagem (2 quadros)
      t = feed(g, grid, note(59), t, 0.4); // Si
      g.close();
      expect(grid.view(58, t), isNull);
      expect(grid.view(57, t)!.plays, 1);
      expect(grid.view(59, t)!.plays, 1);
      expect(grid.summary(10).notes, 2);
      // e o diagnóstico lembra do que foi descartado
      expect(g.runs.map((r) => (r.midi, r.kept)).toList(),
          [(59, true), (58, false), (57, true)]);
    });

    test('Ré fantasma de ressonância (poucos quadros) é descartado', () {
      final grid = PitchGrid(holdSeconds: null);
      final g = NoteGate();
      var t = feed(g, grid, note(55), 0, 0.5); // Sol
      t = feed(g, grid, note(62, 0, 0.78), t, 0.04); // Ré por 40 ms
      t = feed(g, grid, note(55), t, 0.3); // volta ao Sol
      g.close();
      expect(grid.view(62, t), isNull);
      // Sol tocado, interrompido e retomado logo: segue sendo uma tocada só
      expect(grid.view(55, t)!.plays, 1);
    });

    test('semicolcheias de 125 ms são todas registradas', () {
      final grid = PitchGrid(holdSeconds: null);
      final g = NoteGate();
      var t = 0.0;
      for (final m in [60, 62, 64, 65, 67, 69, 71, 72]) {
        t = feed(g, grid, note(m), t, 0.125);
      }
      g.close();
      expect(grid.summary(10).distinct, 8);
      expect(grid.summary(10).notes, 8);
    });

    test('falha curta (queda do sinal) no meio da nota não a parte em duas', () {
      final grid = PitchGrid(holdSeconds: null);
      final g = NoteGate();
      var t = feed(g, grid, note(60), 0, 0.3);
      t = feed(g, grid, null, t, 0.08); // sinal some um instante
      t = feed(g, grid, note(60), t, 0.3);
      g.close();
      expect(grid.view(60, t)!.plays, 1);
      expect(g.runs.length, 1);
    });

    test('silêncio longo fecha a nota; voltar a ela depois conta outra tocada', () {
      final grid = PitchGrid(holdSeconds: null);
      final g = NoteGate();
      var t = feed(g, grid, note(60), 0, 0.3);
      t = feed(g, grid, null, t, 0.6);
      t = feed(g, grid, note(60), t, 0.3);
      g.close();
      expect(grid.view(60, t)!.plays, 2);
    });

    test('trinado rápido (notas de 70 ms): reconhece o padrão e registra todas, inclusive as primeiras', () {
      final grid = PitchGrid(holdSeconds: null);
      final g = NoteGate(keepRuns: 50);
      var t = 0.0;
      for (var i = 0; i < 12; i++) {
        t = feed(g, grid, note(i.isEven ? 69 : 71), t, 0.07);
      }
      g.close();
      final kept = g.runs.where((r) => r.kept).length;
      expect(kept, greaterThanOrEqualTo(11)); // 12 notas, no máximo 1 perdida
      expect(grid.view(69, t), isNotNull);
      expect(grid.view(71, t), isNotNull);
      expect(g.trilling(t - 0.01), isTrue);
    });

    test('um Ré fantasma entre dois Sol NÃO vira trinado', () {
      final grid = PitchGrid(holdSeconds: null);
      final g = NoteGate();
      var t = feed(g, grid, note(55), 0, 0.4);
      t = feed(g, grid, note(62), t, 0.04);
      t = feed(g, grid, note(55), t, 0.4);
      t = feed(g, grid, note(62), t, 0.04);
      t = feed(g, grid, note(55), t, 0.4);
      g.close();
      expect(grid.view(62, t), isNull);
      expect(g.trilling(t), isFalse);
    });

    test('passar por uma nota entre duas (Lá, Lá♯, Si) não é trinado', () {
      final grid = PitchGrid(holdSeconds: null);
      final g = NoteGate();
      var t = feed(g, grid, note(69), 0, 0.4);
      t = feed(g, grid, note(70), t, 0.04);
      t = feed(g, grid, note(71), t, 0.4);
      g.close();
      expect(grid.view(70, t), isNull);
      expect(g.trilling(t), isFalse);
    });

    test('o tempo mínimo é ajustável (Livre aceita notas mais curtas)', () {
      final strict = NoteGate(minSeconds: 0.09);
      final loose = NoteGate(minSeconds: 0.03);
      final g1 = PitchGrid(holdSeconds: null);
      final g2 = PitchGrid(holdSeconds: null);
      feed(strict, g1, note(60), 0, 0.05);
      feed(loose, g2, note(60), 0, 0.05);
      expect(g1.view(60, 1), isNull);
      expect(g2.view(60, 1), isNotNull);
    });
  });
}
