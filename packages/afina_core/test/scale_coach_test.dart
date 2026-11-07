import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

SessionRecord session(
  DateTime date, {
  required List<StepRecord> steps,
  double acc = 0.8,
  int oct = 1,
  double zone = 5,
}) =>
    SessionRecord(
      date: date,
      title: 'Sol maior',
      octaves: oct,
      zone: zone,
      accuracy: acc,
      meanAbsCents: 4,
      steps: steps,
    );

/// Passos de uma escala em que cada nota (pitch class) tem um viés fixo.
List<StepRecord> stepsWithBias(Map<int, double> biasByPc, {int reps = 1}) => [
      for (var r = 0; r < reps; r++)
        for (final e in biasByPc.entries) StepRecord(60 + e.key, true, 0, e.value),
    ];

void main() {
  group('sequência de escalas', () {
    test('Sol maior, 1 oitava: sobe 8 notas e desce 7 (15 no total)', () {
      final s = scaleSequence(55, ScaleType.major);
      expect(s, [55, 57, 59, 60, 62, 64, 66, 67, 66, 64, 62, 60, 59, 57, 55]);
    });

    test('1, 2 e 3 oitavas: 15, 29 e 43 notas (7*oitavas*2 + 1)', () {
      expect(scaleSequence(55, ScaleType.major, octaves: 1).length, 15);
      expect(scaleSequence(55, ScaleType.major, octaves: 2).length, 29);
      expect(scaleSequence(55, ScaleType.major, octaves: 3).length, 43);
    });

    test('3 oitavas vai de Sol3 a Sol6 e volta', () {
      final s = scaleSequence(55, ScaleType.major, octaves: 3);
      expect(s.first, 55);
      expect(s.reduce((a, b) => a > b ? a : b), 91);
      expect(s.last, 55);
    });

    test('menor melódica sobe com 6ª/7ª maiores e desce como menor natural', () {
      final s = scaleSequence(57, ScaleType.melodicMinor); // Lá
      expect(s.sublist(0, 8), [57, 59, 60, 62, 64, 66, 68, 69]);
      expect(s.sublist(8), [67, 65, 64, 62, 60, 59, 57]);
    });

    test('a sequência sempre termina na tônica e nunca repete o topo', () {
      for (final t in ScaleType.values) {
        for (final o in [1, 2, 3]) {
          final s = scaleSequence(60, t, octaves: o);
          expect(s.last, 60, reason: '$t $o');
          final top = 60 + 12 * o;
          expect(s.where((m) => m == top).length, 1, reason: '$t $o');
        }
      }
    });
  });

  group('exercício guiado', () {
    ScaleExercise make({int oct = 1}) => ScaleExercise(
        tonicMidi: 55, type: ScaleType.major, octaves: oct, zone: 5);

    /// Segura [midi] com [cents] por [secs] segundos, em quadros de 35 ms.
    StepResult? hold(ScaleExercise e, int? midi, double cents, double secs) {
      StepResult? last;
      for (var t = 0.0; t < secs; t += 0.035) {
        final r = e.feed(midi: midi, cents: cents, clarity: 0.97, dt: 0.035);
        if (r != null) last = r;
      }
      return last;
    }

    test('avança só quando a nota esperada é segurada o suficiente', () {
      final e = make();
      expect(hold(e, 55, 2, 0.2), isNull); // curto demais
      expect(e.index, 0);
      final r = hold(e, 55, 2, 0.5);
      expect(r, isNotNull);
      expect(e.index, 1);
      expect(r!.cents, closeTo(2, 0.5));
    });

    test('ignora notas erradas e silêncio', () {
      final e = make();
      hold(e, 60, 0, 1.0);
      hold(e, null, 0, 1.0);
      expect(e.index, 0);
    });

    test('segurar a nota anterior não conta para a próxima', () {
      final e = make();
      hold(e, 55, 0, 0.6);
      expect(e.index, 1);
      hold(e, 55, 0, 1.0); // ainda segurando a anterior
      expect(e.index, 1);
    });

    test('a média ignora o início (altura ainda assentando)', () {
      final e = make();
      // 0,1 s a +40 cents (escorregando) e depois estável em +2.
      hold(e, 55, 40, 0.1);
      final r = hold(e, 55, 2, 0.6)!;
      expect(r.cents!.abs(), lessThan(8));
    });

    test('pontuação: afinadas / total; puladas contam contra', () {
      final e = make();
      hold(e, 55, 1, 0.6); // afinada (±5)
      hold(e, 57, -3, 0.6); // afinada
      hold(e, 59, -14, 0.6); // fora
      e.skip(); // pulada
      final sc = e.score;
      expect(sc.inTune, 2);
      expect(sc.played, 3);
      expect(sc.total, 15);
      expect(sc.accuracy, closeTo(2 / 15, 1e-9));
      expect(sc.meanAbsCents, closeTo((1 + 3 + 14) / 3, 0.6));
    });

    test('termina ao completar todas as notas, subida e descida marcadas', () {
      final e = make();
      var n = 0;
      while (!e.finished) {
        final m = e.expected!;
        final asc = e.ascendingNow;
        final r = hold(e, m, 0, 0.6)!;
        expect(r.ascending, asc);
        n++;
      }
      expect(n, 15);
      expect(e.score.accuracy, 1.0);
      expect(e.results.where((r) => r.ascending).length, 8);
    });
  });

  group('treinador', () {
    final d0 = DateTime(2026, 11, 1);

    test('a regra do exemplo: notas Mi baixas viram "tente colocá-las mais altas"', () {
      // Mi = pitch class 4, sempre ~9 cents grave; as demais afinadas.
      final bias = {0: 1.0, 2: -1.0, 4: -9.0, 5: 0.0, 7: 1.0};
      final ss = [
        for (var i = 0; i < 4; i++) session(d0.add(Duration(days: i)), steps: stepsWithBias(bias))
      ].reversed.toList();
      final ins = analyzePractice(ss);
      final mi = ins.firstWhere((i) => i.key == 'bias-Mi');
      expect(mi.kind, InsightKind.warn);
      expect(mi.text, contains('Mi'));
      expect(mi.text, contains('baixas'));
      expect(mi.text, contains('mais altas'));
      expect(mi.text, contains('♭9'));
      expect(ins.any((i) => i.key == 'bias-Dó'), isFalse); // afinada não gera aviso
    });

    test('notas agudas pedem para baixar', () {
      final ss = [session(d0, steps: stepsWithBias({9: 8.0}, reps: 4))];
      final ins = analyzePractice(ss);
      final la = ins.firstWhere((i) => i.key == 'bias-Lá');
      expect(la.text, contains('altas'));
      expect(la.text, contains('mais baixas'));
    });

    test('poucas leituras não geram aviso (evita falso alarme)', () {
      final ss = [session(d0, steps: stepsWithBias({4: -12.0}, reps: 2))];
      expect(analyzePractice(ss).any((i) => i.key.startsWith('bias')), isFalse);
    });

    test('vieses pequenos dentro da zona são ignorados', () {
      final ss = [session(d0, steps: stepsWithBias({4: -2.0}, reps: 5))];
      expect(analyzePractice(ss).any((i) => i.key.startsWith('bias')), isFalse);
    });

    test('descida mais baixa que a subida é detectada', () {
      final steps = [
        for (var i = 0; i < 8; i++) StepRecord(55 + i, true, 0, 0.0),
        for (var i = 0; i < 8; i++) StepRecord(55 + i, false, 0, -8.0),
      ];
      final ins = analyzePractice([session(d0, steps: steps)]);
      final dir = ins.firstWhere((i) => i.key == 'dir');
      expect(dir.text, contains('descida'));
      expect(dir.text, contains('baixas'));
    });

    test('oitava aguda mais baixa que a grave é detectada', () {
      final steps = [
        for (var i = 0; i < 7; i++) StepRecord(55 + i, true, 0, 0.0),
        for (var i = 0; i < 7; i++) StepRecord(62 + i, true, 1, -9.0),
      ];
      final ins = analyzePractice([session(d0, steps: steps, oct: 2)]);
      expect(ins.any((i) => i.key == 'register'), isTrue);
    });

    test('cansaço: o desvio cresce na segunda metade', () {
      final steps = [
        for (var i = 0; i < 8; i++) StepRecord(55 + i, true, 0, 1.0),
        for (var i = 0; i < 8; i++) StepRecord(55 + i, false, 0, 8.0),
      ];
      final ss = [session(d0, steps: steps), session(d0.subtract(const Duration(days: 1)), steps: steps)];
      expect(analyzePractice(ss).any((i) => i.key == 'drift'), isTrue);
    });

    test('tendência: elogia a melhora e avisa a queda', () {
      SessionRecord s(int day, double acc) =>
          session(d0.add(Duration(days: day)), steps: const [], acc: acc);
      final up = [s(6, 0.9), s(5, 0.88), s(4, 0.9), s(3, 0.6), s(2, 0.62), s(1, 0.6)];
      expect(analyzePractice(up).any((i) => i.key == 'trend-up'), isTrue);
      final down = [s(6, 0.6), s(5, 0.58), s(4, 0.6), s(3, 0.9), s(2, 0.88), s(1, 0.9)];
      expect(analyzePractice(down).any((i) => i.key == 'trend-down'), isTrue);
    });

    test('muitas notas puladas geram dica', () {
      final steps = [
        for (var i = 0; i < 10; i++) StepRecord(55 + i, true, 0, i < 3 ? null : 1.0)
      ];
      expect(analyzePractice([session(d0, steps: steps)]).any((i) => i.key == 'skipped'), isTrue);
    });

    test('sem dados, não inventa nada', () {
      expect(analyzePractice([]), isEmpty);
      final one = analyzePractice([session(d0, steps: const [])]);
      expect(one.single.key, 'none');
    });

    test('avisos vêm antes de elogios e há no máximo 5', () {
      final bias = {0: -9.0, 2: -9.0, 4: -9.0, 5: -9.0, 7: -9.0, 9: -9.0, 11: -9.0};
      final ss = [
        session(d0, steps: stepsWithBias(bias, reps: 3), acc: 0.95),
      ];
      final ins = analyzePractice(ss);
      expect(ins.length, lessThanOrEqualTo(5));
      expect(ins.first.kind, InsightKind.warn);
    });

    test('flats: usa Si♭ em vez de Lá♯', () {
      final ss = [session(d0, steps: stepsWithBias({10: -9.0}, reps: 4))];
      expect(analyzePractice(ss, flats: true).first.text, contains('Si♭'));
      expect(analyzePractice(ss).first.text, contains('Lá♯'));
    });
  });

  group('persistência e resumo para IA', () {
    test('toJson/fromJson preserva tudo', () {
      final s = session(DateTime(2026, 11, 2), steps: [
        const StepRecord(55, true, 0, 1.25),
        const StepRecord(57, false, 1, null),
      ], acc: 0.7333);
      final back = SessionRecord.tryFromJson(s.toJson())!;
      expect(back.title, s.title);
      expect(back.accuracy, closeTo(0.7333, 1e-4));
      expect(back.steps.length, 2);
      expect(back.steps[0].cents, 1.25);
      expect(back.steps[1].cents, isNull);
      expect(back.steps[1].ascending, isFalse);
      expect(back.steps[1].octaveIndex, 1);
    });

    test('formato antigo é ignorado sem quebrar', () {
      expect(SessionRecord.tryFromJson({'scale': 'Sol maior', 'accuracy': 0.5}), isNull);
    });

    test('o resumo para IA tem números e nenhuma informação pessoal', () {
      final ss = [
        session(DateTime(2026, 11, 2), steps: stepsWithBias({4: -9.0}, reps: 3), acc: 0.8)
      ];
      final t = buildAiPrompt(ss, instrument: 'violino');
      expect(t, contains('violino'));
      expect(t, contains('80%'));
      expect(t, contains('Mi: -9.0'));
      expect(t.toLowerCase(), isNot(contains('@')));
    });
  });
}
