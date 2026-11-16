import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime(2026, 11, 14, 10);
  Assignment task(String id, {DateTime? claimed, bool done = false, bool? sent = true, DateTime? created}) =>
      Assignment(id: id, title: 'T $id', created: created ?? DateTime(2026, 11, 12), sent: sent, done: done, claimedAt: claimed);
  Student stu(String name, List<Assignment> tasks) => Student(id: name, name: name, tasks: tasks);

  group('fila de validação', () {
    test('só entram alunos com tarefa esperando decisão', () {
      final q = reviewQueue([
        stu('Ana', [task('a1')]),
        stu('Bruno', [task('b1', done: true)]),
        stu('Clara', [task('c1', sent: false)]),
      ], now);
      expect(q.map((g) => g.student.name), ['Ana']);
    });

    test('quem tem mais tarefas marcadas pelo aluno vem primeiro; empate pelo nome', () {
      final q = reviewQueue([
        stu('Zeca', [task('z1')]),
        stu('Ana', [task('a1', claimed: DateTime(2026, 11, 13))]),
        stu('Bia', [task('b1', claimed: DateTime(2026, 11, 13)), task('b2', claimed: DateTime(2026, 11, 13))]),
        stu('Caio', [task('c1')]),
      ], now);
      expect(q.map((g) => g.student.name), ['Bia', 'Ana', 'Caio', 'Zeca']);
    });

    test('dentro do aluno: marcadas primeiro (marcação mais antiga antes), depois as outras', () {
      final q = reviewQueue([
        stu('Ana', [
          task('x'),
          task('m2', claimed: DateTime(2026, 11, 13, 9)),
          task('m1', claimed: DateTime(2026, 11, 12, 20)),
          task('y'),
        ]),
      ], now);
      final g = q.single;
      expect(g.marked.map((t) => t.id), ['m1', 'm2']);
      expect(g.others.map((t) => t.id), ['x', 'y']);
      expect(g.all.map((t) => t.id), ['m1', 'm2', 'x', 'y']);
      expect(g.total, 4);
    });

    test('tarefa devolvida, feita ou antiga fica de fora; fila vazia sem ninguém', () {
      final s = stu('Ana', [
        task('feita', done: true),
        task('antiga', created: DateTime(2026, 9, 1)),
      ]);
      expect(reviewQueue([s], now), isEmpty);
      expect(reviewQueue(const [], now), isEmpty);
    });
  });
}
