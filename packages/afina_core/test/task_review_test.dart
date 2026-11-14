import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime(2026, 11, 14, 10);
  Assignment task(String id, {bool? sent = true, bool done = false, bool reviewed = false, DateTime? created}) =>
      Assignment(id: id, title: 'T $id', created: created ?? DateTime(2026, 11, 12), sent: sent, done: done, reviewed: reviewed);

  group('professor decide sobre a tarefa (o aluno não precisa assinar)', () {
    test('para avaliar: só o que já foi enviado, não validado e recente', () {
      final s = Student(id: 's', name: 'Ana', tasks: [
        task('a'),
        task('naoEnviada', sent: false),
        task('semInfo', sent: null),
        task('feita', done: true),
        task('devolvida', reviewed: true),
        task('antiga', created: DateTime(2026, 9, 1)),
      ]);
      expect(toReview(s, now).map((t) => t.id), ['a']);
    });

    test('validar: finaliza como feita', () {
      final s = Student(id: 's', name: 'Ana', tasks: [task('a')]);
      expect(reviewTask(s, 'a', TaskReview.ok), isTrue);
      expect(s.tasks.first.done, isTrue);
      expect(toReview(s, now), isEmpty);
    });

    test('refazer: continua pendente e sai da lista até o próximo pacote', () {
      final s = Student(id: 's', name: 'Ana', tasks: [task('a')]);
      reviewTask(s, 'a', TaskReview.back);
      expect(s.tasks.first.done, isFalse);
      expect(s.tasks.first.reviewed, isTrue);
      expect(toReview(s, now), isEmpty);
      reopenReviews(s); // saiu a próxima aula
      expect(toReview(s, now).map((t) => t.id), ['a']);
    });

    test('levar para a próxima aula: volta a "a enviar", com a data de agora, e vai no próximo pacote', () {
      final s = Student(id: 's', name: 'Ana', tasks: [task('a', created: DateTime(2026, 11, 2))]);
      reviewTask(s, 'a', TaskReview.next, now: now);
      final t = s.tasks.first;
      expect(t.sent, isFalse);
      expect(t.created, now);
      expect(t.done, isFalse);
      expect(pendingTasks(s).map((x) => x.id), ['a']);
      expect(toReview(s, now), isEmpty); // ainda não foi enviada de novo
    });

    test('tarefa que não existe: falso', () {
      expect(reviewTask(Student(id: 's', name: 'Ana'), 'x', TaskReview.ok), isFalse);
    });

    test('a marca do professor nunca vai para o aluno', () {
      final l = SharedLesson(id: 'aula1', atMs: 1, tasks: [task('a', reviewed: true)]);
      final tarefa = (l.toWire()['tasks'] as List).first as Map;
      expect(tarefa.containsKey('rv'), isFalse);
      expect(task('a', reviewed: true).toJson()['rv'], isTrue);
      expect(Assignment.tryFrom(task('a', reviewed: true).toJson())!.reviewed, isTrue);
    });
  });

  group('levada para a próxima aula (visão do aluno)', () {
    SharedLesson lesson(String id, int at, List<Assignment> t, {String by = 'K7QM-4TXK'}) =>
        SharedLesson(id: id, teacherCode: by, atMs: at, durationSec: 1800, tasks: t);

    test('a cópia antiga some do plano; vale a da aula mais nova', () {
      final velha = lesson('aulaum', DateTime(2026, 11, 9).millisecondsSinceEpoch, [task('a'), task('b')]);
      final nova = lesson('aulados', DateTime(2026, 11, 13).millisecondsSinceEpoch, [task('b'), task('c')]);
      expect(carriedTaskKeys([velha, nova]), {'aulaum:b'});
      final p = buildWeekPlan([velha, nova], {}, now);
      expect(p.total, 3); // a (velha), b e c (nova); b da velha não conta de novo
      expect(p.week.map((g) => g.lesson.id), ['aulados', 'aulaum']);
      expect(p.week.last.tasks.map((t) => t.task.id), ['a']);
    });

    test('professores diferentes com o mesmo id de tarefa não se confundem', () {
      final a = lesson('aulaum', DateTime(2026, 11, 9).millisecondsSinceEpoch, [task('x')], by: 'AAAA-AAAA');
      final b = lesson('aulados', DateTime(2026, 11, 13).millisecondsSinceEpoch, [task('x')], by: 'BBBB-BBBB');
      expect(carriedTaskKeys([a, b]), isEmpty);
    });
  });
}
