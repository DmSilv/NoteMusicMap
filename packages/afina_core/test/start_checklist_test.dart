import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  group('Comece por aqui (professor)', () {
    test('professor novo: nada feito, o próximo passo é adicionar um aluno; a tarefa vem antes do convite', () {
      final l = teacherStartItems(hasStudent: false, hasTask: false, delivered: false);
      expect(l.map((i) => i.id), ['student', 'task', 'link']);
      expect(startDoneCount(l), 0);
      expect(allStartDone(l), isFalse);
      expect(nextStartItem(l)!.id, 'student');
    });
    test('o próximo passo é o primeiro que falta, mesmo se um posterior já foi feito', () {
      final l = teacherStartItems(hasStudent: true, hasTask: false, delivered: true);
      expect(startDoneCount(l), 2);
      expect(nextStartItem(l)!.id, 'task');
    });
    test('tudo feito: lista completa e sem próximo passo', () {
      final l = teacherStartItems(hasStudent: true, hasTask: true, delivered: true);
      expect(allStartDone(l), isTrue);
      expect(nextStartItem(l), isNull);
      expect(startDoneCount(l), 3);
    });
  });

  group('o que o professor novo vê', () {
    bool basics({bool unlocked = false, bool student = false, bool task = false, bool advanced = false}) =>
        teacherBasicsOnly(unlocked: unlocked, hasStudent: student, hasTask: task, usesAdvanced: advanced);

    test('só o essencial até ter aluno E tarefa (ações só dele: não depende do aluno aceitar nada)', () {
      expect(basics(), isTrue);
      expect(basics(student: true), isTrue);
      expect(basics(task: true), isTrue);
      expect(basics(student: true, task: true), isFalse);
    });

    test('quem pediu para ver tudo, quem já usava e quem já usa uma ferramenta avançada vê tudo', () {
      expect(basics(unlocked: true), isFalse);
      expect(basics(advanced: true), isFalse);
    });
  });

  group('Seu primeiro passo (músico solo)', () {
    test('começa sem nada feito e o próximo passo é afinar', () {
      final l = soloStartItems(tuned: false, playedScale: false, studySeconds: 0);
      expect(l.map((i) => i.id), ['tune', 'scale', 'study']);
      expect(startDoneCount(l), 0);
      expect(nextStartItem(l)!.id, 'tune');
    });
    test('estudar só conta a partir de 5 minutos', () {
      expect(soloStartItems(tuned: true, playedScale: true, studySeconds: 299).last.done, isFalse);
      final l = soloStartItems(tuned: true, playedScale: true, studySeconds: 300);
      expect(l.last.done, isTrue);
      expect(allStartDone(l), isTrue);
    });
  });
}
