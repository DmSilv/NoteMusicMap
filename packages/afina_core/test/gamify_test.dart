import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

Map<String, double> _days(DateTime today, List<int> back, {double secs = 300}) =>
    {for (final b in back) studyDayKey(today.subtract(Duration(days: b))): secs};

SessionRecord _s(DateTime date, String title, double acc, {List<StepRecord> steps = const []}) =>
    SessionRecord(date: date, title: title, octaves: 1, zone: 5, accuracy: acc, meanAbsCents: 6, steps: steps);

void main() {
  final today = DateTime(2026, 11, 14); // sábado

  test('a meta da semana é a diária em 5 dias, com mínimo de 10', () {
    expect(weeklyGoalMinutes(20), 100);
    expect(weeklyGoalMinutes(1), 10);
  });

  test('a maior sequência de dias é contada sem perdão', () {
    expect(bestStudyRun({}), 0);
    expect(bestStudyRun(_days(today, [0, 1, 2, 5, 6])), 3);
    expect(bestStudyRun(_days(today, [0, 2, 4])), 1);
  });

  test('conquistas: nada feito, nada ganho; com estudo, as certas são ganhas', () {
    final none = achievements(secs: {}, sessions: [], today: today, dailyGoalMinutes: 20);
    expect(none.where((a) => a.done), isEmpty);
    final some = achievements(secs: _days(today, [0, 1, 2], secs: 1800), sessions: [_s(today, 'Sol maior', 0.85)], today: today, dailyGoalMinutes: 20);
    final done = {for (final a in some) a.id: a.done};
    expect(done['first'], isTrue);
    expect(done['run3'], isTrue);
    expect(done['run7'], isFalse);
    expect(done['acc80'], isTrue);
    expect(done['week'], isFalse); // 90 min < 100
    expect(some.firstWhere((a) => a.id == 'run7').progress, closeTo(3 / 7, 0.001));
  });

  test('o resumo da semana tem só números e notas curtas', () {
    final steps = [
      for (var i = 0; i < 4; i++) StepRecord(71, true, 0, 18.0), // Si desafinado
      for (var i = 0; i < 4; i++) StepRecord(67, true, 0, 3.0), // Sol afinado
      const StepRecord(69, true, 0, 30.0), // Lá com poucas leituras
    ];
    final r = buildStudyShare(
      secs: _days(today, [0, 1, 2, 3, 4], secs: 1008),
      sessions: [
        _s(today.subtract(const Duration(days: 5)), 'Sol maior', 0.62),
        _s(today, 'Sol maior', 0.78, steps: steps),
      ],
      today: today,
      dailyGoalMinutes: 20,
      tasksDone: 3,
      tasksTotal: 4,
      noteOf: (m) => const ['Dó', 'Dó#', 'Ré', 'Ré#', 'Mi', 'Fá', 'Fá#', 'Sol', 'Sol#', 'Lá', 'Lá#', 'Si'][m % 12],
    );
    expect(r['w'], '2026-11-09');
    expect(r['m'], 84);
    expect(r['g'], 100);
    expect(r['d'], 5);
    expect(r['a'], 70); // média de 62 e 78
    expect(r['tk'], 3);
    expect(r['tt'], 4);
    expect(r['n'], 5);
    expect(r['weak'], ['Si']);
    expect(r['up'], {'t': 'Sol maior', 'a': 62, 'b': 78});
  });

  test('sem escalas na semana: acerto -1 e nada de notas', () {
    final r = buildStudyShare(secs: {}, sessions: [], today: today, dailyGoalMinutes: 20, tasksDone: 0, tasksTotal: 0, noteOf: (m) => 'x');
    expect(r['a'], -1);
    expect(r['weak'], isEmpty);
    expect(r.containsKey('up'), isFalse);
  });
}
