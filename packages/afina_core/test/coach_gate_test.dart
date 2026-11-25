import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  group('treinador: quando abre', () {
    test('fechado até 60 minutos de estudo somados; depois abre', () {
      expect(coachGate(studySeconds: {}).open, isFalse);
      expect(coachGate(studySeconds: {}).left, kCoachUnlockMinutes);
      final g = coachGate(studySeconds: {'2026-11-20': 20 * 60, '2026-11-21': 25 * 60});
      expect(g.minutes, 45);
      expect(g.open, isFalse);
      expect(g.left, 15);
      expect(g.progress, closeTo(0.75, 0.001));
      expect(coachGate(studySeconds: {'a': 30 * 60, 'b': 30 * 60}).open, isTrue);
      expect(coachGate(studySeconds: {'a': 59 * 60 + 59}).open, isFalse, reason: 'segundo a segundo não arredonda para cima');
    });

    test('quem já usava o treinador não perde o acesso; tempo negativo não conta', () {
      expect(coachGate(studySeconds: {}, grandfathered: true).open, isTrue);
      expect(coachGate(studySeconds: {'a': -5000, 'b': 10 * 60}).minutes, 10);
    });
  });

  group('perguntas', () {
    test('o banco tem ids únicos e textos únicos', () {
      final ids = coachQuestionBank.map((q) => q.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(coachQuestionBank.map((q) => q.text).toSet().length, ids.length);
      expect(ids.length, greaterThanOrEqualTo(20));
    });

    test('três por dia, as mesmas no mesmo dia e diferentes de um dia para o outro', () {
      final d1 = DateTime(2026, 11, 24);
      final a = pickCoachQuestions(day: d1, hasSessions: true, hasTeacher: true).map((q) => q.id).toList();
      final b = pickCoachQuestions(day: d1, hasSessions: true, hasTeacher: true).map((q) => q.id).toList();
      expect(a, b);
      expect(a.length, 3);
      final dias = <String>{};
      for (var i = 0; i < 10; i++) {
        dias.add(pickCoachQuestions(day: d1.add(Duration(days: i)), hasSessions: true, hasTeacher: true).map((q) => q.id).join(','));
      }
      expect(dias.length, greaterThan(5), reason: 'a lista gira');
    });

    test('mistura temas e evita as feitas há pouco', () {
      final hoje = pickCoachQuestions(day: DateTime(2026, 11, 24), hasSessions: true, hasTeacher: true);
      expect(hoje.map((q) => q.theme).toSet().length, 3);
      final recent = {for (final q in hoje) q.id};
      final novas = pickCoachQuestions(day: DateTime(2026, 11, 24), recent: recent, hasSessions: true, hasTeacher: true);
      expect(novas.any((q) => recent.contains(q.id)), isFalse);
    });

    test('sem sessões não oferece as perguntas sobre "as minhas notas"; sem professor, as de aula', () {
      for (var i = 0; i < 40; i++) {
        final l = pickCoachQuestions(day: DateTime(2026, 11, 1).add(Duration(days: i)));
        for (final q in l) {
          expect(['afin_mesma', 'afin_agudas', 'afin_descida'].contains(q.id), isFalse);
          expect(q.theme == 'lesson', isFalse);
        }
        expect(l.length, 3);
      }
    });

    test('se quase tudo foi feito há pouco, ainda devolve três', () {
      final todas = {for (final q in coachQuestionBank) q.id};
      expect(pickCoachQuestions(day: DateTime(2026, 11, 24), recent: todas, hasSessions: true, hasTeacher: true).length, 3);
    });
  });
}

