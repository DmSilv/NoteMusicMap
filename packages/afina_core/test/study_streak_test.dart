import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

Map<String, double> _days(DateTime today, List<int> back, {double secs = 300}) =>
    {for (final b in back) studyDayKey(today.subtract(Duration(days: b))): secs};

void main() {
  final today = DateTime(2026, 11, 14);

  group('Dias seguidos com perdão de 1 dia', () {
    test('sem estudo nenhum: zero', () {
      expect(studyStreak({}, today).days, 0);
    });
    test('hoje ainda zerado não quebra: conta de ontem para trás', () {
      final s = studyStreak(_days(today, [1, 2, 3]), today);
      expect(s.days, 3);
      expect(s.forgave, isFalse);
    });
    test('hoje estudado entra na conta', () {
      expect(studyStreak(_days(today, [0, 1, 2]), today).days, 3);
    });
    test('menos de 1 minuto no dia não conta', () {
      expect(studyStreak(_days(today, [0, 1], secs: 59), today).days, 0);
    });
    test('um dia de folga é perdoado e não soma', () {
      final s = studyStreak(_days(today, [0, 1, 3, 4]), today); // faltou o dia 2
      expect(s.days, 4);
      expect(s.forgave, isTrue);
    });
    test('dois dias seguidos sem estudar quebram', () {
      final s = studyStreak(_days(today, [0, 1, 4, 5]), today); // faltaram 2 e 3
      expect(s.days, 2);
    });
    test('só perdoa uma vez a cada 7 dias', () {
      // estudou 0,1,3,5,6: faltaram 2 e 4; o 2º vazio vem logo depois do 1º perdão -> quebra
      final s = studyStreak(_days(today, [0, 1, 3, 5, 6]), today);
      expect(s.days, 3);
      // com 7 dias de distância entre os dois vazios, perdoa de novo
      final t = studyStreak(_days(today, [0, 1, 3, 4, 5, 6, 7, 8, 10]), today); // vazios: 2 e 9
      expect(t.days, 9);
    });
    test('estudar depois de um buraco grande começa uma sequência nova', () {
      expect(studyStreak(_days(today, [0, 10, 11, 12]), today).days, 1);
    });
  });

  group('Resumo da semana', () {
    test('soma os 7 dias, conta dias estudados e dias da meta, e compara com a semana anterior', () {
      final secs = {
        studyDayKey(today): 600.0, // 10 min
        studyDayKey(today.subtract(const Duration(days: 2))): 1800.0, // 30 min
        studyDayKey(today.subtract(const Duration(days: 8))): 1200.0, // 20 min (semana anterior)
      };
      final w = weekSummary(secs, today, 20);
      expect(w.minutes, 40);
      expect(w.previousMinutes, 20);
      expect(w.delta, 20);
      expect(w.daysStudied, 2);
      expect(w.goalDays, 1);
      expect(w.bestDayMinutes, 30);
      expect(w.empty, isFalse);
    });
    test('sem nenhum estudo: vazio', () {
      expect(weekSummary({}, today, 5).empty, isTrue);
    });
  });
}
