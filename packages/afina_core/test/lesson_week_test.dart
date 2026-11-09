import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  standalone();
  final now = DateTime(2026, 11, 12, 15, 0); // quinta
  Assignment task(String id, [String title = 'Tarefa']) =>
      Assignment(id: id, title: '$title $id', created: DateTime(2026, 1, 1));
  SharedLesson lesson(String id, DateTime at, List<Assignment> tasks) =>
      SharedLesson(
          id: id, teacherCode: 'AAAA-AAAA', atMs: at.millisecondsSinceEpoch, durationSec: 1800, tasks: tasks);

  group('buildWeekPlan', () {
    test('sem aulas: plano vazio e progresso completo', () {
      final p = buildWeekPlan(const [], {}, now);
      expect(p.isEmpty, isTrue);
      expect(p.total, 0);
      expect(p.progress, 1);
    });

    test('aula de hoje e da semana entram, mais recente primeiro, com progresso', () {
      final hoje = lesson('hoje1', DateTime(2026, 11, 12, 9), [task('a'), task('b')]);
      final seg = lesson('seg01', DateTime(2026, 11, 9, 18), [task('c'), task('d'), task('e')]);
      final p = buildWeekPlan([seg, hoje], {'seg01:c', 'seg01:d'}, now);
      expect(p.week.map((g) => g.lesson.id), ['hoje1', 'seg01']);
      expect(p.total, 5);
      expect(p.done, 2);
      expect(p.open, 3);
      expect(p.progress, closeTo(0.4, 1e-9));
      expect(p.week.first.tasks.every((t) => t.today), isTrue);
      expect(p.week.last.tasks.any((t) => t.today), isFalse);
    });

    test('tarefa em aberto de uma aula que não é a última fica "atrasada"', () {
      final hoje = lesson('hoje1', DateTime(2026, 11, 12, 9), [task('a')]);
      final seg = lesson('seg01', DateTime(2026, 11, 9), [task('c'), task('d')]);
      final p = buildWeekPlan([hoje, seg], {'seg01:c'}, now);
      final byId = {for (final g in p.week) for (final t in g.tasks) t.task.id: t};
      expect(byId['a']!.overdue, isFalse); // da última aula
      expect(byId['c']!.overdue, isFalse); // feita
      expect(byId['d']!.overdue, isTrue); // aberta, de aula anterior
    });

    test('aula com mais de 7 dias: só aparece o que está em aberto, em "atrasadas"', () {
      final velha = lesson('velha', DateTime(2026, 10, 20), [task('x'), task('y')]);
      final hoje = lesson('hoje1', DateTime(2026, 11, 12), [task('a')]);
      final p = buildWeekPlan([velha, hoje], {'velha:x'}, now);
      expect(p.week.map((g) => g.lesson.id), ['hoje1']);
      expect(p.late.map((g) => g.lesson.id), ['velha']);
      expect(p.late.single.tasks.map((t) => t.task.id), ['y']); // a feita (x) não volta
      expect(p.open, 2);
    });

    test('aula antiga totalmente feita some do plano', () {
      final velha = lesson('velha', DateTime(2026, 10, 20), [task('x')]);
      final p = buildWeekPlan([velha], {'velha:x'}, now);
      expect(p.isEmpty, isTrue);
    });

    test('limite da semana: 7 dias atrás ainda entra, 8 dias atrás não', () {
      final sete = lesson('sete1', DateTime(2026, 11, 5, 8), [task('a')]);
      final oito = lesson('oito1', DateTime(2026, 11, 4, 22), [task('b')]);
      final p = buildWeekPlan([sete, oito], {}, now);
      expect(p.week.map((g) => g.lesson.id), ['sete1']);
      expect(p.late.map((g) => g.lesson.id), ['oito1']);
    });

    test('aula sem tarefas (só observações) não vira grupo', () {
      final p = buildWeekPlan([lesson('so-obs', DateTime(2026, 11, 12), const [])], {}, now);
      expect(p.isEmpty, isTrue);
    });

    test('marcar tudo como feito leva o progresso a 100%', () {
      final l = lesson('hoje1', DateTime(2026, 11, 12), [task('a'), task('b')]);
      final p = buildWeekPlan([l], {'hoje1:a', 'hoje1:b'}, now);
      expect(p.open, 0);
      expect(p.progress, 1);
    });
  });

  test('dia da semana em português', () {
    expect(fmtLessonDay(DateTime(2026, 11, 9)), 'segunda, 09/11');
    expect(fmtLessonDay(DateTime(2026, 11, 14)), 'sábado, 14/11');
    expect(fmtLessonDay(DateTime(2026, 11, 15)), 'domingo, 15/11');
  });
}

void standalone() {
  final now = DateTime(2026, 11, 12, 15, 0);
  Assignment task(String id) => Assignment(id: id, title: 'T $id', created: DateTime(2026, 1, 1));
  SharedLesson aula(String id, DateTime at, List<Assignment> t) =>
      SharedLesson(id: id, atMs: at.millisecondsSinceEpoch, durationSec: 1800, tasks: t);
  SharedLesson avulsa(String id, DateTime at, List<Assignment> t) =>
      SharedLesson(id: id, atMs: at.millisecondsSinceEpoch, durationSec: 0, tasks: t);

  group('tarefas avulsas no "Esta semana"', () {
    test('uma tarefa avulsa NÃO faz as da aula anterior virarem atraso', () {
      final plan = buildWeekPlan([
        aula('l1', DateTime(2026, 11, 9, 10), [task('a')]),
        avulsa('v1', DateTime(2026, 11, 11, 10), [task('b')]),
      ], {}, now);
      final all = [...plan.week, ...plan.late].expand((g) => g.tasks).toList();
      expect(all.length, 2);
      expect(all.any((t) => t.overdue), isFalse);
    });

    test('quando uma aula nova vem depois, o que ficou aberto (inclusive avulso) entra em atraso', () {
      final plan = buildWeekPlan([
        aula('l1', DateTime(2026, 11, 2, 10), [task('a')]),
        avulsa('v1', DateTime(2026, 11, 5, 10), [task('b')]),
        aula('l2', DateTime(2026, 11, 11, 10), [task('c')]),
      ], {}, now);
      final byId = {for (final g in [...plan.week, ...plan.late]) for (final t in g.tasks) t.task.id: t};
      expect(byId['a']!.overdue, isTrue);
      expect(byId['b']!.overdue, isTrue);
      expect(byId['c']!.overdue, isFalse);
    });

    test('só tarefas avulsas (sem nenhuma aula): nada em atraso', () {
      final plan = buildWeekPlan([avulsa('v1', DateTime(2026, 11, 11, 10), [task('b')])], {}, now);
      expect([...plan.week, ...plan.late].expand((g) => g.tasks).any((t) => t.overdue), isFalse);
    });
  });
}
