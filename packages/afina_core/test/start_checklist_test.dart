import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  group('Comece por aqui (professor)', () {
    test('professor novo: nada feito, o próximo passo é vincular um aluno', () {
      final l = teacherStartItems(hasLinkedStudent: false, hasClass: false, hasTask: false);
      expect(l.map((i) => i.id), ['link', 'class', 'task']);
      expect(startDoneCount(l), 0);
      expect(allStartDone(l), isFalse);
      expect(nextStartItem(l)!.id, 'link');
    });
    test('o próximo passo é o primeiro que falta, mesmo se um posterior já foi feito', () {
      final l = teacherStartItems(hasLinkedStudent: true, hasClass: false, hasTask: true);
      expect(startDoneCount(l), 2);
      expect(nextStartItem(l)!.id, 'class');
    });
    test('tudo feito: lista completa e sem próximo passo', () {
      final l = teacherStartItems(hasLinkedStudent: true, hasClass: true, hasTask: true);
      expect(allStartDone(l), isTrue);
      expect(nextStartItem(l), isNull);
      expect(startDoneCount(l), 3);
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
