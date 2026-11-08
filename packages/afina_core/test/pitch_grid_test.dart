import 'package:afina_core/pitch_detector.dart';
import 'package:afina_core/pitch_grid.dart';
import 'package:afina_core/tuning.dart';
import 'package:test/test.dart';

PitchResult pr(double f, [double clarity = 0.97]) => PitchResult(f, clarity, 0.1);

void main() {
  const eq = TuningConfig();

  group('PitchTracker', () {
    test('só emite depois de 3 quadros na mesma nota', () {
      final t = PitchTracker();
      final f = etFreq(69, 440);
      expect(t.update(pr(f), eq), isNull);
      expect(t.update(pr(f), eq), isNull);
      final n = t.update(pr(f), eq);
      expect(n, isNotNull);
      expect(n!.midi, 69);
      expect(n.cents, closeTo(0, 0.01));
    });

    test('um quadro com erro de oitava é ignorado', () {
      final t = PitchTracker();
      final f = etFreq(69, 440);
      for (var i = 0; i < 6; i++) {
        t.update(pr(f), eq);
      }
      expect(t.update(pr(f * 2), eq), isNull); // outlier
      final n = t.update(pr(f), eq);
      expect(n!.midi, 69);
    });

    test('3 quadros em outra altura = nota nova', () {
      final t = PitchTracker();
      for (var i = 0; i < 6; i++) {
        t.update(pr(etFreq(69, 440)), eq);
      }
      TrackedNote? n;
      for (var i = 0; i < 8; i++) {
        n = t.update(pr(etFreq(71, 440)), eq) ?? n;
      }
      expect(n!.midi, 71);
    });

    test('histerese: 52 cents acima do Lá não vira Lá♯ de repente', () {
      final t = PitchTracker();
      for (var i = 0; i < 6; i++) {
        t.update(pr(etFreq(69, 440)), eq);
      }
      // Sobe devagar até +52 cents.
      TrackedNote? n;
      for (var c = 0.0; c <= 52; c += 4) {
        n = t.update(pr(etFreq(69 + c / 100, 440)), eq) ?? n;
      }
      expect(n!.midi, 69);
      expect(n.cents, greaterThan(40));
    });

    test('em Sol maior justo, o Si "baixo" é lido como Si afinado', () {
      const just = TuningConfig(
          system: TuningSystem.just, tonicPc: 7, anchor: Anchor.tonic);
      final t = PitchTracker();
      final fSi = targetFreq(71, just);
      TrackedNote? n;
      for (var i = 0; i < 6; i++) {
        n = t.update(pr(fSi), just) ?? n;
      }
      expect(n!.midi, 71);
      expect(n.cents.abs(), lessThan(0.05));
      // Com o sistema igual, a mesma nota estaria -13.7 cents.
      final t2 = PitchTracker();
      TrackedNote? n2;
      for (var i = 0; i < 6; i++) {
        n2 = t2.update(pr(fSi), eq) ?? n2;
      }
      expect(n2!.cents, closeTo(-13.69, 0.05));
    });

    test('silêncio prolongado zera o estado', () {
      final t = PitchTracker();
      for (var i = 0; i < 6; i++) {
        t.update(pr(440), eq);
      }
      for (var i = 0; i < 5; i++) {
        expect(t.update(null, eq), isNull);
      }
      expect(t.update(pr(440), eq), isNull); // precisa reconfirmar
    });
  });

  group('PitchGrid', () {
    test('média ponderada por clareza e tempo', () {
      final g = PitchGrid(history: HistoryMode.unlimited);
      g.add(69, 10, 1.0, 1.0, 1.0);
      g.add(69, -10, 1.0, 1.0, 2.0);
      expect(g.view(69, 2.0)!.avgCents, closeTo(0, 1e-9));
      g.add(69, 20, 1.0, 2.0, 4.0); // pesa o dobro
      expect(g.view(69, 4.0)!.avgCents, closeTo((10 - 10 + 40) / 4, 1e-9));
    });

    test('vibrato simétrico dá média ~0 (célula não "pisca")', () {
      final g = PitchGrid(history: HistoryMode.unlimited);
      for (var i = 0; i < 200; i++) {
        final c = 18 * (i.isEven ? 1 : -1);
        g.add(69, c.toDouble(), 0.98, 0.02, i * 0.02);
      }
      expect(g.view(69, 4)!.avgCents.abs(), lessThan(0.3));
    });

    test('histórico curto esquece rápido; ilimitado não', () {
      final shortG = PitchGrid(history: HistoryMode.short);
      final unl = PitchGrid(history: HistoryMode.unlimited);
      for (final g in [shortG, unl]) {
        g.add(60, 20, 1, 1, 0); // 1 s sendo +20
        g.add(60, -20, 1, 1, 10); // 10 s depois, 1 s em -20
      }
      expect(shortG.view(60, 10)!.avgCents, lessThan(-19));
      expect(unl.view(60, 10)!.avgCents, closeTo(0, 1e-9));
    });

    test('retenção: visível, depois some em fadeSeconds', () {
      final g = PitchGrid(holdSeconds: 5, fadeSeconds: 2);
      g.add(60, 5, 1, 1, 0);
      expect(g.view(60, 4)!.alpha, 1);
      expect(g.view(60, 6)!.alpha, closeTo(0.5, 1e-9));
      expect(g.view(60, 8), isNull);
    });

    test('confiança cresce com o tempo tocado', () {
      final g = PitchGrid();
      g.add(60, 0, 1, 0.1, 0.1);
      final low = g.view(60, 0.1)!.confidence;
      for (var i = 0; i < 30; i++) {
        g.add(60, 0, 1, 0.1, 0.2 + i * 0.1);
      }
      expect(g.view(60, 3.2)!.confidence, greaterThan(low));
      expect(g.view(60, 3.2)!.confidence, greaterThan(0.95));
    });
  });

  group('escalas e relatório', () {
    test('Sol maior: Sol Lá Si Dó Ré Mi Fá♯ Sol', () {
      final m = scaleMidis(55, ScaleType.major);
      expect(m, [55, 57, 59, 60, 62, 64, 66, 67]);
      final names = m.map((x) => noteName(x, eq)).toList();
      expect(names, ['Sol', 'Lá', 'Si', 'Dó', 'Ré', 'Mi', 'Fá♯', 'Sol']);
    });

    test('relatório marca afinada / grave / aguda / não tocada', () {
      final g = PitchGrid(history: HistoryMode.unlimited);
      final midis = scaleMidis(55, ScaleType.major);
      g.add(55, 1, 1, 1, 0); // afinada
      g.add(57, -14, 1, 1, 1); // grave
      g.add(59, 12, 1, 1, 2); // aguda
      // 60 não tocada
      g.add(62, 6, 1, 1, 3); // afinada (dentro da faixa padrão)
      final r = buildScaleReport(g, midis, eq, kInTuneCents, 4);
      expect(r.notes[0].status, NoteStatus.inTune);
      expect(r.notes[1].status, NoteStatus.flat);
      expect(r.notes[2].status, NoteStatus.sharp);
      expect(r.notes[3].status, NoteStatus.notPlayed);
      expect(r.notes[4].status, NoteStatus.inTune);
      expect(r.played, 4);
      expect(r.accuracy, closeTo(0.5, 1e-9));
      // O relatório aceita uma faixa explícita (o app usa só a padrão): +6 não passa em ±3.
      final estreita = buildScaleReport(g, midis, eq, 3, 4);
      expect(estreita.notes[4].status, NoteStatus.sharp);
      // A faixa padrão é única e fixa.
      expect(kInTuneCents, 10);
    });

    test('conta quantas vezes cada nota foi tocada (pausa = outra tocada)', () {
      final g = PitchGrid(holdSeconds: null);
      // Mesma nota tocada de forma contínua: 1 vez.
      for (var i = 0; i < 10; i++) {
        g.add(60, 2, 1, 0.05, i * 0.05);
      }
      expect(g.view(60, 1)!.plays, 1);
      // Pausa longa e volta: 2 vezes.
      g.add(60, 2, 1, 0.05, 3.0);
      expect(g.view(60, 3.1)!.plays, 2);
      // Quadros espaçados porque o aparelho engasgou (dt grande) não contam como nota nova.
      for (var i = 0; i < 5; i++) {
        g.add(60, 2, 1, 0.8, 4.0 + i * 0.8);
      }
      expect(g.view(60, 8.1)!.plays, 2);
      // Outra nota tem a própria contagem.
      g.add(64, 0, 1, 0.05, 3.2);
      expect(g.view(64, 3.3)!.plays, 1);
    });

    test('resumo da sessão: total de notas e % afinadas', () {
      final g = PitchGrid(holdSeconds: null);
      g.add(60, 3, 1, 1, 0); // afinada
      g.add(60, 3, 1, 1, 5); // segunda tocada
      g.add(62, 25, 1, 1, 6); // aguda
      g.add(64, -4, 1, 1, 7); // afinada
      final s = g.summary(10);
      expect(s.notes, 4);
      expect(s.distinct, 3);
      expect(s.inTune, 2);
      expect(s.accuracy, closeTo(2 / 3, 1e-9));
      // Sem nada tocado.
      expect(PitchGrid().summary(10).accuracy, 0);
    });

    test('relatório ignora a retenção da grade', () {
      final g = PitchGrid(holdSeconds: 1, fadeSeconds: 1);
      g.add(55, 0, 1, 1, 0);
      final r = buildScaleReport(g, [55], eq, kInTuneCents, 100);
      expect(r.notes.first.status, NoteStatus.inTune);
      expect(g.holdSeconds, 1);
    });
  });
}
